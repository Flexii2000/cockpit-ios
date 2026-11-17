import CryptoKit
import Foundation

/// Was Fokus beim Freigeben signiert - gleich aufgebaut wie im Gate
/// (`Canonical.java` im Assistent-Repo), beide pruefen denselben Testvektor.
///
/// ```
/// assistant-gate/v1
/// art=<base64(art)>
/// <name>=<base64(wert)>      je Feld, in der Reihenfolge des Servers
/// ```
///
/// Fokus rechnet den Hash selbst aus den Feldern, die es anzeigt. Passt er
/// nicht zu dem des Servers, gibt es nichts freizugeben - die Signatur gilt so
/// immer fuer genau das, was auf dem Bildschirm stand.
enum ApprovalPayload {

    static let version = "assistant-gate/v1"

    static func text(art: String, fields: [ApprovalField]) -> String {
        var text = "\(version)\nart=\(base64(art))\n"
        for field in fields {
            text += "\(field.name)=\(base64(field.wert))\n"
        }
        return text
    }

    static func hash(art: String, fields: [ApprovalField]) -> String {
        hex(SHA256.hash(data: Data(text(art: art, fields: fields).utf8)))
    }

    /// Bindet Auftrag, Inhalt und Zeitpunkt (Unix-Sekunden).
    static func message(id: String, hash: String, time: Int64) -> String {
        "\(version)|\(id)|\(hash)|\(time)"
    }

    /// Zum Vergleich mit dem Setup-Skript: die ersten 16 Hex-Zeichen von
    /// SHA-256 ueber den Schluessel (DER), in Vierergruppen.
    static func fingerprint(publicKeyDER: Data) -> String {
        let prefix = hex(SHA256.hash(data: publicKeyDER)).prefix(16)
        return stride(from: 0, to: prefix.count, by: 4).map { start in
            let from = prefix.index(prefix.startIndex, offsetBy: start)
            return String(prefix[from..<prefix.index(from, offsetBy: 4)])
        }.joined(separator: " ")
    }

    private static func base64(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
