import Foundation

/// Welche Art Bild in Daten steckt - am Dateianfang erkannt, nicht an einer
/// Endung oder einem Typ, den jemand behauptet.
///
/// Gebraucht beim Hochladen (ein GIF geht unveraendert als `image/gif` hoch,
/// Vertrag §2.7a), im Postausgang (die wartende Datei behaelt ihre Art) und in
/// der Notification Service Extension (die Anlage braucht die richtige
/// Endung, sonst zeigt iOS sie nicht). Deshalb ohne jede Abhaengigkeit - die
/// Erweiterung uebersetzt nur diese Datei und wenige andere.
enum ImageFormat: String, Sendable, CaseIterable {
    case gif
    case jpeg
    case png
    case webp

    /// Am Dateianfang: `GIF8`, `FF D8 FF`, `89 PNG`, `RIFF … WEBP`.
    static func sniff(_ data: Data) -> ImageFormat? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return .gif }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }
        if bytes.count >= 12, bytes.starts(with: [0x52, 0x49, 0x46, 0x46]),
           Array(bytes[8..<12]) == [0x57, 0x45, 0x42, 0x50] {
            return .webp
        }
        return nil
    }

    /// Aus `Content-Type` (`image/gif; charset=…` und Verwandte).
    static func from(contentType: String?) -> ImageFormat? {
        guard let type = contentType?.split(separator: ";").first?
            .trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
        switch type {
        case "image/gif": return .gif
        case "image/jpeg", "image/jpg", "image/pjpeg": return .jpeg
        case "image/png": return .png
        case "image/webp": return .webp
        default: return nil
        }
    }

    var fileExtension: String {
        switch self {
        case .gif: "gif"
        case .jpeg: "jpg"
        case .png: "png"
        case .webp: "webp"
        }
    }

    var mimeType: String {
        switch self {
        case .gif: "image/gif"
        case .jpeg: "image/jpeg"
        case .png: "image/png"
        case .webp: "image/webp"
        }
    }
}
