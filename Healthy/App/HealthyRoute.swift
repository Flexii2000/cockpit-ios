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
    /// Das Dashboard oben - die Schritte-Kacheln des Sperrbildschirms (14.10.).
    case dashboard
    /// Die Logbook-Seite im Dashboard - die Erinnerung um 09:00.
    case logbook
    /// Der Freunde-Tab - Stupser, Serien-Warnung und die Serien-Kachel (10.11.).
    case friends
    /// Das Dashboard samt offenem Chat - „Deine Antwort ist da.“ (10.11.).
    case chat

    /// Die Art der lokalen „Vorschlag ist fertig"-Mitteilung.
    static let quickCaptureKind = "quick-capture"
    /// Die Arten, die der Weight Tracker ueber den Kalorienzaehler schickt
    /// (Vertrag §11.5).
    static let chatAnswerKind = "chat-answer"
    static let friendNudgeKind = "friend-nudge"
    static let streakWarningKind = "streak-warning"
    /// Das URL-Schema von Healthy (`healthy://food`), in `project.yml`.
    static let urlScheme = "healthy"

    /// Die Art aus der Nutzlast einer Mitteilung.
    ///
    /// **Ohne Art ist es die Schnellerfassung:** der Kalorienzaehler schickt
    /// seine APNs-Meldung ohne `kind`. Unbekannte Arten fuehren nirgends hin -
    /// die App bleibt, wo sie ist, statt zu raten. Dazu gehoert seit 14.10. die
    /// Erinnerung der Evaluation (`evaluation`) - die wohnt jetzt in Fokus.
    static func notification(kind: String?) -> HealthyRoute? {
        guard let kind else { return .food }
        switch kind {
        case quickCaptureKind:     return .food
        case LogbookReminder.kind: return .logbook
        case chatAnswerKind:       return .chat
        case friendNudgeKind, streakWarningKind: return .friends
        default:                      return nil
        }
    }

    /// `healthy://food` - die Kalorien-Kachel; `healthy://dashboard` - die
    /// Schritte-Kacheln; `healthy://friends` und `healthy://chat` seit 10.11.
    /// (Vertrag §11.5). Anderes Schema, anderer Weg: nichts.
    static func url(_ url: URL) -> HealthyRoute? {
        guard url.scheme?.lowercased() == urlScheme else { return nil }
        switch url.host()?.lowercased() {
        case "food":      return .foodToday
        case "dashboard": return .dashboard
        case "friends":   return .friends
        case "chat":      return .chat
        default:          return nil
        }
    }
}
