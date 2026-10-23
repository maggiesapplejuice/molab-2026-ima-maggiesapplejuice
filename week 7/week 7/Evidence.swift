import SwiftUI
import UIKit
import PhotosUI
import CoreLocation
import MessageUI

// MARK: - Model

struct EvidenceItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var fileName: String
    var date: Date
    var latitude: Double?
    var longitude: Double?

    var url: URL {
        fileURL(fileName)
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
        var place = "Location unavailable"
        if let location {
            place = String(format: "%.5f, %.5f  (±%.0f m)", location.coordinate.latitude, location.coordinate.longitude, location.horizontalAccuracy)
        }
        let lines = [takenNow ? "Taken \(time)" : "Added to SOS \(time)", place]
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

    func delete(_ item: EvidenceItem) {
        try? FileManager.default.removeItem(at: item.url)
        items.removeAll { $0.id == item.id }
        save()
    }

    func save() {
        saveJSON(items, to: fileName)
    }
}

// Draws the time and place onto the bottom of the photo, so whoever receives it
// can see them too.
func stampedImage(_ image: UIImage, lines: [String]) -> UIImage {
    let size = image.size
    let text = lines.joined(separator: "\n") as NSString
    let padding = size.width * 0.03
    let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.monospacedDigitSystemFont(ofSize: max(14, size.width * 0.032), weight: .semibold),
        .foregroundColor: UIColor.white
    ]
    let textWidth = size.width - padding * 2
    let textHeight = ceil(text.boundingRect(
        with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
        options: .usesLineFragmentOrigin,
        attributes: attributes,
        context: nil
    ).height)
    let barHeight = textHeight + padding * 2

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.preferredRange = .standard
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        image.draw(at: .zero)
        UIColor.black.withAlphaComponent(0.55).setFill()
        // .normal draws on top of the photo. The default (.copy) would replace it.
        context.fill(CGRect(x: 0, y: size.height - barHeight, width: size.width, height: barHeight), blendMode: .normal)
        text.draw(
            with: CGRect(x: padding, y: size.height - barHeight + padding, width: textWidth, height: textHeight),
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
    @State private var showingComposer = false

    // Only this alert's photos, not ones from earlier alerts.
    private var items: [EvidenceItem] {
        evidence.items.filter { $0.date >= startedAt }
    }

    private var locationText: String {
        if let current = location.current {
            return String(format: "Your location: %.4f, %.4f", current.coordinate.latitude, current.coordinate.longitude)
        }
        return location.isDenied ? "Location is off. Photos will only show the time." : "Finding your location…"
    }

    private var messageBody: String {
        var lines = [message]
        if let mapsURL = items.last?.mapsURL ?? mapsURL(for: location.current) {
            lines.append("My location: \(mapsURL.absoluteString)")
        }
        lines.append("Photos from \(Date.now.formatted(date: .omitted, time: .shortened)).")
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
                // The simulator has no camera, so this button only shows on a real phone.
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showingCamera = true
                    } label: {
                        EmergencyActionLabel(title: "Take photo", symbol: "camera.fill", tint: .white)
                    }
                }
                PhotosPicker(selection: $pickedPhotos, maxSelectionCount: 5, matching: .images) {
                    EmergencyActionLabel(title: "Choose", symbol: "photo.on.rectangle", tint: .white)
                }
            }

            if !items.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(items) { item in
                            EvidenceThumbnail(item: item)
                                .frame(width: 76, height: 76)
                        }
                    }
                }
                sendButton
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        let title = items.count == 1 ? "Send photo to contacts" : "Send \(items.count) photos to contacts"
        // Messages with the photos attached and every contact filled in. Phones that
        // can't send texts (like the simulator) get the regular share sheet instead.
        if MFMessageComposeViewController.canSendText() && !contacts.isEmpty {
            Button {
                showingComposer = true
            } label: {
                EmergencyActionLabel(title: title, symbol: "paperplane.fill", tint: .black)
            }
        } else {
            ShareLink(items: items.map(\.url), message: Text(messageBody)) {
                EmergencyActionLabel(title: items.count == 1 ? "Share photo" : "Share \(items.count) photos", symbol: "square.and.arrow.up", tint: .black)
            }
        }
    }

    private func addPickedPhotos() {
        let picked = pickedPhotos
        guard !picked.isEmpty else { return }
        pickedPhotos = []
        Task {
            for item in picked {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    evidence.add(image, takenNow: false, location: location.current)
                }
            }
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
                if let image = UIImage(contentsOfFile: item.url.path()) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Safety kit section

// Evidence stays saved after "I'm safe", so you can find it later.
struct SavedEvidenceSection: View {
    @Environment(EvidenceStore.self) private var evidence

    var body: some View {
        if !evidence.items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Saved evidence")
                        .font(.headline)
                    Text("Photos from your SOS alerts. They stay on this phone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                    ForEach(evidence.items.reversed()) { item in
                        EvidenceThumbnail(item: item)
                            .contextMenu {
                                ShareLink(item: item.url)
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    evidence.delete(item)
                                }
                            }
                    }
                }
                Text("Touch and hold a photo to share or delete it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
