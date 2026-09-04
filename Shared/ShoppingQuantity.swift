import Foundation

/// Menge als Zahl und Einheit - damit „2" und „500 g" nicht dasselbe Feld
/// sind.
///
/// Der Dienst speichert die Menge weiterhin als Text („500 g", „2 Stk"); die
/// App liest ihn in Zahl und Einheit auseinander und schreibt ihn in genau
/// dieser Form zurueck. Eine Zahl ohne Einheit heisst Stueck. Was sich nicht
/// lesen laesst („eine Handvoll"), bleibt als Text stehen - besser als eine
/// Menge, die jemand eingetippt hat, stillschweigend zu verwerfen.
struct ShoppingQuantity: Equatable, Sendable {

    enum Unit: String, CaseIterable, Identifiable, Sendable {
        case piece = "Stk"
        case gram = "g"
        case kilogram = "kg"
        case milliliter = "ml"
        case liter = "l"
        case pack = "Pck"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .piece:      "Stück"
            case .gram:       "Gramm"
            case .kilogram:   "Kilogramm"
            case .milliliter: "Milliliter"
            case .liter:      "Liter"
            case .pack:       "Packung"
            }
        }

        /// Wie Menschen Einheiten tippen. Klein geschrieben, ohne Punkt.
        static func named(_ raw: String) -> Unit? {
            switch raw.lowercased().replacingOccurrences(of: ".", with: "") {
            case "", "stk", "stück", "stueck", "st", "x", "stck": .piece
            case "g", "gr", "gramm": .gram
            case "kg", "kilo", "kilogramm": .kilogram
            case "ml", "milliliter": .milliliter
            case "l", "liter", "ltr": .liter
            case "pck", "pk", "pkg", "pack", "packung", "päckchen", "paeckchen": .pack
            default: nil
            }
        }
    }

    /// Die Zahl, wie sie getippt wurde („1,5") - keine Umrechnung, keine
    /// Rundung, damit aus 1,5 nicht 1.5 oder 2 wird.
    var amount: String
    var unit: Unit

    /// Der Text, den der Dienst bekommt.
    var text: String { "\(amount) \(unit.rawValue)" }

    /// Liest „500 g", „500g", „2", „2 Stück", „1,5 kg". `nil`, wenn keine Zahl
    /// vorn steht oder die Einheit unbekannt ist.
    static func parse(_ text: String?) -> ShoppingQuantity? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let match = trimmed.wholeMatch(of: /(\d+(?:[.,]\d+)?)\s*([A-Za-zÄÖÜäöü.]*)/) else { return nil }
        guard let unit = Unit.named(String(match.2)) else { return nil }
        return ShoppingQuantity(amount: String(match.1), unit: unit)
    }

    /// Was aus einem Mengenfeld und einer gewaehlten Einheit wird: leer ist
    /// keine Menge; steht im Feld selbst eine Einheit („500g"), gilt die;
    /// eine blosse Zahl bekommt die gewaehlte Einheit; alles andere bleibt
    /// Text.
    static func compose(_ field: String, unit: Unit) -> String? {
        let trimmed = field.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let parsed = parse(trimmed) {
            let hasOwnUnit = trimmed.contains { $0.isLetter }
            return ShoppingQuantity(amount: parsed.amount, unit: hasOwnUnit ? parsed.unit : unit).text
        }
        return trimmed
    }
}
