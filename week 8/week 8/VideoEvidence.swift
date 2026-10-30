import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreLocation
import CoreTransferable
import UniformTypeIdentifiers
import os

// Evidence videos. Like the 08-CameraRecorder demo, every camera frame goes
// through Core Image before it's shown and recorded. Here the "filter" draws the
// time and GPS location onto the frame, so the video proves when and where it was
// filmed, and an optional night boost brightens dark scenes.

// MARK: - Frame processing

// Brightens a dark street so faces and plates are easier to see. exposureAdjust
// multiplies (so blacks stay black, like the Week 7 lesson), and noise reduction
// cleans up the grain that brightening brings out.
nonisolated func nightBoosted(_ image: CIImage) -> CIImage {
    let exposure = CIFilter.exposureAdjust()
    exposure.inputImage = image
    exposure.ev = 1.4
    let noise = CIFilter.noiseReduction()
    noise.inputImage = exposure.outputImage
    noise.noiseLevel = 0.03
    noise.sharpness = 0.5
    return noise.outputImage?.cropped(to: image.extent) ?? image
}

// Puts the stamp bar on the bottom of a frame. Making the bar is the slow part,
// and its text only changes once a second, so the last one is kept and reused
// for the ~30 frames in between.
nonisolated final class StampCache: @unchecked Sendable {
    private let lock = NSLock()
    private var key = ""
    private var bar: CIImage?

    func stamped(_ frame: CIImage, lines: [String]) -> CIImage {
        let extent = frame.extent
        let newKey = "\(extent.width)\n" + lines.joined(separator: "\n")
        lock.lock()
        defer { lock.unlock() }
        if newKey != key || bar == nil {
            bar = CIImage(image: stampBar(width: extent.width, lines: lines))
            key = newKey
        }
        guard let bar else { return frame }
        // Core Image's y axis starts at the bottom, so this is the bottom edge.
        return bar
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .composited(over: frame)
    }
}

// MARK: - Library videos

// Stamps every frame of a video from the photo library and saves the copy to
// `destination`. AVFoundation hands each frame to the closure as a CIImage.
nonisolated func exportStampedVideo(from source: URL, to destination: URL, lines: [String]) async throws {
    let asset = AVURLAsset(url: source)
    let stamps = StampCache()
    let composition = try await AVVideoComposition.videoComposition(with: asset) { request in
        request.finish(with: stamps.stamped(request.sourceImage, lines: lines), context: nil)
    }
    // 720p keeps it small enough to text.
    guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
        throw CocoaError(.featureUnsupported)
    }
    export.videoComposition = composition
    try await export.export(to: destination, as: .mov)
}

// A still frame for the evidence grid.
nonisolated func videoThumbnail(_ asset: AVAsset) async -> UIImage? {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 400, height: 400)
    guard let (image, _) = try? await generator.image(at: .zero) else { return nil }
    return UIImage(cgImage: image)
}

// PhotosPicker can only hand over a video as a file, so this copies it somewhere
// we're allowed to keep it (the picker deletes its copy afterwards).
nonisolated struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = URL.temporaryDirectory.appending(path: "picked-\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

// MARK: - Camera recorder

// Runs the camera and microphone, processes every frame and writes the result to
// a .mov file with AVAssetWriter. All the camera work happens on `queue` (a
// background thread), so this class is nonisolated, unlike the rest of the app.
nonisolated final class EvidenceVideoRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    // Videos stop at one minute so they're small enough to text.
    static let maxDuration = 60.0

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "evidence-video")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let context = CIContext()
    private let stamps = StampCache()

    private let onPreview: @MainActor (CGImage) -> Void
    // The finished file (nil if it failed) and when its first frame was filmed.
    private let onFinished: @MainActor (URL?, Date) -> Void
    private let onCameraError: @MainActor () -> Void

    // Changed from the main thread while frames are being processed, so a lock
    // keeps the two threads from reading and writing them at the same time.
    private struct Settings {
        var location: CLLocation?
        var nightBoost = false
    }
    private let settings = OSAllocatedUnfairLock(initialState: Settings())

    // Only used on `queue`.
    private var isConfigured = false
    private var errorObserver: NSObjectProtocol?
    private var hasAudio = false
    private var pendingURL: URL?
    private var writer: AVAssetWriter?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    private var firstFrameTime: CMTime?
    private var filmedAt = Date.now

    init(
        onPreview: @escaping @MainActor (CGImage) -> Void,
        onFinished: @escaping @MainActor (URL?, Date) -> Void,
        onCameraError: @escaping @MainActor () -> Void
    ) {
        self.onPreview = onPreview
        self.onFinished = onFinished
        self.onCameraError = onCameraError
    }

    deinit {
        if let errorObserver {
            NotificationCenter.default.removeObserver(errorObserver)
        }
    }

    func setLocation(_ location: CLLocation?) {
        settings.withLock { $0.location = location }
    }

    func setNightBoost(_ on: Bool) {
        settings.withLock { $0.nightBoost = on }
    }

    func start(withAudio: Bool) {
        queue.async { [self] in
            if !isConfigured {
                configure(withAudio: withAudio)
            }
            session.startRunning()
        }
    }

    // Stops the camera. If it was recording, the video is finished and saved first.
    func stop() {
        queue.async { [self] in
            finishRecording()
            session.stopRunning()
        }
    }

    func startRecording() {
        let url = URL.temporaryDirectory.appending(path: "recording-\(UUID().uuidString).mov")
        // The writer is made when the next frame arrives, so it can use that
        // frame's exact size and time.
        queue.async { [self] in
            pendingURL = url
        }
    }

    func stopRecording() {
        queue.async { [self] in
            finishRecording()
        }
    }

    private func configure(withAudio: Bool) {
        session.beginConfiguration()
        // 720p, the same size as stamped library videos.
        session.sessionPreset = .hd1280x720

        // The back camera, to film what's happening rather than your own face.
        if let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: camera),
           session.canAddInput(input) {
            session.addInput(input)
        }
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        // Turn the frames upright for holding the phone in portrait, so the stamp
        // is drawn along the bottom instead of up the side.
        if let connection = videoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        if withAudio,
           let microphone = AVCaptureDevice.default(for: .audio),
           let input = try? AVCaptureDeviceInput(device: microphone),
           session.canAddInput(input) {
            session.addInput(input)
            audioOutput.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(audioOutput) {
                session.addOutput(audioOutput)
                hasAudio = true
            }
        }
        session.commitConfiguration()
        isConfigured = true

        // If the camera can't start (another app is using it, or the simulator),
        // say so instead of showing a spinner forever.
        errorObserver = NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [onCameraError] _ in
            MainActor.assumeIsolated { onCameraError() }
        }
    }

    // Called for every camera frame (about 30 a second) and every bit of sound.
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === audioOutput {
            appendAudio(sampleBuffer)
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let current = settings.withLock { $0 }

        var frame = CIImage(cvPixelBuffer: pixelBuffer)
        if current.nightBoost {
            frame = nightBoosted(frame)
        }
        let lines = ["Filmed \(Date.now.formatted(date: .abbreviated, time: .standard))", placeLine(current.location)]
        frame = stamps.stamped(frame, lines: lines)

        if let pendingURL {
            beginWriting(to: pendingURL, size: frame.extent.size, at: time)
            self.pendingURL = nil
        }
        appendVideo(frame, at: time)

        // The preview shows the processed frame, so you see exactly what's recorded.
        if let image = context.createCGImage(frame, from: frame.extent) {
            DispatchQueue.main.async { [onPreview] in
                MainActor.assumeIsolated { onPreview(image) }
            }
        }
    }

    private func beginWriting(to url: URL, size: CGSize, at time: CMTime) {
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height)
            ])
            videoInput.expectsMediaDataInRealTime = true
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ])
            writer.add(videoInput)

            if hasAudio {
                let audioInput = AVAssetWriterInput(
                    mediaType: .audio,
                    outputSettings: audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov)
                )
                audioInput.expectsMediaDataInRealTime = true
                if writer.canAdd(audioInput) {
                    writer.add(audioInput)
                    self.audioInput = audioInput
                }
            }

            writer.startWriting()
            // The video starts at this frame's time, so it starts exactly when the
            // first frame was filmed.
            writer.startSession(atSourceTime: time)
            self.writer = writer
            self.adaptor = adaptor
            firstFrameTime = time
            filmedAt = .now
        } catch {
            print("Recording error:", error)
            DispatchQueue.main.async { [onFinished] in
                MainActor.assumeIsolated { onFinished(nil, .now) }
            }
        }
    }

    private func appendVideo(_ frame: CIImage, at time: CMTime) {
        guard let writer, let adaptor, let firstFrameTime,
              adaptor.assetWriterInput.isReadyForMoreMediaData,
              let pool = adaptor.pixelBufferPool else { return }

        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return }
        context.render(frame, to: buffer)
        adaptor.append(buffer, withPresentationTime: time)

        if writer.status == .failed || (time - firstFrameTime).seconds >= Self.maxDuration {
            finishRecording()
        }
    }

    private func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        // Sound from before the first video frame is skipped, so they line up.
        guard let audioInput, let firstFrameTime,
              CMSampleBufferGetPresentationTimeStamp(sampleBuffer) >= firstFrameTime,
              audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sampleBuffer)
    }

    private func finishRecording() {
        let hadPendingRecording = pendingURL != nil
        pendingURL = nil
        guard let writer else {
            // Stopped before a single frame came in, so there's nothing to save.
            if hadPendingRecording {
                DispatchQueue.main.async { [onFinished] in
                    MainActor.assumeIsolated { onFinished(nil, .now) }
                }
            }
            return
        }
        self.writer = nil
        adaptor?.assetWriterInput.markAsFinished()
        audioInput?.markAsFinished()
        adaptor = nil
        audioInput = nil
        firstFrameTime = nil

        // finishWriting calls back on another thread. Nothing else uses the writer
        // after this point, so it's safe to read its status there.
        nonisolated(unsafe) let finishedWriter = writer
        finishedWriter.finishWriting { [onFinished, filmedAt] in
            let url = finishedWriter.status == .completed ? finishedWriter.outputURL : nil
            if let error = finishedWriter.error {
                print("Recording error:", error)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { onFinished(url, filmedAt) }
            }
        }
    }
}

// MARK: - Recording screen

// Full screen camera for the alert screen's "Video" button.
struct EvidenceVideoCamera: View {
    @Environment(\.dismiss) private var dismiss
    let location: LocationFetcher
    // The finished file, and when filming started.
    let onSave: (URL, Date) -> Void

    @State private var recorder: EvidenceVideoRecorder?
    @State private var preview: CGImage?
    @State private var recordingSince: Date?
    @State private var nightBoost = false
    @State private var cameraDenied = false
    @State private var cameraFailed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let preview {
                Image(decorative: preview, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else if cameraDenied || cameraFailed {
                Text(cameraDenied
                     ? "Camera access is off. Turn it on in Settings to record video."
                     : "The camera couldn't start. You can still choose a video or call for help.")
                    .multilineTextAlignment(.center)
                    .padding(32)
            } else {
                ProgressView()
                    .tint(.white)
            }

            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding()
        }
        .foregroundStyle(.white)
        .task {
            await startCamera()
        }
        .onChange(of: location.current) {
            recorder?.setLocation(location.current)
        }
        .onChange(of: nightBoost) {
            recorder?.setNightBoost(nightBoost)
        }
        .onDisappear {
            // Closing while recording still saves the video. Evidence shouldn't be
            // lost because someone swiped the wrong way.
            recorder?.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sensoryFeedback(trigger: recordingSince) { _, newValue in
            newValue == nil ? .stop : .start
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .padding(12)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .accessibilityLabel(recordingSince == nil ? "Close" : "Stop and close")

            Spacer()

            if let recordingSince {
                // Redraws once a second to count up.
                TimelineView(.periodic(from: recordingSince, by: 1)) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(recordingSince)
                    Label("\(durationText(elapsed)) / \(durationText(EvidenceVideoRecorder.maxDuration))", systemImage: "record.circle")
                        .font(.headline.monospacedDigit())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.urgentAction, in: Capsule())
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                nightBoost.toggle()
            } label: {
                Image(systemName: nightBoost ? "moon.stars.fill" : "moon.stars")
                    .font(.title3)
                    .frame(width: 56, height: 56)
                    .background(nightBoost ? Color.white : Color.secondaryAction, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(nightBoost ? .black : .white)
            }
            .accessibilityLabel("Night boost")
            .accessibilityValue(nightBoost ? "On" : "Off")

            // A wide button, not a round shutter: in this app circles are held
            // (SOS) and rectangles are tapped.
            Button {
                toggleRecording()
            } label: {
                EmergencyActionLabel(
                    title: recordingSince == nil ? "Start recording" : "Stop and save",
                    symbol: recordingSince == nil ? "record.circle" : "stop.fill",
                    tint: .secondaryAction
                )
            }
            .disabled(recorder == nil || cameraFailed)
            .opacity(recorder == nil || cameraFailed ? 0.4 : 1)
        }
    }

    private func startCamera() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            cameraDenied = true
            return
        }
        // Without the microphone it still records, just without sound.
        let microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)

        let recorder = EvidenceVideoRecorder { image in
            preview = image
        } onFinished: { url, filmedAt in
            if let url {
                onSave(url, filmedAt)
            }
            recordingSince = nil
            UIApplication.shared.isIdleTimerDisabled = false
            dismiss()
        } onCameraError: {
            cameraFailed = true
        }
        recorder.setLocation(location.current)
        recorder.setNightBoost(nightBoost)
        recorder.start(withAudio: microphoneAllowed)
        self.recorder = recorder
    }

    private func toggleRecording() {
        if recordingSince == nil {
            recordingSince = .now
            // Keep the screen from locking in the middle of a recording.
            UIApplication.shared.isIdleTimerDisabled = true
            recorder?.startRecording()
        } else {
            recorder?.stopRecording()
        }
    }
}
