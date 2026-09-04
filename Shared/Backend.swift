import Foundation

/// Die Dienste, die diese App zusammenfasst.
///
/// Die Reihenfolge hier ist die Reihenfolge der Tabs: Essen zuerst, weil dort
/// die meisten taeglichen Eingaben passieren; die beiden gesperrten Tabs
/// zuletzt, weil sie zum Nachlesen sind und nicht zum Eintragen.
enum Backend: String, CaseIterable, Identifiable, Sendable {
    case food
    case weight
    case finance
    case grades
    case habits
    case todo
    case shopping

    var id: String { rawValue }

    /// Die Basis, an die `APIClient` seine Pfade haengt.
    ///
    /// Bei den Noten gehoert der Pfad dazu: sie sind kein eigener Host,
    /// sondern liegen unter `fherrmann.com/grades` - `/api/overview` wird so
    /// zu `/grades/api/overview`.
    var url: URL {
        #if DEBUG
        // Gegen einen lokal laufenden Dienst statt gegen den Server -
        // z. B. COCKPIT_URL_GRADES=http://127.0.0.1:48230/grades. Der einzige
        // Weg, eine Oberflaeche mit echten Daten zu sehen, deren Zugang nicht
        // im Keychain liegen kann (die Noten wollen ein Passwort).
        // ATS laesst Schleifenadressen ohne Ausnahme durch.
        if let override = ProcessInfo.processInfo.environment["COCKPIT_URL_\(rawValue.uppercased())"],
           let url = URL(string: override) {
            return url
        }
        #endif
        return switch self {
        case .food:    URL(string: "https://food.fherrmann.com")!
        case .weight:  URL(string: "https://weight.fherrmann.com")!
        case .finance: URL(string: "https://finanzen.fherrmann.com")!
        case .grades:  URL(string: "https://fherrmann.com/grades")!
        case .habits:  URL(string: "https://fherrmann.com/habits")!
        case .todo:    URL(string: "https://fherrmann.com/todo")!
        case .shopping: URL(string: "https://fherrmann.com/shopping-list")!
        }
    }

    var title: String {
        switch self {
        case .food:    "Essen"
        case .weight:  "Gewicht"
        case .finance: "Finanzen"
        case .grades:  "Noten"
        case .habits:  "Habits"
        case .todo:    "To-Do"
        case .shopping: "Einkaufsliste"
        }
    }

    var systemImage: String {
        switch self {
        case .food:    "fork.knife"
        case .weight:  "scalemass"
        case .finance: "eurosign.circle"
        case .grades:  "graduationcap"
        case .habits:  "flame"
        case .todo:    "checklist"
        case .shopping: "cart"
        }
    }
}
