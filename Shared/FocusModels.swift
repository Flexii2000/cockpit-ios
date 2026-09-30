import Foundation

/// Eine durchgestandene Fokus-Session, wie der Habits-Dienst sie liefert
/// (`/habits/api/focus/sessions`): ein Baum im Wald.
///
/// Anfang und Ende sind Zeitpunkte (`Instant`, ISO-8601 mit `Z`), nicht Tage -
/// `day` ist der Tag, dem der Dienst die Session zurechnet: der des Beginns,
/// in Felix' Zeitzone. Die App rechnet das nicht nach.
struct FocusSession: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let start: Date
    let end: Date
    let minutes: Int
    let day: CalendarDate
}

/// Was die App meldet, wenn eine Session durch ist. Die Id vergibt die App,
/// damit ein Nachsenden aus dem Postausgang keinen zweiten Baum pflanzt.
struct FocusSessionDraft: Encodable, Sendable {
    let id: String
    let start: Date
    let end: Date
}

/// Minuten als Stunden - „2:15 h", „2:15/4:00 h".
enum FocusMinutes {

    static func hours(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// Der Stand von heute gegen das Tagesziel.
    static func progress(_ minutes: Int, goal: Int) -> String {
        "\(hours(minutes))/\(hours(goal)) h"
    }
}
