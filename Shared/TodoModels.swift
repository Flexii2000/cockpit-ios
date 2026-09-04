import Foundation

/// Was `/todo/api/board` liefert - das ganze Brett. Siehe docs/BACKENDS.md.
///
/// Jede Antwort des Dienstes ist ein Brett; die App ersetzt ihren Stand und
/// setzt nichts zusammen.
struct TodoBoard: Decodable, Sendable, Equatable {
    let areas: [TodoArea]
    let includesHidden: Bool
    /// Erledigte, die aelter als die Sichtfrist sind und nicht mitkommen.
    let hiddenDoneCount: Int
    let now: Date
}

/// Ein Bereich - in der App eine Seite, im Browser eine Kachel.
struct TodoArea: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let position: Int
    let openCount: Int
    let hiddenDoneCount: Int
    let todos: [TodoItem]
}

/// Eine Aufgabe, mit ihren Unteraufgaben (genau eine Ebene).
struct TodoItem: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let createdAt: Date
    let doneAt: Date?
    /// Bei erledigten: bis wann sie noch zu sehen ist.
    let visibleUntil: Date?
    /// Faelligkeit - eine Anzeige, ueberfaellig heisst rot.
    let dueAt: CalendarDate?
    /// Zeitpunkte, zu denen der Dienst eine Push-Nachricht schickt.
    let reminders: [TodoReminder]
    let children: [TodoItem]

    var isDone: Bool { doneAt != nil }

    var isOverdue: Bool {
        guard let dueAt, !isDone else { return false }
        return dueAt.daysFromToday() < 0
    }
}

struct TodoReminder: Decodable, Identifiable, Sendable, Equatable {
    let id: String
    let at: Date
    let sentAt: Date?
}

/// Was die App beim Anlegen schickt. `dueAt` als ISO-Datum, wie der Dienst
/// es liest.
struct TodoDraft: Encodable, Sendable {
    let areaId: String
    let parentId: String?
    let title: String
    let dueAt: String?
}

/// Text und Faelligkeit aendern - ohne `dueAt` gibt es keine mehr.
struct TodoUpdate: Encodable, Sendable {
    let title: String
    let dueAt: String?
}

/// Ein Zeitpunkt mit Zone - der Dienst liest ein `Instant`, kein Datum ohne.
struct ReminderDraft: Encodable, Sendable {
    let at: String

    init(at: Date) {
        self.at = ISO8601DateFormatter().string(from: at)
    }
}

struct AreaDraft: Encodable, Sendable {
    let name: String
}
