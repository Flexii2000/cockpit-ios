import Foundation

/// Eine Aenderung am To-Do, die Fokus sofort zeigt und spaeter schickt.
///
/// Neue Aufgaben bekommen ihre Kennung von der App: Haken, Aendern und
/// Unteraufgaben brauchen ein Ziel, bevor der Dienst geantwortet hat. Der
/// Dienst uebernimmt sie und legt bei derselben Kennung nichts doppelt an.
enum TodoChange: Codable, Equatable, Sendable {
    case create(id: String, areaId: String, parentId: String?, title: String, dueAt: CalendarDate?, at: Date)
    case setDone(id: String, done: Bool, at: Date)
    case update(id: String, title: String, dueAt: CalendarDate?)
    case delete(id: String)

    var target: String {
        switch self {
        case .create(let id, _, _, _, _, _), .setDone(let id, _, _), .update(let id, _, _), .delete(let id): id
        }
    }

    var role: PendingRole {
        switch self {
        case .create: .create
        case .setDone: .state
        case .update: .edit
        case .delete: .delete
        }
    }

    var dependsOn: String? {
        if case .create(_, _, let parentId, _, _, _) = self { return parentId }
        return nil
    }

    var request: PendingRequest {
        switch self {
        case .create(let id, let areaId, let parentId, let title, let dueAt, _):
            PendingRequest(method: "POST", path: "/api/todos",
                           body: Self.json(TodoDraft(areaId: areaId, parentId: parentId, title: title,
                                                     dueAt: dueAt?.iso, id: id)))
        case .setDone(let id, let done, _):
            done ? PendingRequest(method: "POST", path: "/api/todos/\(id)/done", body: Data("{}".utf8))
                 : PendingRequest(method: "DELETE", path: "/api/todos/\(id)/done")
        case .update(let id, let title, let dueAt):
            PendingRequest(method: "PUT", path: "/api/todos/\(id)",
                           body: Self.json(TodoUpdate(title: title, dueAt: dueAt?.iso)))
        case .delete(let id):
            PendingRequest(method: "DELETE", path: "/api/todos/\(id)", notFoundMeansDone: true)
        }
    }

    /// Ein wartendes Anlegen mit einer spaeteren Aenderung von Text und Faelligkeit.
    func folded(with change: TodoChange) -> TodoChange? {
        guard case .create(let id, let areaId, let parentId, _, _, let at) = self,
              case .update(let other, let title, let dueAt) = change, other == id else { return nil }
        return .create(id: id, areaId: areaId, parentId: parentId, title: title, dueAt: dueAt, at: at)
    }

    func notice(label: String, status: Int, message: String?) -> PendingNotice {
        let name = "„\(label)“"
        if status == 404 {
            // Die Aufgabe (oder beim Anlegen ihr Bereich, ihre Aufgabe darueber) ist weg.
            if case .create = self {
                return PendingNotice(text: "\(name) wurde nicht angelegt – der Bereich oder die Aufgabe darüber ist weg.",
                                     isInfo: true)
            }
            return PendingNotice(text: "\(name) gibt es nicht mehr.", isInfo: true)
        }
        return switch self {
        case .create: .error("\(name) wurde nicht angelegt", message, status: status)
        case .setDone(_, let done, _):
            .error(done ? "\(name) ließ sich nicht abhaken" : "\(name) ließ sich nicht wieder öffnen", message, status: status)
        case .update: .error("\(name) ließ sich nicht ändern", message, status: status)
        case .delete: .error("\(name) ließ sich nicht löschen", message, status: status)
        }
    }

    private static func json<T: Encodable>(_ value: T) -> Data? {
        try? APIClient.encoder().encode(value)
    }
}

/// Das Brett, wie die App es zeigt: der Stand des Dienstes und darueber, was wartet.
///
/// Gerechnet wird nur, was die Liste selbst ausmacht - einfuegen, abhaken,
/// umbenennen, entfernen, sortieren wie der Dienst, die offenen zaehlen. Mehr
/// nicht; nach dem Senden gilt wieder das Brett des Dienstes.
enum TodoOverlay {

    /// So lange bleibt Erledigtes beim Dienst sichtbar (`todo.done-visible-days`).
    static let doneVisible: TimeInterval = 3 * 86_400

    static func apply(_ changes: [TodoChange], to board: TodoBoard) -> TodoBoard {
        guard !changes.isEmpty else { return board }
        var areas = board.areas.map(MutableArea.init)
        for change in changes {
            apply(change, to: &areas)
        }
        return TodoBoard(areas: areas.map(\.area), includesHidden: board.includesHidden,
                         hiddenDoneCount: board.hiddenDoneCount, now: board.now)
    }

    private static func apply(_ change: TodoChange, to areas: inout [MutableArea]) {
        switch change {
        case .create(let id, let areaId, let parentId, let title, let dueAt, let at):
            // Schon beim Dienst (die Antwort kam, die Aenderung wartet noch auf ihr Ende)
            // oder schon eingefuegt: nichts doppelt.
            guard !areas.contains(where: { $0.contains(id) }),
                  let a = areas.firstIndex(where: { $0.id == areaId }) else { return }
            let item = TodoItem(id: id, title: title, link: nil, createdAt: at, doneAt: nil, visibleUntil: nil,
                                dueAt: dueAt, reminders: [], children: [])
            if let parentId {
                guard let p = areas[a].tops.firstIndex(where: { $0.id == parentId }) else { return }
                areas[a].tops[p].children.append(item)
            } else {
                areas[a].tops.append(MutableItem(item))
            }
        case .setDone(let id, let done, let at):
            update(id, in: &areas) { item in
                let doneAt = done ? (item.doneAt ?? at) : nil
                return item.with(doneAt: doneAt, visibleUntil: doneAt.map { $0.addingTimeInterval(doneVisible) })
            }
        case .update(let id, let title, let dueAt):
            update(id, in: &areas) { $0.with(title: title, dueAt: dueAt) }
        case .delete(let id):
            for a in areas.indices {
                areas[a].tops.removeAll { $0.id == id }
                for t in areas[a].tops.indices {
                    areas[a].tops[t].children.removeAll { $0.id == id }
                }
            }
        }
    }

    private static func update(_ id: String, in areas: inout [MutableArea], _ change: (TodoItem) -> TodoItem) {
        for a in areas.indices {
            for t in areas[a].tops.indices {
                if areas[a].tops[t].id == id {
                    areas[a].tops[t].item = change(areas[a].tops[t].item)
                    return
                }
                if let c = areas[a].tops[t].children.firstIndex(where: { $0.id == id }) {
                    areas[a].tops[t].children[c] = change(areas[a].tops[t].children[c])
                    return
                }
            }
        }
    }

    /// Offene zuerst (aelteste oben), Erledigte dahinter (zuletzt erledigte oben) -
    /// dieselbe Ordnung wie `TodoService.sortedTodos`.
    static func sorted(_ items: [TodoItem]) -> [TodoItem] {
        items.sorted { a, b in
            if a.isDone != b.isDone { return !a.isDone }
            if let x = a.doneAt, let y = b.doneAt { return x > y }
            return a.createdAt < b.createdAt
        }
    }

    private struct MutableItem {
        var item: TodoItem
        var children: [TodoItem]
        var id: String { item.id }

        init(_ item: TodoItem) {
            self.item = item
            children = item.children
        }
    }

    private struct MutableArea {
        let source: TodoArea
        var tops: [MutableItem]
        var id: String { source.id }

        init(_ area: TodoArea) {
            source = area
            tops = area.todos.map(MutableItem.init)
        }

        func contains(_ id: String) -> Bool {
            tops.contains { $0.id == id || $0.children.contains { $0.id == id } }
        }

        /// Wie der Dienst zaehlt: offene Aufgaben und offene Unteraufgaben.
        var area: TodoArea {
            let todos = TodoOverlay.sorted(tops.map { $0.item.with(children: TodoOverlay.sorted($0.children)) })
            let open = todos.reduce(0) { sum, todo in
                sum + (todo.isDone ? 0 : 1) + todo.children.filter { !$0.isDone }.count
            }
            return TodoArea(id: source.id, name: source.name, position: source.position, openCount: open,
                            hiddenDoneCount: source.hiddenDoneCount, todos: todos)
        }
    }
}

extension TodoItem {
    func with(title: String? = nil, dueAt: CalendarDate?? = nil, doneAt: Date?? = nil,
              visibleUntil: Date?? = nil, children: [TodoItem]? = nil) -> TodoItem {
        TodoItem(id: id, title: title ?? self.title, link: link, createdAt: createdAt,
                 doneAt: doneAt ?? self.doneAt, visibleUntil: visibleUntil ?? self.visibleUntil,
                 dueAt: dueAt ?? self.dueAt, reminders: reminders, children: children ?? self.children)
    }
}
