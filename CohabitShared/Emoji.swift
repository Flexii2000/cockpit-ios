import Foundation

/// Emoji-Reaktionen (Vertrag §2.7a, seit 2026-10-05): je Person hoechstens
/// eine je Nachricht bzw. Ereignis, ein beliebiges Emoji.
///
/// Was als Emoji zaehlt und wie es geschrieben wird, entscheidet der Dienst
/// (ein Graphem mit einem Bildzeichen, einem Flaggenpaar oder einer
/// Tastenkappe; ohne U+FE0E, ein einzelnes Textzeichen mit U+FE0F). Die App
/// schreibt es vorher genauso - sonst stuende „❤" neben „❤️" und das eigene
/// waere in der Leiste nicht hervorgehoben.
enum Emoji {

    /// Die Schnellauswahl in der Leiste, in dieser Reihenfolge.
    static let quickPicks = ["💪", "🔥", "🙌", "❤️", "😂", "👏"]

    /// „Gratulieren" im Abschlussdialog.
    static let congratulate = "💪"

    /// Die vier festen Reaktionen bis 05.10. - der Dienst deutet sie genauso
    /// um; so liest die App auch einen aelteren Dienst oder einen alten
    /// Auftrag aus dem Postausgang.
    static let legacy = ["STARK": "💪", "RESPEKT": "🙌", "WEITER_SO": "🔥", "HAHA": "😂"]

    /// Hoechstens so lang (UTF-16), wie der Dienst es annimmt.
    static let maxLength = 32

    /// Ein Wert aus dem Dienst: alte Namen als Emoji, sonst unveraendert.
    static func fromService(_ raw: String) -> String {
        legacy[raw] ?? raw
    }

    /// Wie der Dienst schreibt: ohne Text-Variante (U+FE0E), ein einzelnes
    /// Zeichen ohne eigene Emoji-Darstellung mit U+FE0F (❤ → ❤️).
    static func normalized(_ emoji: String) -> String {
        var scalars = emoji.unicodeScalars.filter { $0.value != 0xFE0E }
        if scalars.count == 1, let only = scalars.first, !only.properties.isEmojiPresentation {
            scalars.append(Unicode.Scalar(0xFE0F)!)
        }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    /// Das erste Emoji einer Eingabe (die Emoji-Tastatur hinter „+") -
    /// `nil`, wenn keins darin ist.
    static func first(in text: String) -> String? {
        text.first(where: isEmoji).map { normalized(String($0)) }
    }

    /// Ob ein Zeichen ein Emoji ist, das der Dienst annimmt.
    static func isEmoji(_ character: Character) -> Bool {
        let scalars = Array(character.unicodeScalars)
        guard !scalars.isEmpty, String(character).utf16.count <= maxLength else { return false }
        // Tastenkappe: 1️⃣, #️⃣ …
        if scalars.contains(where: { $0.value == 0x20E3 }) { return true }
        // Flagge: zwei Regionalbuchstaben.
        let regional = scalars.filter { (0x1F1E6...0x1F1FF).contains($0.value) }
        if regional.count == 2 { return true }
        return scalars.contains(where: isPictographic)
    }

    /// Naeherung an Extended_Pictographic, das Swift nicht anbietet: ein
    /// Emoji-Zeichen, das keine Ziffer, kein Regionalbuchstabe und keine
    /// Hautfarbe ist.
    private static func isPictographic(_ scalar: Unicode.Scalar) -> Bool {
        let properties = scalar.properties
        guard properties.isEmoji, !scalar.isASCII else { return false }
        if (0x1F1E6...0x1F1FF).contains(scalar.value) { return false }
        if properties.isEmojiModifier { return false }
        return true
    }
}
