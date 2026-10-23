import SwiftUI
import UIKit
import PhotosUI
import Photos
import CoreImage
import CoreImage.CIFilterBuiltins

// One shared Core Image context. Making a new one for every photo is slow.
let ciContext = CIContext()

enum WallpaperStyle: String, CaseIterable, Identifiable {
    case calm = "Calm"
    case noir = "Noir"
    case night = "Night"
    case vivid = "Vivid"

    var id: Self { self }

    // Each style darkens the photo a little so the white text stays readable.
    func apply(to input: CIImage) -> CIImage {
        switch self {
        case .calm:
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = input.clampedToExtent()
            blur.radius = 18
            return darken(blur.outputImage?.cropped(to: input.extent) ?? input, by: 0.5)
        case .noir:
            let noir = CIFilter.photoEffectNoir()
            noir.inputImage = input
            return darken(noir.outputImage ?? input, by: 0.4)
        case .night:
            let exposure = CIFilter.exposureAdjust()
            exposure.inputImage = input
            exposure.ev = -1.4
            let tint = CIFilter.colorMonochrome()
            tint.inputImage = exposure.outputImage
            tint.color = CIColor(red: 0.1, green: 0.15, blue: 0.4)
            tint.intensity = 0.6
            return tint.outputImage ?? input
        case .vivid:
            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = input
            vibrance.amount = 1
            let vignette = CIFilter.vignette()
            vignette.inputImage = vibrance.outputImage
            vignette.intensity = 1.5
            vignette.radius = 2
            return vignette.outputImage ?? input
        }
    }

    // Exposure darkens every color by the same percentage, so colors stay
    // true and shadows don't turn solid black.
    private func darken(_ image: CIImage, by stops: Float) -> CIImage {
        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = image
        exposure.ev = -stops
        return exposure.outputImage ?? image
    }
}

struct LockScreenView: View {
    @Environment(ContactStore.self) private var store

    @AppStorage("name") private var name = ""
    @AppStorage("bloodType") private var bloodType = ""
    @AppStorage("allergies") private var allergies = ""
    @AppStorage("medications") private var medications = ""

    @State private var pickedPhoto: PhotosPickerItem?
    @State private var originalImage: UIImage?
    @State private var filteredImage: UIImage?
    @State private var style = WallpaperStyle.calm

    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Put your medical info on your lock screen, so a first responder can see it without unlocking your phone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Show the full-size wallpaper at about half size.
                    wallpaper
                        .scaleEffect(0.6)
                        .frame(width: 393 * 0.6, height: 852 * 0.6)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)

                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Label(originalImage == nil ? "Choose a background photo" : "Change photo", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .tint(.teal)

                    Picker("Style", selection: $style) {
                        ForEach(WallpaperStyle.allCases) { style in
                            Text(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(originalImage == nil)

                    Button(action: saveWallpaper) {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Text("Then in Photos, open the picture, tap Share, and choose Use as Wallpaper.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Lock screen")
            .onChange(of: pickedPhoto) {
                loadSelectedPhoto()
            }
            .onChange(of: style) {
                applyStyle()
            }
            .alert(alertTitle, isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
        }
    }

    private var wallpaper: WallpaperCard {
        WallpaperCard(
            background: filteredImage,
            name: name,
            bloodType: bloodType,
            allergies: allergies,
            medications: medications,
            contact: store.contacts.first
        )
    }

    private func loadSelectedPhoto() {
        Task {
            if let data = try? await pickedPhoto?.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                // Shrink big camera photos first so the filters stay fast.
                originalImage = resizedImage(image, maxWidth: 1200)
                applyStyle()
            }
        }
    }

    private func applyStyle() {
        guard let originalImage, let input = CIImage(image: originalImage) else { return }
        let output = style.apply(to: input)
        if let cgImage = ciContext.createCGImage(output, from: input.extent) {
            filteredImage = UIImage(cgImage: cgImage)
        }
    }

    private func saveWallpaper() {
        // Draw the SwiftUI view into an image at iPhone screen resolution.
        let renderer = ImageRenderer(content: wallpaper)
        renderer.scale = 3
        guard let image = renderer.uiImage else { return }

        Task {
            // .addOnly means we can save new photos but never see the user's library.
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                showAlert("Photos access is off", "Turn it on in Settings > Privacy > Photos to save your wallpaper.")
                return
            }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                showAlert("Saved to Photos", "Set it as your lock screen wallpaper from the Photos app.")
            } catch {
                showAlert("Couldn't save", error.localizedDescription)
            }
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
}

// The wallpaper itself, drawn at the size of an iPhone screen in points.
struct WallpaperCard: View {
    let background: UIImage?
    let name: String
    let bloodType: String
    let allergies: String
    let medications: String
    let contact: EmergencyContact?

    var body: some View {
        ZStack(alignment: .bottom) {
            if let background {
                Image(uiImage: background)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 393, height: 852)
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.1, blue: 0.12), Color(red: 0.45, green: 0.05, blue: 0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)

            // The clock covers the top of the lock screen and the flashlight and
            // camera buttons cover the bottom, so the card sits just above them.
            infoCard
                .padding(.horizontal, 26)
                .padding(.bottom, 130)
        }
        .frame(width: 393, height: 852)
        .clipped()
    }

    private var hasMedicalInfo: Bool {
        !bloodType.isEmpty || !allergies.isEmpty || !medications.isEmpty
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("MEDICAL ID", systemImage: "staroflife.fill")
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color(red: 1, green: 0.35, blue: 0.35))
            Text(name.isEmpty ? "Your name" : name)
                .font(.title.bold())

            if hasMedicalInfo {
                if !bloodType.isEmpty { infoRow("Blood type", bloodType) }
                if !allergies.isEmpty { infoRow("Allergies", allergies) }
                if !medications.isEmpty { infoRow("Medications", medications) }
            } else {
                Text("Add your medical info in Safety kit")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }

            if let contact {
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(height: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("IN AN EMERGENCY, CALL")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.65))
                    Text("\(contact.name) (\(contact.relationship))")
                        .font(.headline)
                    Text(contact.phone)
                        .font(.title3.weight(.semibold).monospacedDigit())
                }
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(.body.weight(.medium))
        }
    }
}

#Preview {
    LockScreenView()
        .environment(ContactStore())
}
