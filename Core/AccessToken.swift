import Foundation

/// Der persoenliche Healthy-Token aus dem, was jemand ins Feld einfuegt.
///
/// Felix schickt entweder den nackten Token oder einen Setup-Link
/// (`https://food.fherrmann.com/setup?token=…`). Beides soll ins selbe Feld
/// passen - auch mitsamt dem Satz drumherum, wenn jemand die ganze Nachricht
/// kopiert hat. Dieselbe Regel wie in der Android-App (`core/AccessToken.kt`).
enum AccessToken {

    /// Der Token aus der Eingabe, oder `nil`, wenn keiner darin zu erkennen ist.
    static func extract(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let match = text.firstMatch(of: #/[?&]token=([^&#\s]+)/#) {
            let raw = String(match.1)
            let token = (raw.removingPercentEncoding ?? raw)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return token.isEmpty ? nil : token
        }
        // Ohne token-Parameter: ein Link oder ein Satz ist kein Token. Was
        // uebrig bleibt, prueft der Dienst - das Format hier festzunageln
        // (48 Hex-Zeichen) wuerde nur einen kuenftigen Token aussperren.
        if text.contains(where: { $0.isWhitespace || "/?:&=".contains($0) }) { return nil }
        return text
    }
}
