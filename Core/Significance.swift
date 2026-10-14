import Foundation

/// Sterne fuer ein p - in der Evaluation (Fokus) und bei den Effekten des
/// Logbooks (Healthy) gleich: < 0,001 `***`, < 0,01 `**`, < 0,05 `*`.
///
/// Liegt in `Core/`, seit die Evaluation nach Fokus gezogen ist (14.10.) - die
/// Statistik dort bleibt dort, nur die Sterne braucht das Logbook auch.
enum Significance {
    static func stars(_ p: Double) -> String {
        switch p {
        case ..<0.001: "***"
        case ..<0.01:  "**"
        case ..<0.05:  "*"
        default:       ""
        }
    }
}
