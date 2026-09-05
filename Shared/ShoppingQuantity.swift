import Foundation

/// Menge als Zahl und Einheit - damit „2" und „500 g" nicht dasselbe Feld
/// sind.
///
/// Der Dienst speichert die Menge weiterhin als Text („500 g", „2 Stk",
/// „3 Dosen"); die App liest ihn in Zahl und Einheit auseinander und schreibt
/// ihn in genau dieser Form zurueck. Gelesen wird, was Menschen tippen:
/// Ziffern und Zahlwoerter („zwei", „ein halbes"), Einheiten ausgeschrieben
/// oder abgekuerzt („Gramm", „gr", „Stk.", „Pck", „Dosen", „Kasten"), mit
/// oder ohne Leerzeichen. Eine Zahl ohne Einheit heisst Stueck. Was sich
/// nicht lesen laesst („eine Handvoll"), bleibt als Text stehen - besser als
/// eine Menge, die jemand eingetippt hat, stillschweigend zu verwerfen.
///
/// Der Dienst hat dieselben Regeln (`QuantityParser`); hier noch einmal,
/// damit ein Eintrag ohne Netz schon richtig dasteht.
struct ShoppingQuantity: Equatable, Sendable {

    enum Unit: String, CaseIterable, Identifiable, Sendable {
        case piece = "Stk"
        case gram = "g"
        case kilogram = "kg"
        case milliliter = "ml"
        case centiliter = "cl"
        case liter = "l"
        case pack = "Pck"
        case can = "Dose"
        case bottle = "Flasche"
        case bag = "Tüte"
        case pouch = "Beutel"
        case cup = "Becher"
        case jar = "Glas"
        case bar = "Tafel"
        case roll = "Rolle"
        case crate = "Kiste"
        case caseOf = "Kasten"
        case slice = "Scheibe"
        case bunch = "Bund"
        case pair = "Paar"
        case stick = "Stange"
        case head = "Kopf"
        case net = "Netz"
        case tray = "Schale"
        case carton = "Karton"
        case pound = "Pfund"
        case tube = "Tube"
        case box = "Schachtel"
        case portion = "Portion"
        case tablespoon = "EL"
        case teaspoon = "TL"
        case pinch = "Prise"
        case barlet = "Riegel"

        var id: String { rawValue }

        /// Was das Menue anbietet. Der Rest kommt ueber das Tippen herein.
        static let common: [Unit] = [.piece, .gram, .kilogram, .milliliter, .liter, .pack]

        var label: String {
            switch self {
            case .piece:      "Stück"
            case .gram:       "Gramm"
            case .kilogram:   "Kilogramm"
            case .milliliter: "Milliliter"
            case .centiliter: "Zentiliter"
            case .liter:      "Liter"
            case .pack:       "Packung"
            case .tablespoon: "Esslöffel"
            case .teaspoon:   "Teelöffel"
            default:          rawValue
            }
        }

        /// Die Form zu einer Zahl: „1 Dose", „2 Dosen". Abkuerzungen bleiben.
        func form(for amount: String) -> String {
            if amount == "1" { return rawValue }
            switch self {
            case .can: return "Dosen"
            case .bottle: return "Flaschen"
            case .bag: return "Tüten"
            case .jar: return "Gläser"
            case .bar: return "Tafeln"
            case .roll: return "Rollen"
            case .crate: return "Kisten"
            case .caseOf: return "Kästen"
            case .slice: return "Scheiben"
            case .stick: return "Stangen"
            case .head: return "Köpfe"
            case .net: return "Netze"
            case .tray: return "Schalen"
            case .carton: return "Kartons"
            case .tube: return "Tuben"
            case .box: return "Schachteln"
            case .portion: return "Portionen"
            case .pinch: return "Prisen"
            default: return rawValue
            }
        }

        /// Wie Menschen Einheiten tippen - Abkuerzungen, Einzahl, Mehrzahl.
        static func named(_ raw: String) -> Unit? {
            let key = raw.lowercased()
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: "ä", with: "ae")
                .replacingOccurrences(of: "ö", with: "oe")
                .replacingOccurrences(of: "ü", with: "ue")
                .replacingOccurrences(of: "ß", with: "ss")
            return aliases[key]
        }

        private static let aliases: [String: Unit] = {
            var table: [String: Unit] = [:]
            let rows: [(Unit, [String])] = [
                (.piece, ["", "stk", "st", "stck", "stueck", "stuecke", "x", "mal"]),
                (.gram, ["g", "gr", "gramm"]),
                (.kilogram, ["kg", "kilo", "kilos", "kilogramm"]),
                (.milliliter, ["ml", "milliliter"]),
                (.centiliter, ["cl", "zentiliter"]),
                (.liter, ["l", "liter", "ltr"]),
                (.pack, ["pck", "pk", "pkg", "pkt", "pack", "packung", "packungen", "paeckchen", "packerl"]),
                (.can, ["dose", "dosen", "ds"]),
                (.bottle, ["flasche", "flaschen", "fl"]),
                (.bag, ["tuete", "tueten"]),
                (.pouch, ["beutel"]),
                (.cup, ["becher"]),
                (.jar, ["glas", "glaeser"]),
                (.bar, ["tafel", "tafeln"]),
                (.roll, ["rolle", "rollen"]),
                (.crate, ["kiste", "kisten"]),
                (.caseOf, ["kasten", "kaesten"]),
                (.slice, ["scheibe", "scheiben"]),
                (.bunch, ["bund"]),
                (.pair, ["paar"]),
                (.stick, ["stange", "stangen"]),
                (.head, ["kopf", "koepfe"]),
                (.net, ["netz", "netze"]),
                (.tray, ["schale", "schalen"]),
                (.carton, ["karton", "kartons"]),
                (.pound, ["pfund", "pfd"]),
                (.tube, ["tube", "tuben"]),
                (.box, ["schachtel", "schachteln"]),
                (.portion, ["portion", "portionen"]),
                (.tablespoon, ["el", "essloeffel"]),
                (.teaspoon, ["tl", "teeloeffel"]),
                (.pinch, ["prise", "prisen"]),
                (.barlet, ["riegel"]),
            ]
            for (unit, names) in rows {
                for name in names { table[name] = unit }
            }
            return table
        }()
    }

    /// Die Zahl, wie sie getippt wurde („1,5") - keine Umrechnung, keine
    /// Rundung, damit aus 1,5 nicht 1.5 oder 2 wird. Zahlwoerter werden zu
    /// Ziffern („zwei" zu „2", „ein halbes" zu „0,5").
    var amount: String
    var unit: Unit

    /// Der Text, den der Dienst bekommt.
    var text: String { "\(amount) \(unit.form(for: amount))" }

    /// Liest einen Text, der nur aus einer Menge besteht: „500 g", „500g",
    /// „2", „zwei Stück", „1,5 kg", „3 Dosen", „ein halbes Kilo".
    static func parse(_ text: String?) -> ShoppingQuantity? {
        guard let text else { return nil }
        let tokens = words(text)
        guard !tokens.isEmpty, let (quantity, used) = phrase(tokens[...]), used == tokens.count else { return nil }
        return quantity
    }

    /// Liest eine Menge aus dem Namen heraus, wie man sie tippt: „gemischtes
    /// Hack 200g" wird zu „gemischtes Hack" und 200 g, „zwei Zwiebeln" zu
    /// „Zwiebeln" und 2 Stk, „Klopapier 2" zu „Klopapier" und 2 Stk, „ein
    /// halbes Kilo Hack" zu „Hack" und 0,5 kg. Hinten wird vor vorn gesucht.
    /// Ohne Menge im Namen kommt der Name zurueck, wie er war.
    static func split(_ name: String) -> (name: String, quantity: ShoppingQuantity?) {
        let tokens = words(name)
        let plain = tokens.joined(separator: " ")
        guard tokens.count >= 2 else { return (plain, nil) }
        for start in 1..<tokens.count {
            if let (quantity, used) = phrase(tokens[start...]), start + used == tokens.count {
                return (tokens[..<start].joined(separator: " "), quantity)
            }
        }
        if let (quantity, used) = phrase(tokens[...]), used < tokens.count {
            return (tokens[used...].joined(separator: " "), quantity)
        }
        return (plain, nil)
    }

    /// Was aus einem Mengenfeld und einer gewaehlten Einheit wird: leer ist
    /// keine Menge; steht im Feld selbst eine Einheit („500g", „3 Dosen"),
    /// gilt die; eine blosse Zahl bekommt die gewaehlte Einheit; alles andere
    /// bleibt Text.
    static func compose(_ field: String, unit: Unit) -> String? {
        let trimmed = field.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Eine blosse Zahl im Mengenfeld ist immer eine Menge - hier gilt die
        // Grenze fuer Stueckzahlen im Namen nicht, die Einheit steht daneben.
        if trimmed.wholeMatch(of: /\d+(?:[.,]\d+)?/) != nil {
            return ShoppingQuantity(amount: trimmed, unit: unit).text
        }
        if let parsed = parse(trimmed) {
            return parsed.text
        }
        return trimmed
    }

    // MARK: - Lesen

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Liest am Anfang der Woerter eine Mengenangabe: Zahl (Ziffern oder
    /// Wort, auch zusammengeschrieben mit der Einheit wie „200g"), optional
    /// „halb", optional Einheit. Liefert die Menge und die Zahl der
    /// verbrauchten Woerter.
    private static func phrase(_ tokens: ArraySlice<String>) -> (ShoppingQuantity, Int)? {
        guard let first = tokens.first else { return nil }
        // Zahl und Einheit in einem Wort: 200g, 2x, 1,5l, 3Stk
        if let match = first.wholeMatch(of: /(\d+(?:[.,]\d+)?)([^\d\s.,]+\.?)/),
           let unit = Unit.named(String(match.2)) {
            return (ShoppingQuantity(amount: String(match.1), unit: unit), 1)
        }
        // Ein Einheitenwort ohne Zahl heisst eins: „Liter Cola", „Packung
        // Nudeln", „Dose Tomaten". Nur ausgeschriebene Woerter - ein „l" oder
        // „g" allein ist eher ein Tippfehler als eine Menge.
        if first.count >= 3, first.allSatisfy(\.isLetter), let unit = Unit.named(first) {
            return (ShoppingQuantity(amount: "1", unit: unit), 1)
        }
        guard var amount = number(first) else { return nil }
        var index = tokens.startIndex + 1
        // „ein halbes Kilo": das Halbe gehoert zur Eins.
        if index < tokens.endIndex, isHalf(tokens[index]) {
            guard amount == "1" else { return nil }
            amount = "0,5"
            index += 1
        }
        // „ein paar Aepfel" ist keine Menge, auch wenn „Paar" eine Einheit ist.
        if index < tokens.endIndex, tokens[index].lowercased() == "paar",
           first.lowercased().hasPrefix("ein") {
            return nil
        }
        if index < tokens.endIndex, let unit = Unit.named(tokens[index]) {
            return (ShoppingQuantity(amount: amount, unit: unit), index + 1 - tokens.startIndex)
        }
        // Eine blosse Zahl ist nur dann eine Stueckzahl, wenn sie ganz und
        // klein ist: „Mehl Type 405" hat keine 405 Stueck, und „Milch 1,5"
        // meint eher den Fettgehalt.
        guard let whole = Int(amount), whole <= 99 else { return nil }
        return (ShoppingQuantity(amount: amount, unit: .piece), index - tokens.startIndex)
    }

    private static func isHalf(_ word: String) -> Bool {
        ["halb", "halbe", "halber", "halbes", "halben"].contains(word.lowercased())
    }

    /// Ziffern („2", „1,5", „1/2", „½") und Zahlwoerter („zwei", „eine",
    /// „anderthalb", „halbes", „Dutzend") als Text mit Komma.
    private static func number(_ word: String) -> String? {
        if word.wholeMatch(of: /\d+(?:[.,]\d+)?/) != nil { return word }
        switch word.lowercased() {
        case "1/2", "½", "halb", "halbe", "halber", "halbes", "halben": return "0,5"
        case "ein", "eine", "einen", "einem", "einer", "eins": return "1"
        case "anderthalb", "eineinhalb", "1½": return "1,5"
        case "zwei", "zwo": return "2"
        case "zweieinhalb": return "2,5"
        case "drei": return "3"
        case "vier": return "4"
        case "fünf", "fuenf": return "5"
        case "sechs": return "6"
        case "sieben": return "7"
        case "acht": return "8"
        case "neun": return "9"
        case "zehn": return "10"
        case "elf": return "11"
        case "zwölf", "zwoelf", "dutzend": return "12"
        default: return nil
        }
    }
}
