import Foundation

/// Die drei Dienste, die diese App zusammenfasst.
///
/// Die Reihenfolge hier ist die Reihenfolge der Tabs: Essen zuerst, weil dort
/// die meisten taeglichen Eingaben passieren; Finanzen zuletzt, weil es der
/// Tab zum Nachlesen ist, nicht zum Eintragen.
enum Backend: String, CaseIterable, Identifiable, Sendable {
    case food
    case weight
    case finance

    var id: String { rawValue }

    var url: URL {
        switch self {
        case .food:    URL(string: "https://food.fherrmann.com")!
        case .weight:  URL(string: "https://weight.fherrmann.com")!
        case .finance: URL(string: "https://finanzen.fherrmann.com")!
        }
    }

    var title: String {
        switch self {
        case .food:    "Essen"
        case .weight:  "Gewicht"
        case .finance: "Finanzen"
        }
    }

    var systemImage: String {
        switch self {
        case .food:    "fork.knife"
        case .weight:  "scalemass"
        case .finance: "eurosign.circle"
        }
    }
}
