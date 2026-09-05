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

    /// Liest eine Menge aus dem Namen heraus, wie man sie tippt: „gemischtes
    /// Hack 200g" wird zu „gemischtes Hack" und 200 g, „2 Zwiebeln" zu
    /// „Zwiebeln" und 2 Stk, „Milch 1l" zu „Milch" und 1 l. Eine blosse Zahl
    /// zaehlt nur als Stueckzahl, wenn sie ganz und klein ist - „Mehl Type
    /// 405" hat keine 405 Stueck. Ohne Menge im Namen kommt der Name zurueck,
    /// wie er war. Dieselben Regeln hat der Dienst (`QuantityParser`); hier
    /// noch einmal, damit ein Eintrag ohne Netz schon richtig dasteht.
    static func split(_ name: String) -> (name: String, quantity: ShoppingQuantity?) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        // Die Einheit steht als Aufzaehlung IM Muster, nicht als "irgendein
        // Wort": sonst haelt „2 gemischte Brote" das Wort "gemischte" fuer
        // die Einheit, und der Vergleich danach kann nichts mehr retten.
        // Als Literale, nicht aus einem String gebaut: nur Literale haben
        // nummerierte Gruppen mit Typ. Und lokal statt statisch, weil `Regex`
        // nicht `Sendable` ist.
        let trailing = /(.+?)\s+(\d+(?:[.,]\d+)?)\s*(stk|stück|stueck|stck|st|x|g|gr|gramm|kg|kilo|kilogramm|ml|milliliter|l|liter|ltr|pck|pk|pkg|pack|packung|packungen|päckchen|paeckchen)?/
            .ignoresCase()
        let leading = /(\d+(?:[.,]\d+)?)\s*(stk|stück|stueck|stck|st|x|g|gr|gramm|kg|kilo|kilogramm|ml|milliliter|l|liter|ltr|pck|pk|pkg|pack|packung|packungen|päckchen|paeckchen)?\s+(.+)/
            .ignoresCase()
        if let m = trimmed.wholeMatch(of: trailing),
           let quantity = quantity(amount: String(m.2), unitText: m.3.map(String.init) ?? "") {
            return (String(m.1), quantity)
        }
        if let m = trimmed.wholeMatch(of: leading),
           let quantity = quantity(amount: String(m.1), unitText: m.2.map(String.init) ?? "") {
            return (String(m.3), quantity)
        }
        return (trimmed, nil)
    }

    private static func quantity(amount: String, unitText: String) -> ShoppingQuantity? {
        guard let unit = Unit.named(unitText) else { return nil }
        if unitText.isEmpty {
            // Eine blosse Zahl ist nur dann eine Stueckzahl, wenn sie ganz und
            // klein ist: „Mehl Type 405" hat keine 405 Stueck, und „Milch 1,5"
            // meint eher den Fettgehalt.
            guard let whole = Int(amount), whole <= 99 else { return nil }
        }
        return ShoppingQuantity(amount: amount, unit: unit)
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
