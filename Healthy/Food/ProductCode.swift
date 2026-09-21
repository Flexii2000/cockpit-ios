import Foundation

/// Der Produktcode, wie Open Food Facts ihn kennt: die Ziffern der GTIN
/// (EAN-8, EAN-13, UPC) - gewonnen aus dem, was der Scanner liefert.
///
/// Ein Strichcode gibt die Ziffern direkt her. Ein QR-Code auf einer Packung
/// ist meist ein GS1 Digital Link (`https://id.gs1.org/01/04000417025005/…`),
/// ein DataMatrix ein GS1-Elementstring (`(01)04000417025005(17)…`) - und
/// oft ist ein QR-Code nur eine Werbeseite, die mit dem Produkt nichts zu tun
/// hat. Reine Logik ohne Kamera, damit sie sich pruefen laesst.
enum ProductCode {

    /// Die GTIN aus dem Inhalt eines Codes - `nil`, wenn es kein Produktcode ist.
    static func gtin(from payload: String) -> String? {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // EAN/UPC: nur Ziffern. Kuerzer als EAN-8 oder laenger als GTIN-14 ist
        // keine Artikelnummer - hoechstens ein Elementstring ohne Klammern.
        if isDigits(text) {
            return (8...14).contains(text.count) ? normalised(text) : elementString(text)
        }

        // GS1 Digital Link: im Pfad steht die GTIN hinter dem
        // Anwendungsbezeichner 01 (oder dem aelteren Klartext "gtin").
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           scheme == "https" || scheme == "http" {
            let parts = url.pathComponents
            for (index, part) in parts.enumerated()
            where (part == "01" || part.lowercased() == "gtin") && index + 1 < parts.count {
                let candidate = parts[index + 1]
                if isDigits(candidate), (8...14).contains(candidate.count) {
                    return normalised(candidate)
                }
            }
            return nil
        }

        return elementString(text)
    }

    /// GS1-Elementstring, wie ihn DataMatrix und GS1 DataBar tragen: der
    /// Anwendungsbezeichner 01 - mit oder ohne Klammern - und dahinter genau
    /// 14 Ziffern; danach folgen Charge, Haltbarkeit und Aehnliches.
    private static func elementString(_ text: String) -> String? {
        let body: Substring
        if text.hasPrefix("(01)") {
            body = text.dropFirst(4)
        } else if text.hasPrefix("01"), text.count > 14 {
            body = text.dropFirst(2)
        } else {
            return nil
        }
        let gtin = String(body.prefix(14))
        guard gtin.count == 14, isDigits(gtin) else { return nil }
        return normalised(gtin)
    }

    /// Eine GTIN-14 mit Packungskennzeichen 0 ist dieselbe Artikelnummer wie
    /// die EAN-13 dahinter - und unter der fuehrt Open Food Facts sie.
    private static func normalised(_ digits: String) -> String {
        digits.count == 14 && digits.hasPrefix("0") ? String(digits.dropFirst()) : digits
    }

    private static func isDigits(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
