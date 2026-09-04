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
    let children: [TodoItem]

    var isDone: Bool { doneAt != nil }
}

/// Was die App beim Anlegen schickt.
struct TodoDraft: Encodable, Sendable {
    let areaId: String
    let parentId: String?
    let title: String
}

struct AreaDraft: Encodable, Sendable {
    let name: String
}
