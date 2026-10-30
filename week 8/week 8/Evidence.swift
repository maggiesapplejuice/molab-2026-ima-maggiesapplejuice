import SwiftUI
import UIKit
import PhotosUI
import CoreLocation
import MessageUI
import AVKit

// MARK: - Model

struct EvidenceItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var fileName: String
    var date: Date
    var latitude: Double?
    var longitude: Double?
    // Only videos have these. Older evidence.json files without them still load,
    // because Codable treats missing optionals as nil.
    var thumbnailFileName: String?
    var duration: Double?

    var url: URL {
        fileURL(fileName)
    }

    var isVideo: Bool {
        fileName.hasSuffix(".mov")
    }

    // What to show in the grid: the photo itself, or a still frame of the video.
    var previewURL: URL {
        thumbnailFileName.map(fileURL) ?? url
    }

    var mapsURL: URL? {
        guard let latitude, let longitude else { return nil }
        return URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)")
    }
}

@Observable
@MainActor
final class EvidenceStore {
    var items: [EvidenceItem] = []
    let fileName = "evidence.json"

    init() {
        items = loadJSON([EvidenceItem].self, from: fileName) ?? []
    }

    // takenNow is true for camera photos. Photos picked from the library may be
    // older, so their stamp says when they were added instead of when they were taken.
    func add(_ image: UIImage, takenNow: Bool, location: CLLocation?) {
        let item = EvidenceItem(
            fileName: "evidence-\(UUID().uuidString).jpg",
            date: .now,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude
        )
        let time = item.date.formatted(date: .abbreviated, time: .standard)
        let lines = [takenNow ? "Taken \(time)" : "Added to SOS \(time)", placeLine(location)]
        let stamped = stampedImage(resizedImage(image, maxWidth: 1600), lines: lines)

        guard let data = stamped.jpegData(compressionQuality: 0.85) else { return }
        do {
            // completeFileProtection keeps the file encrypted while the phone is locked.
            try data.write(to: item.url, options: [.atomic, .completeFileProtection])
            items.append(item)
            save()
        } catch {
            print("Evidence save error:", error)
        }
    }

    // Moves a finished video into Documents and saves a still frame for the grid.
    func addVideo(from tempURL: URL, date: Date, location: CLLocation?) async {
        var item = EvidenceItem(
            fileName: "evidence-\(UUID().uuidString).mov",
            date: date,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude
        )
        do {
            try FileManager.default.moveItem(at: tempURL, to: item.url)
            // Same protection as the photos. AVAssetWriter can't set it while writing.
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: item.url.path())
        } catch {
            print("Video save error:", error)
            return
        }

        let asset = AVURLAsset(url: item.url)
        item.duration = try? await asset.load(.duration).seconds
        if let thumbnail = await videoThumbnail(asset),
           let data = thumbnail.jpegData(compressionQuality: 0.8) {
            let thumbnailFileName = "thumbnail-\(UUID().uuidString).jpg"
            if (try? data.write(to: fileURL(thumbnailFileName), options: [.atomic, .completeFileProtection])) != nil {
                item.thumbnailFileName = thumbnailFileName
            }
        }
        items.append(item)
        save()
    }

    func delete(_ item: EvidenceItem) {
        try? FileManager.default.removeItem(at: item.url)
        if let thumbnailFileName = item.thumbnailFileName {
            try? FileManager.default.removeItem(at: fileURL(thumbnailFileName))
        }
        items.removeAll { $0.id == item.id }
        save()
    }

    func save() {
        saveJSON(items, to: fileName)
    }
}

// "40.72950, -73.99650  (±12 m)", the second line of every stamp.
nonisolated func placeLine(_ location: CLLocation?) -> String {
    guard let location else { return "Location unavailable" }
    return String(format: "%.5f, %.5f  (±%.0f m)", location.coordinate.latitude, location.coordinate.longitude, location.horizontalAccuracy)
}

// Draws the time and place onto the bottom of the photo, so whoever receives it
// can see them too.
func stampedImage(_ image: UIImage, lines: [String]) -> UIImage {
    let size = image.size
    let bar = stampBar(width: size.width, lines: lines)

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.preferredRange = .standard
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
        image.draw(at: .zero)
        bar.draw(at: CGPoint(x: 0, y: size.height - bar.size.height))
    }
}

// The see-through black bar with the white text, on its own. Photos draw it onto
// the bottom of the picture and videos draw it onto every frame (VideoEvidence.swift).
// nonisolated because videos make it on a background thread.
nonisolated func stampBar(width: CGFloat, lines: [String]) -> UIImage {
    let text = lines.joined(separator: "\n") as NSString
    let padding = width * 0.03
    let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.monospacedDigitSystemFont(ofSize: max(14, width * 0.032), weight: .semibold),
        .foregroundColor: UIColor.white
    ]
    let textWidth = width - padding * 2
    let textHeight = ceil(text.boundingRect(
        with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
        options: .usesLineFragmentOrigin,
        attributes: attributes,
        context: nil
    ).height)
    let size = CGSize(width: width, height: textHeight + padding * 2)

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.preferredRange = .standard
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        UIColor.black.withAlphaComponent(0.55).setFill()
        // .normal draws on top of what's behind it. The default (.copy) would replace it.
        context.fill(CGRect(origin: .zero, size: size), blendMode: .normal)
        text.draw(
            with: CGRect(x: padding, y: padding, width: textWidth, height: textHeight),
            options: .usesLineFragmentOrigin,
            attributes: attributes,
            context: nil
        )
    }
}

// MARK: - Location

// Keeps the latest location while the alert screen is open.
@Observable
@MainActor
final class LocationFetcher {
    var current: CLLocation?
    var isDenied = false

    private var session: CLServiceSession?
    private var updates: Task<Void, Never>?

    func start() {
        // Creating the session asks for "While Using the App" permission the first time.
        session = CLServiceSession(authorization: .whenInUse)
        updates = Task {
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    isDenied = update.authorizationDenied || update.authorizationDeniedGlobally
                    if let location = update.location {
                        current = location
                    }
                }
            } catch {
                print("Location error:", error)
            }
        }
    }

    func stop() {
        updates?.cancel()
        session?.invalidate()
        session = nil
    }
}

// MARK: - Alert screen section

struct EvidenceCaptureSection: View {
    @Environment(EvidenceStore.self) private var evidence
    let contacts: [EmergencyContact]
    let message: String

    @State private var location = LocationFetcher()
    @State private var startedAt = Date.now
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var showingVideoCamera = false
    @State private var showingComposer = false
    @State private var stampingVideos = 0
    @State private var viewing: EvidenceItem?

    // Only this alert's photos, not ones from earlier alerts.
    private var items: [EvidenceItem] {
        evidence.items.filter { $0.date >= startedAt }
    }

    private var locationText: String {
        if let current = location.current {
            return String(format: "Your location: %.4f, %.4f", current.coordinate.latitude, current.coordinate.longitude)
        }
        return location.isDenied ? "Location is off. Photos and videos will only show the time." : "Finding your location…"
    }

    private var messageBody: String {
        var lines = [message]
        if let mapsURL = items.last?.mapsURL ?? mapsURL(for: location.current) {
            lines.append("My location: \(mapsURL.absoluteString)")
        }
        lines.append("\(evidenceCount(items).capitalized) from \(Date.now.formatted(date: .omitted, time: .shortened)).")
        return lines.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Record what's happening", systemImage: "camera.viewfinder")
                .font(.headline)
            Text(locationText)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))

            HStack {
                // The simulator has no camera, so these buttons only show on a real phone.
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showingCamera = true
                    } label: {
                        EmergencyActionLabel(title: "Photo", symbol: "camera.fill", tint: .secondaryAction)
                    }
                    Button {
                        showingVideoCamera = true
                    } label: {
                        EmergencyActionLabel(title: "Video", symbol: "video.fill", tint: .secondaryAction)
                    }
                }
                PhotosPicker(selection: $pickedPhotos, maxSelectionCount: 5, matching: .any(of: [.images, .videos])) {
                    EmergencyActionLabel(title: "Choose", symbol: "photo.on.rectangle", tint: .secondaryAction)
                }
            }

            if stampingVideos > 0 {
                Label {
                    Text(stampingVideos == 1 ? "Stamping video…" : "Stamping \(stampingVideos) videos…")
                } icon: {
                    ProgressView()
                        .tint(.white)
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
            }

            if !items.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(items) { item in
                            Button {
                                viewing = item
                            } label: {
                                EvidenceThumbnail(item: item)
                                    .frame(width: 76, height: 76)
                            }
                        }
                    }
                }
                sendButton
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { location.start() }
        .onDisappear { location.stop() }
        .onChange(of: pickedPhotos) {
            addPickedPhotos()
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(isPresented: $showingCamera) { image in
                evidence.add(image, takenNow: true, location: location.current)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showingVideoCamera) {
            EvidenceVideoCamera(location: location) { url, startedAt in
                Task {
                    await evidence.addVideo(from: url, date: startedAt, location: location.current)
                }
            }
        }
        .sheet(item: $viewing) { item in
            EvidenceViewer(item: item)
        }
        .sheet(isPresented: $showingComposer) {
            MessageComposer(
                isPresented: $showingComposer,
                recipients: contacts.map(\.digits),
                body: messageBody,
                attachments: items.map(\.url)
            )
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        let recipient = contacts.first?.name ?? "contact"
        let title = "Send \(evidenceCount(items)) to \(recipient)"
        // Messages with the photos attached and the contact filled in. Phones that
        // can't send texts (like the simulator) get the regular share sheet instead.
        if MFMessageComposeViewController.canSendText() && !contacts.isEmpty {
            Button {
                showingComposer = true
            } label: {
                EmergencyActionLabel(title: title, symbol: "paperplane.fill", tint: .secondaryAction)
            }
        } else {
            ShareLink(items: items.map(\.url), message: Text(messageBody)) {
                EmergencyActionLabel(title: "Share \(evidenceCount(items))", symbol: "square.and.arrow.up", tint: .secondaryAction)
            }
        }
    }

    private func addPickedPhotos() {
        let picked = pickedPhotos
        guard !picked.isEmpty else { return }
        pickedPhotos = []
        Task {
            for item in picked {
                if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                    await addPickedVideo(item)
                } else if let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) {
                    evidence.add(image, takenNow: false, location: location.current)
                }
            }
        }
    }

    // Library videos get the same stamp as photos from the library, drawn onto
    // every frame. It takes a few seconds, so the section shows a spinner meanwhile.
    private func addPickedVideo(_ item: PhotosPickerItem) async {
        stampingVideos += 1
        defer { stampingVideos -= 1 }
        let addedAt = Date.now
        let place = location.current
        let lines = ["Added to SOS \(addedAt.formatted(date: .abbreviated, time: .standard))", placeLine(place)]
        do {
            guard let picked = try await item.loadTransferable(type: PickedMovie.self) else { return }
            let stamped = URL.temporaryDirectory.appending(path: "stamped-\(UUID().uuidString).mov")
            try await exportStampedVideo(from: picked.url, to: stamped, lines: lines)
            try? FileManager.default.removeItem(at: picked.url)
            await evidence.addVideo(from: stamped, date: addedAt, location: place)
        } catch {
            print("Video import error:", error)
        }
    }

    private func mapsURL(for location: CLLocation?) -> URL? {
        guard let location else { return nil }
        return URL(string: "https://maps.apple.com/?ll=\(location.coordinate.latitude),\(location.coordinate.longitude)")
    }
}

struct EvidenceThumbnail: View {
    let item: EvidenceItem

    var body: some View {
        Color.gray.opacity(0.2)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = UIImage(contentsOfFile: item.previewURL.path()) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            // Videos get a play icon and their length, like in the Photos app.
            .overlay(alignment: .bottomLeading) {
                if item.isVideo {
                    Label(durationText(item.duration), systemImage: "play.fill")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel(item.isVideo ? "Video, \(durationText(item.duration))" : "Photo")
    }
}

// "0:12"
func durationText(_ seconds: Double?) -> String {
    Duration.seconds(seconds ?? 0).formatted(.time(pattern: .minuteSecond))
}

// "1 photo", "2 videos", "1 photo and 2 videos"
func evidenceCount(_ items: [EvidenceItem]) -> String {
    let videos = items.filter(\.isVideo).count
    let photos = items.count - videos
    var parts: [String] = []
    if photos > 0 { parts.append(photos == 1 ? "1 photo" : "\(photos) photos") }
    if videos > 0 { parts.append(videos == 1 ? "1 video" : "\(videos) videos") }
    return parts.joined(separator: " and ")
}

// MARK: - Safety kit section

// Evidence stays saved after "I'm safe", so you can find it later.
struct SavedEvidenceSection: View {
    @Environment(EvidenceStore.self) private var evidence
    @State private var viewing: EvidenceItem?

    var body: some View {
        if !evidence.items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Saved evidence")
                        .font(.headline)
                    Text("Photos and videos from your SOS alerts. They stay on this phone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                    ForEach(evidence.items.reversed()) { item in
                        Button {
                            viewing = item
                        } label: {
                            EvidenceThumbnail(item: item)
                        }
                        .contextMenu {
                            ShareLink(item: item.url)
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                evidence.delete(item)
                            }
                        }
                    }
                }
                Text("Tap to view. Touch and hold to share or delete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .sheet(item: $viewing) { item in
                EvidenceViewer(item: item)
            }
        }
    }
}

// Full-size photo, or the video with play controls.
struct EvidenceViewer: View {
    @Environment(\.dismiss) private var dismiss
    let item: EvidenceItem
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            Group {
                if item.isVideo {
                    VideoPlayer(player: player)
                        .onAppear {
                            player = AVPlayer(url: item.url)
                            player?.play()
                        }
                        .onDisappear { player?.pause() }
                } else if let image = UIImage(contentsOfFile: item.url.path()) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .navigationTitle(item.date.formatted(date: .abbreviated, time: .shortened))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: item.url)
                }
            }
        }
    }
}

// MARK: - UIKit wrappers
// SwiftUI has no camera or text message views yet, so these wrap the UIKit ones,
// like the UIViewControllerRepresentable in the 07-PhotoPickBlender demo.

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

struct MessageComposer: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let recipients: [String]
    let body: String
    let attachments: [URL]

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.recipients = recipients
        composer.body = body
        for url in attachments {
            composer.addAttachmentURL(url, withAlternateFilename: nil)
        }
        composer.messageComposeDelegate = context.coordinator
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let parent: MessageComposer

        init(_ parent: MessageComposer) {
            self.parent = parent
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            parent.isPresented = false
        }
    }
}
