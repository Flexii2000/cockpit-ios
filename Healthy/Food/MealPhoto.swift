import PhotosUI
import SwiftUI
import UIKit

/// Ein Foto der Mahlzeit fuer die Schnellerfassung - verkleinert und als
/// JPEG, damit es als Base64 durch die JSON-Anfrage passt und der Agent
/// trotzdem genug sieht. 1280 Punkte an der langen Kante reichen fuer
/// Teller und Verpackung; ein Original mit zwölf Megapixeln waere zehnmal
/// so gross und fuer die Schaetzung keinen Deut besser.
enum MealPhoto {

    static let maxSide: CGFloat = 1280
    static let quality: CGFloat = 0.65

    static func resized(_ image: UIImage, maxSide: CGFloat = MealPhoto.maxSide) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Obergrenze fuer die Datei: nginx laesst vor dem Dienst 1 MB durch, und
    /// Base64 macht aus 700 kB rund 930 kB. Ein detailreiches Foto kann bei
    /// 1280 Punkten und 0,65 darueber liegen - dann kleiner und grober, bis
    /// es passt.
    static let maxBytes = 700_000

    static func jpegData(_ image: UIImage) -> Data? {
        var side = maxSide
        var quality = MealPhoto.quality
        for _ in 0..<5 {
            guard let data = resized(image, maxSide: side).jpegData(compressionQuality: quality) else { return nil }
            if data.count <= maxBytes { return data }
            side *= 0.8
            quality = max(0.4, quality - 0.1)
        }
        return resized(image, maxSide: side).jpegData(compressionQuality: quality)
    }

    /// Das Bild, wie es der Dienst erwartet: JPEG als Base64, ohne Praefix.
    static func base64(_ image: UIImage) -> String? {
        jpegData(image)?.base64EncodedString()
    }
}

/// Die Kamera als Blatt. `UIImagePickerController`, weil SwiftUI keine
/// eigene Kamera hat; die Fotomediathek kommt ueber `PhotosPicker`.
struct CameraPicker: UIViewControllerRepresentable {

    let onPhoto: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPhoto: onPhoto, dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPhoto: (UIImage) -> Void
        let dismiss: () -> Void

        init(onPhoto: @escaping (UIImage) -> Void, dismiss: @escaping () -> Void) {
            self.onPhoto = onPhoto
            self.dismiss = dismiss
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onPhoto(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}
