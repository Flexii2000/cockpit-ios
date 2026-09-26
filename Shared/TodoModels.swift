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
    /// Eine Adresse zur Aufgabe, etwa die Wunsch-Seite, von der sie stammt.
    /// Nur http und https - alles andere kommt als nil an.
    let link: URL?
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

    /// Die Faelligkeit, wie sie in der Zeile steht - eine Woche um heute
    /// herum in Tagen, weiter weg als Datum.
    var dueLabel: String? {
        dueAt.map { TodoItem.dueLabel(for: $0, daysFromToday: $0.daysFromToday()) }
    }

    /// "heute", "morgen", "in 3 Tagen" bis eine Woche voraus; "seit gestern",
    /// "seit 3 Tagen" bis eine Woche zurueck; sonst "bis 12.09." bzw.
    /// "seit 12.08.". Eine Woche ist die Spanne, in der man in Tagen denkt -
    /// "in 5 Tagen" sagt mehr als der 9., bei "in 23 Tagen" rechnet man
    /// doch wieder ins Datum um.
    static func dueLabel(for date: CalendarDate, daysFromToday days: Int) -> String {
        switch days {
        case 0: "heute"
        case 1: "morgen"
        case -1: "seit gestern"
        case 2...7: "in \(days) Tagen"
        case -7 ... -2: "seit \(-days) Tagen"
        default: days < 0 ? "seit \(date.short)" : "bis \(date.short)"
        }
    }
}

extension TodoItem {
    /// Muss hier stehen: Swift erzeugt `CodingKeys` nur, wenn es den Decoder
    /// selbst ableitet.
    private enum CodingKeys: String, CodingKey {
        case id, title, link, createdAt, doneAt, visibleUntil, dueAt, reminders, children
    }

    /// Wie der synthetisierte Decoder, nur der Link ist nachsichtig: fehlt er,
    /// ist er kein Text oder keine Webadresse, gibt es eben keinen. Ein
    /// kaputter Link darf nie das ganze Brett kippen - dann stuende der Tab
    /// leer da, nur wegen eines Pfeils. Als Erweiterung, damit der
    /// Memberwise-Init bleibt.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        link = TodoItem.webLink(try? container.decodeIfPresent(String.self, forKey: .link))
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        doneAt = try container.decodeIfPresent(Date.self, forKey: .doneAt)
        visibleUntil = try container.decodeIfPresent(Date.self, forKey: .visibleUntil)
        dueAt = try container.decodeIfPresent(CalendarDate.self, forKey: .dueAt)
        reminders = try container.decode([TodoReminder].self, forKey: .reminders)
        children = try container.decode([TodoItem].self, forKey: .children)
    }

    /// Nur http und https mit Host: das oeffnet Safari. Ein anderes Schema
    /// wuerde irgendeine App starten, und der Dienst laesst es ohnehin nicht
    /// durch - das hier faengt nur ab, was trotzdem ankommt.
    static func webLink(_ raw: String?) -> URL? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), !host.isEmpty else { return nil }
        return url
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
