import Foundation

/// Eine Aenderung am To-Do, die Fokus sofort zeigt und spaeter schickt.
///
/// Neue Aufgaben bekommen ihre Kennung von der App: Haken, Aendern und
/// Unteraufgaben brauchen ein Ziel, bevor der Dienst geantwortet hat. Der
/// Dienst uebernimmt sie und legt bei derselben Kennung nichts doppelt an.
enum TodoChange: Codable, Equatable, Sendable {
    /// Ohne `areaId`, mit `today`: eine Aufgabe, die nur in „Heute" steht. `today`
    /// optional mit Vorgabe, damit Wartendes von vor dem 26.10. weiter lesbar ist.
    case create(id: String, areaId: String?, parentId: String?, title: String, dueAt: CalendarDate?, at: Date,
                today: Bool? = nil)
    case setDone(id: String, done: Bool, at: Date)
    case update(id: String, title: String, dueAt: CalendarDate?)
    case delete(id: String)
    /// Nach „Heute" holen oder wieder rausnehmen.
    case setToday(id: String, today: Bool)
    /// Die Reihenfolge der offenen in „Heute", zuerst oben.
    case orderToday(ids: [String])

    /// Das Ziel einer neuen Reihenfolge - keine Aufgabe, aber eine feste Kennung:
    /// so gilt beim Zusammenfassen die letzte, und an keiner Zeile haengt eine Uhr.
    static let todayOrderTarget = "today-order"

    var target: String {
        switch self {
        case .create(let id, _, _, _, _, _, _), .setDone(let id, _, _), .update(let id, _, _), .delete(let id),
             .setToday(let id, _): id
        case .orderToday: Self.todayOrderTarget
        }
    }

    var role: PendingRole {
        switch self {
        case .create: .create
        case .setDone: .state
        case .update: .edit
        case .delete: .delete
        // Nicht `.state`: das fasste Holen und Abhaken derselben Aufgabe zu einem zusammen.
        case .setToday: .other
        // Wie ein Aendern: die letzte Reihenfolge gilt.
        case .orderToday: .edit
        }
    }

    var dependsOn: String? {
        if case .create(_, _, let parentId, _, _, _, _) = self { return parentId }
        return nil
    }

    var request: PendingRequest {
        switch self {
        case .create(let id, let areaId, let parentId, let title, let dueAt, _, let today):
            PendingRequest(method: "POST", path: "/api/todos",
                           body: Self.json(TodoDraft(areaId: areaId, parentId: parentId, title: title,
                                                     dueAt: dueAt?.iso, id: id, today: today)))
        case .setDone(let id, let done, _):
            done ? PendingRequest(method: "POST", path: "/api/todos/\(id)/done", body: Data("{}".utf8))
                 : PendingRequest(method: "DELETE", path: "/api/todos/\(id)/done")
        case .update(let id, let title, let dueAt):
            PendingRequest(method: "PUT", path: "/api/todos/\(id)",
                           body: Self.json(TodoUpdate(title: title, dueAt: dueAt?.iso)))
        case .delete(let id):
            PendingRequest(method: "DELETE", path: "/api/todos/\(id)", notFoundMeansDone: true)
        case .setToday(let id, let today):
            today ? PendingRequest(method: "POST", path: "/api/todos/\(id)/today", body: Data("{}".utf8))
                  : PendingRequest(method: "DELETE", path: "/api/todos/\(id)/today", notFoundMeansDone: true)
        case .orderToday(let ids):
            PendingRequest(method: "PUT", path: "/api/today", body: Self.json(TodayOrder(ids: ids)))
        }
    }

    /// Ein wartendes Anlegen mit einer spaeteren Aenderung von Text und Faelligkeit.
    func folded(with change: TodoChange) -> TodoChange? {
        guard case .create(let id, let areaId, let parentId, _, _, let at, let today) = self,
              case .update(let other, let title, let dueAt) = change, other == id else { return nil }
        return .create(id: id, areaId: areaId, parentId: parentId, title: title, dueAt: dueAt, at: at, today: today)
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
        case .setToday(_, let today):
            .error(today ? "\(name) ließ sich nicht nach Heute holen" : "\(name) ließ sich nicht aus Heute nehmen",
                   message, status: status)
        case .orderToday: .error("Die Reihenfolge in „Heute“ ließ sich nicht sichern", message, status: status)
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
///
/// „Heute" ebenso: die Reihenfolge als Liste von Kennungen, die Eintraege selbst
/// aus den Bereichen - so gilt ein Haken dort wie hier, ohne doppelte Buchfuehrung.
/// Die Aufgaben ohne Bereich stehen dafuer in einem Bereich ohne Namen, der nie
/// als Seite erscheint.
enum TodoOverlay {

    /// So lange bleibt Erledigtes beim Dienst sichtbar (`todo.done-visible-days`).
    static let doneVisible: TimeInterval = 3 * 86_400
    /// Der Bereich der Aufgaben ohne Bereich - nur hier drinnen.
    private static let adHocArea = ""

    /// - Parameter now: wann „heute" ist - fuer Tests; Erledigtes von vor
    ///   Mitternacht steht nicht mehr in „Heute", wie beim Dienst.
    static func apply(_ changes: [TodoChange], to board: TodoBoard, now: Date = Date()) -> TodoBoard {
        guard !changes.isEmpty else { return board }
        let today = board.today ?? .empty
        var areas = board.areas.map(MutableArea.init)
        areas.append(MutableArea(TodoArea(id: adHocArea, name: "", position: Int.max, openCount: 0, hiddenDoneCount: 0,
                                          todos: today.items.filter(\.isAdHoc).map(\.todo))))
        var order = today.items.map(\.id)
        for change in changes {
            apply(change, to: &order, in: areas)
            apply(change, to: &areas)
        }
        var shown = areas.map(\.area)
        let adHoc = shown.removeLast()
        return TodoBoard(areas: shown, includesHidden: board.includesHidden,
                         hiddenDoneCount: board.hiddenDoneCount, now: board.now,
                         today: todayView(order: order, areas: shown, adHoc: adHoc,
                                          includesHidden: board.includesHidden, now: now))
    }

    private static func apply(_ change: TodoChange, to areas: inout [MutableArea]) {
        switch change {
        case .create(let id, let areaId, let parentId, let title, let dueAt, let at, let today):
            // Schon beim Dienst (die Antwort kam, die Aenderung wartet noch auf ihr Ende)
            // oder schon eingefuegt: nichts doppelt.
            guard !areas.contains(where: { $0.contains(id) }),
                  let a = areas.firstIndex(where: { $0.id == (areaId ?? adHocArea) }) else { return }
            let isAdHoc = areaId == nil
            var item = TodoItem(id: id, title: title, link: nil, createdAt: at, doneAt: nil, visibleUntil: nil,
                                dueAt: dueAt, today: isAdHoc || today == true, reminders: [], children: [])
            if let parentId {
                guard let p = areas[a].tops.firstIndex(where: { $0.id == parentId }) else { return }
                // Steht die Aufgabe darueber schon in „Heute", kommt die neue mit ihr.
                if isAdHoc || areas[a].tops[p].item.today { item = item.with(today: false) }
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
        case .setToday(let id, let today):
            guard let place = locate(id, in: areas), !place.isAdHoc, !place.isCovered else { return }
            update(id, in: &areas) { $0.with(today: today) }
            // Eine Hauptaufgabe bringt ihre Unteraufgaben mit - einzeln geholte sind es nicht mehr.
            if today, place.child == nil {
                areas[place.area].tops[place.top].children = areas[place.area].tops[place.top].children
                    .map { $0.with(today: false) }
            }
        case .orderToday:
            break
        }
    }

    /// Die Reihenfolge in „Heute" - wie der Dienst sie fuehrt: Neues ans Ende,
    /// Geordnetes nach vorn, was die Reihenfolge nicht nennt, dahinter.
    private static func apply(_ change: TodoChange, to order: inout [String], in areas: [MutableArea]) {
        switch change {
        case .create(let id, let areaId, let parentId, _, _, _, let today):
            guard today == true || areaId == nil, !order.contains(id) else { return }
            if let parentId, areaId == nil || order.contains(parentId) { return }
            order.append(id)
        case .setToday(let id, true):
            guard let place = locate(id, in: areas), !place.isAdHoc, !place.isCovered, !order.contains(id) else { return }
            if place.child == nil {
                let children = Set(areas[place.area].tops[place.top].children.map(\.id))
                order.removeAll { children.contains($0) }
            }
            order.append(id)
        case .setToday(let id, false):
            guard let place = locate(id, in: areas), !place.isAdHoc else { return }
            order.removeAll { $0 == id }
        case .orderToday(let ids):
            let current = Set(order)
            var next: [String] = []
            for id in ids where current.contains(id) && !next.contains(id) { next.append(id) }
            next += order.filter { !next.contains($0) }
            order = next
        case .setDone, .update, .delete:
            // Geloeschtes faellt beim Zeichnen raus - es steht dann in keinem Bereich mehr.
            break
        }
    }

    /// Wo eine Aufgabe steht, und ob sie mit ihrer Aufgabe darueber schon in „Heute" ist.
    private struct Place {
        let area: Int
        let top: Int
        let child: Int?
        let isAdHoc: Bool
        let isCovered: Bool
    }

    private static func locate(_ id: String, in areas: [MutableArea]) -> Place? {
        for a in areas.indices {
            for t in areas[a].tops.indices {
                let isAdHoc = areas[a].id == adHocArea
                if areas[a].tops[t].id == id {
                    return Place(area: a, top: t, child: nil, isAdHoc: isAdHoc, isCovered: false)
                }
                if let c = areas[a].tops[t].children.firstIndex(where: { $0.id == id }) {
                    return Place(area: a, top: t, child: c, isAdHoc: isAdHoc,
                                 isCovered: isAdHoc || areas[a].tops[t].item.today)
                }
            }
        }
        return nil
    }

    /// „Heute" aus der Reihenfolge und den Bereichen - so, wie der Dienst es liefert:
    /// alles in der Reihenfolge, heute Erledigtes an seinem Platz; Unteraufgaben in
    /// der Reihenfolge des Anlegens, auch abgehakte.
    private static func todayView(order: [String], areas: [TodoArea], adHoc: TodoArea, includesHidden: Bool,
                                  now: Date) -> TodoToday {
        let startOfDay = Calendar.current.startOfDay(for: now)
        func isToday(_ item: TodoItem) -> Bool {
            includesHidden || item.doneAt.map { $0 >= startOfDay } ?? true
        }
        var found: [String: (area: TodoArea?, item: TodoItem, parent: TodoItem?)] = [:]
        for area in areas + [adHoc] {
            for top in area.todos {
                let home = area.id == adHocArea ? nil : area
                found[top.id] = (home, top, nil)
                for child in top.children { found[child.id] = (home, child, top) }
            }
        }
        let pinned = Set(order)
        var ids = order
        // Ohne Bereich steht eine Aufgabe immer in „Heute" - fehlt sie in der Reihenfolge, hinten.
        ids += adHoc.todos.map(\.id).filter { !pinned.contains($0) }
        var items: [TodoTodayItem] = []
        var openCount = 0
        var seen: Set<String> = []
        for id in ids where seen.insert(id).inserted {
            guard case let (area, item, parent)? = found[id], isToday(item) else { continue }
            if let parent, area == nil || pinned.contains(parent.id) { continue }
            let children = parent == nil ? item.children.filter(isToday).sorted { $0.createdAt < $1.createdAt } : []
            openCount += children.filter { !$0.isDone }.count + (item.isDone ? 0 : 1)
            let entry = TodoTodayItem(areaId: area?.id, areaName: area?.name, parentId: parent?.id,
                                      parentTitle: parent?.title, todo: item.with(children: children))
            items.append(entry)
        }
        return TodoToday(openCount: openCount, items: items)
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
              visibleUntil: Date?? = nil, today: Bool? = nil, children: [TodoItem]? = nil) -> TodoItem {
        TodoItem(id: id, title: title ?? self.title, link: link, createdAt: createdAt,
                 doneAt: doneAt ?? self.doneAt, visibleUntil: visibleUntil ?? self.visibleUntil,
                 dueAt: dueAt ?? self.dueAt, today: today ?? self.today, reminders: reminders,
                 children: children ?? self.children)
    }
}
