import UIKit

/// Ein Foto fuer den Dienst: aufrecht, hoechstens 2048 Punkte an der langen
/// Kante, JPEG (Vertrag §1.1: der Dienst dreht nicht nach EXIF - die App
/// zeichnet das Bild neu, und dabei wird die Ausrichtung eingebacken).
enum PhotoEncoding {

    static let maxSide: CGFloat = 2048
    static let quality: CGFloat = 0.85
    /// Die Grenze des Dienstes; darunter bleiben, auch bei einem sehr
    /// detailreichen Bild.
    static let maxBytes = 9_500_000

    static func jpeg(_ image: UIImage, maxSide: CGFloat = PhotoEncoding.maxSide) -> Data? {
        var side = maxSide
        var quality = PhotoEncoding.quality
        for _ in 0..<4 {
            guard let data = upright(image, maxSide: side).jpegData(compressionQuality: quality) else { return nil }
            if data.count <= maxBytes { return data }
            side *= 0.8
            quality = max(0.6, quality - 0.1)
        }
        return upright(image, maxSide: side).jpegData(compressionQuality: quality)
    }

    /// Neu gezeichnet: das Ergebnis hat Ausrichtung `.up`, die Pixel stehen
    /// so, wie man das Foto sieht.
    static func upright(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        let scale = longest > maxSide && longest > 0 ? maxSide / longest : 1
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Quadratisch aus der Mitte - fuer das Profilbild (der Dienst schneidet
    /// nicht zu, Vertrag §3.2).
    static func squareAvatar(_ image: UIImage, side: CGFloat = 1024) -> Data? {
        let upright = upright(image, maxSide: max(image.size.width, image.size.height))
        let length = min(upright.size.width, upright.size.height)
        let crop = CGRect(x: (upright.size.width - length) / 2, y: (upright.size.height - length) / 2,
                          width: length, height: length)
        guard let cg = upright.cgImage?.cropping(to: crop) else { return nil }
        let square = UIImage(cgImage: cg)
        return self.upright(square, maxSide: side).jpegData(compressionQuality: quality)
    }
}
