import Foundation

/// Was die Kachel zeigt.
///
/// Drei Zustaende, und keiner davon ist eine erfundene Zahl.
enum WidgetState: Equatable, Sendable {
    case noAccess
    case value(RemainingCalories)
    /// Server nicht erreichbar - mit dem letzten bekannten Stand, falls es
    /// einen gibt.
    case unreachable(RemainingCalories?)

    var calories: RemainingCalories? {
        switch self {
        case .value(let value):       value
        case .unreachable(let value): value
        case .noAccess:               nil
        }
    }
}
