import Foundation

/// Wohin ein Tipp von aussen fuehrt - auf eine Mitteilung oder einen Link.
///
/// Seit Healthy im Dashboard aufmacht, muss jeder Weg sagen, wohin er will:
/// vorher landete alles ohnehin im Essen-Tab, und die Schnellerfassung hat
/// sich darauf verlassen.
enum HealthyRoute: Equatable, Sendable {
    /// Der Essen-Tab, wie er gerade steht - der Vorschlag der Schnellerfassung
    /// geht dort auf, egal fuer welchen Tag er war.
    case food
    /// Der Essen-Tab mit heute - die Kalorien-Kachel und die Energie-Karte.
    case foodToday
    case evaluation
    /// Die Logbook-Seite im Dashboard - die Erinnerung um 09:00.
    case logbook

    /// Die Art der lokalen „Vorschlag ist fertig"-Mitteilung.
    static let quickCaptureKind = "quick-capture"
    /// Das URL-Schema von Healthy (`healthy://food`), in `project.yml`.
    static let urlScheme = "healthy"

    /// Die Art aus der Nutzlast einer Mitteilung.
    ///
    /// **Ohne Art ist es die Schnellerfassung:** der Kalorienzaehler schickt
    /// seine APNs-Meldung ohne `kind`. Unbekannte Arten fuehren nirgends hin -
    /// die App bleibt, wo sie ist, statt zu raten.
    static func notification(kind: String?) -> HealthyRoute? {
        guard let kind else { return .food }
        switch kind {
        case quickCaptureKind:        return .food
        case EvaluationReminder.kind: return .evaluation
        case LogbookReminder.kind:    return .logbook
        default:                      return nil
        }
    }

    /// `healthy://food` - die Kalorien-Kachel. Anderes Schema, anderer Weg: nichts.
    static func url(_ url: URL) -> HealthyRoute? {
        guard url.scheme?.lowercased() == urlScheme else { return nil }
        switch url.host()?.lowercased() {
        case "food": return .foodToday
        default:     return nil
        }
    }
}
