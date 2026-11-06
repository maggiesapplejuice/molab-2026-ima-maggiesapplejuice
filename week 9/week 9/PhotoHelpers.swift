import SwiftUI
import UIKit

// Shrinks a photo so it's at most maxWidth pixels wide. Redrawing it also fixes
// photos that were taken sideways.
func resizedImage(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
    let width = min(image.size.width, maxWidth)
    let size = CGSize(width: width, height: width * image.size.height / image.size.width)
    // Scale 1 so the image is really `width` pixels (not 3x that), and standard
    // range so Core Image and JPEG get normal sRGB colors.
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.preferredRange = .standard
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in
        image.draw(in: CGRect(origin: .zero, size: size))
    }
}

// A contact's face, or their initials if they don't have a photo yet.
struct ContactAvatar: View {
    let contact: EmergencyContact
    let size: CGFloat

    var body: some View {
        Group {
            if let photoFileName = contact.photoFileName,
               let image = UIImage(contentsOfFile: fileURL(photoFileName).path()) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Text(contact.initials.isEmpty ? "?" : contact.initials)
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.teal)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.6), lineWidth: 2))
        .accessibilityHidden(true)
    }
}
