import ActivityKit
import Foundation

/// Startet und beendet die Live-Aktivitaet zur Session. Eine zur Zeit:
/// vor dem Start wird aufgeraeumt, was noch von frueher steht.
///
/// Beenden kann nur die App - die Erweiterung am Ende der Session nicht.
/// Laeuft die App am Ende nicht, bleibt die Aktivitaet mit „Baum gepflanzt"
/// stehen (`staleDate` = Ende), bis die App das naechste Mal aufraeumt.
@MainActor
enum LiveActivityBridge {

    static func start(_ session: ActiveSession) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        await endAll()
        let attributes = FocusActivityAttributes(sessionID: session.id, start: session.start,
                                                 end: session.end, test: session.test)
        let content = ActivityContent(state: FocusActivityAttributes.ContentState(), staleDate: session.end)
        do {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            print("Live-Aktivität nicht gestartet: \(error.localizedDescription)")
        }
    }

    /// Sorgt dafuer, dass die laufende Session ihre Aktivitaet hat - etwa
    /// nach einem Update, das die Aktivitaet erst mitbrachte, oder wenn sie
    /// weggewischt wurde. Bei jedem Vordergrund aufgerufen; ist sie da,
    /// passiert nichts.
    static func ensure(_ session: ActiveSession) async {
        let existing = Activity<FocusActivityAttributes>.activities
        if existing.contains(where: { $0.attributes.sessionID == session.id
                                        && $0.activityState == .active }) { return }
        await start(session)
    }

    /// Nacheinander und im selben Kontext: `Activity` ist nicht Sendable,
    /// ein eigener Task je Aktivitaet waere fuer Swift 6 ein Datenrennen.
    static func endAll() async {
        for activity in Activity<FocusActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
