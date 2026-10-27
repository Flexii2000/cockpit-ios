import XCTest
@testable import Healthy

/// „Heute" in Fokus, waehrend Aenderungen warten: so, wie der Dienst es danach
/// zeigen wird (`TodoTodayTest` in `../todo`).
final class TodoTodayOverlayTests: XCTestCase {

    private let earlier = Date(timeIntervalSince1970: 1_790_000_000)
    private let now = Date(timeIntervalSince1970: 1_790_100_000)

    private func item(_ id: String, _ title: String, done: Date? = nil, today: Bool = false,
                      children: [TodoItem] = []) -> TodoItem {
        TodoItem(id: id, title: title, link: nil, createdAt: earlier, doneAt: done, visibleUntil: nil,
                 dueAt: nil, today: today, reminders: [], children: children)
    }

    private func board(_ todos: [TodoItem], today: [TodoTodayItem] = []) -> TodoBoard {
        TodoBoard(areas: [TodoArea(id: "privat", name: "Privat", position: 0, openCount: todos.count,
                                   hiddenDoneCount: 0, todos: todos)],
                  includesHidden: false, hiddenDoneCount: 0, now: earlier,
                  today: TodoToday(openCount: today.count, items: today))
    }

    private func entry(_ todo: TodoItem, area: Bool = true, parent: TodoItem? = nil) -> TodoTodayItem {
        TodoTodayItem(areaId: area ? "privat" : nil, areaName: area ? "Privat" : nil, parentId: parent?.id,
                      parentTitle: parent?.title, todo: todo)
    }

    private func ids(_ board: TodoBoard) -> [String] {
        board.today?.items.map(\.id) ?? []
    }

    func testPickedGoesToTheEndAndIsMarked() {
        let base = board([item("a", "Aufgabe A"), item("b", "Aufgabe B")])
        let shown = TodoOverlay.apply([.setToday(id: "b", today: true), .setToday(id: "a", today: true),
                                       .setToday(id: "b", today: true)], to: base, now: now)
        XCTAssertEqual(ids(shown), ["b", "a"], "noch einmal holen aendert nichts")
        XCTAssertEqual(shown.today?.items[0].areaName, "Privat")
        XCTAssertEqual(shown.today?.openCount, 2)
        XCTAssertTrue(shown.areas[0].todos.allSatisfy(\.today))

        let out = TodoOverlay.apply([.setToday(id: "a", today: false)], to: shown, now: now)
        XCTAssertEqual(ids(out), ["b"])
        XCTAssertFalse(out.areas[0].todos.first { $0.id == "a" }!.today, "im Bereich bleibt sie")
    }

    func testWithoutAnAreaOnlyInToday() {
        let base = board([item("a", "Aufgabe A")])
        let shown = TodoOverlay.apply([.create(id: "x", areaId: nil, parentId: nil, title: "Aufgabe X", dueAt: nil,
                                               at: now, today: true)], to: base, now: now)
        XCTAssertEqual(ids(shown), ["x"])
        XCTAssertNil(shown.today?.items[0].areaId)
        XCTAssertEqual(shown.areas[0].todos.map(\.id), ["a"], "in keinem Bereich")

        // Rausnehmen gibt es nicht - abhaken und loeschen schon.
        let still = TodoOverlay.apply([.setToday(id: "x", today: false)], to: withToday(shown), now: now)
        XCTAssertEqual(ids(still), ["x"])
        let gone = TodoOverlay.apply([.delete(id: "x")], to: withToday(shown), now: now)
        XCTAssertEqual(ids(gone), [])
    }

    func testCheckedStaysInPlace() {
        let a = item("a", "Aufgabe A", today: true)
        let b = item("b", "Aufgabe B", today: true)
        let c = item("c", "Aufgabe C", today: true)
        let base = board([a, b, c], today: [entry(a), entry(b), entry(c)])
        let ordered = TodoOverlay.apply([.orderToday(ids: ["c", "weg", "a", "c"])], to: base, now: now)
        XCTAssertEqual(ids(ordered), ["c", "a", "b"], "nicht genannte ans Ende, unbekannte zaehlen nicht")

        let checked = TodoOverlay.apply([.orderToday(ids: ["c", "a", "b"]), .setDone(id: "c", done: true, at: now)],
                                        to: base, now: now)
        XCTAssertEqual(ids(checked), ["c", "a", "b"], "abgehakt bleibt es an seinem Platz")
        XCTAssertEqual(checked.today?.openCount, 2)
    }

    func testACheckedSubtaskStaysInPlace() {
        let first = TodoItem(id: "c", title: "Gliederung", link: nil, createdAt: earlier, doneAt: nil,
                             visibleUntil: nil, dueAt: nil, today: false, reminders: [], children: [])
        let second = TodoItem(id: "d", title: "Literatur", link: nil, createdAt: earlier.addingTimeInterval(60),
                              doneAt: nil, visibleUntil: nil, dueAt: nil, today: false, reminders: [], children: [])
        let parent = item("p", "Hausarbeit", today: true, children: [first, second])
        let base = board([parent], today: [entry(parent)])
        let shown = TodoOverlay.apply([.setDone(id: "c", done: true, at: now)], to: base, now: now)
        XCTAssertEqual(shown.today?.items[0].todo.children.map(\.id), ["c", "d"])
        XCTAssertEqual(shown.areas[0].todos[0].children.map(\.id), ["d", "c"], "im Bereich rutscht sie nach unten")
    }

    func testDoneBeforeMidnightIsNoLongerInToday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let a = item("a", "Aufgabe A", done: yesterday, today: true)
        let b = item("b", "Aufgabe B", today: true)
        // Der Dienst haette „a" nicht mehr geschickt; hier kommt es durch einen Haken zurueck.
        let base = board([a, b], today: [entry(b)])
        let shown = TodoOverlay.apply([.setDone(id: "b", done: true, at: now)], to: base, now: now)
        XCTAssertEqual(ids(shown), ["b"], "heute erledigt steht noch da")
        XCTAssertEqual(shown.areas[0].todos.count, 2, "im Bereich steht beides")
    }

    func testATaskBringsItsSubtasksAndASingleSubtaskShowsItsParent() {
        let child = item("c", "Gliederung", today: true)
        let parent = item("p", "Hausarbeit", children: [child, item("d", "Literatur")])
        let base = board([parent], today: [entry(child, parent: parent)])
        XCTAssertEqual(base.today?.items[0].parentTitle, "Hausarbeit")

        let shown = TodoOverlay.apply([.setToday(id: "p", today: true)], to: base, now: now)
        XCTAssertEqual(ids(shown), ["p"], "die einzeln geholte stuende sonst doppelt da")
        XCTAssertEqual(shown.today?.items[0].todo.children.map(\.id), ["c", "d"])
        XCTAssertEqual(shown.today?.openCount, 3)
        XCTAssertFalse(shown.areas[0].todos[0].children[0].today)

        // Und eine Unteraufgabe darunter holen: nichts.
        let again = TodoOverlay.apply([.setToday(id: "p", today: true), .setToday(id: "d", today: true)],
                                      to: base, now: now)
        XCTAssertEqual(ids(again), ["p"])
    }

    func testCreatingInAnAreaWithTodayPicksItRightAway() {
        let shown = TodoOverlay.apply([.create(id: "n", areaId: "privat", parentId: nil, title: "Neu", dueAt: nil,
                                               at: now, today: true)], to: board([]), now: now)
        XCTAssertEqual(ids(shown), ["n"])
        XCTAssertEqual(shown.today?.items[0].areaId, "privat")
        XCTAssertTrue(shown.areas[0].todos[0].today)
    }

    /// Was vor dem 26.10. in der Warteschlange lag, kennt `today` nicht - und muss
    /// trotzdem lesbar bleiben, sonst legte die App die ganze Datei beiseite.
    func testAWaitingCreateFromBeforeStillDecodes() throws {
        let old = #"{"create":{"id":"x","areaId":"privat","title":"Aufgabe X","at":0}}"#
        let change = try JSONDecoder().decode(TodoChange.self, from: Data(old.utf8))
        XCTAssertEqual(change, .create(id: "x", areaId: "privat", parentId: nil, title: "Aufgabe X", dueAt: nil,
                                       at: Date(timeIntervalSinceReferenceDate: 0)))
        let roundTrip = try JSONDecoder().decode(TodoChange.self, from: JSONEncoder().encode(
            TodoChange.orderToday(ids: ["a", "b"])))
        XCTAssertEqual(roundTrip, .orderToday(ids: ["a", "b"]))
    }

    func testRequestsAsTheServiceReadsThem() throws {
        let create = TodoChange.create(id: "x", areaId: nil, parentId: nil, title: "Aufgabe X", dueAt: nil, at: now,
                                       today: true).request
        let body = try JSONSerialization.jsonObject(with: create.body ?? Data()) as? [String: Any]
        XCTAssertNil(body?["areaId"], "ohne Bereich")
        XCTAssertEqual(body?["today"] as? Bool, true)

        XCTAssertEqual(TodoChange.setToday(id: "a", today: true).request.path, "/api/todos/a/today")
        XCTAssertEqual(TodoChange.setToday(id: "a", today: false).request.method, "DELETE")
        let order = TodoChange.orderToday(ids: ["b", "a"]).request
        XCTAssertEqual(order.method, "PUT")
        XCTAssertEqual(order.path, "/api/today")
        XCTAssertEqual((try JSONSerialization.jsonObject(with: order.body ?? Data()) as? [String: Any])?["ids"]
                       as? [String], ["b", "a"])
    }

    func testDecodesTodayFromTheService() throws {
        let data = """
        {"areas":[{"id":"uni","name":"Uni","position":1,"openCount":1,"hiddenDoneCount":0,
          "todos":[{"id":"t1","title":"Hausarbeit","link":null,"createdAt":"2026-09-04T10:00:00Z","doneAt":null,
                    "visibleUntil":null,"dueAt":null,"today":true,"reminders":[],"children":[]}]}],
         "today":{"openCount":2,"items":[
           {"areaId":"uni","areaName":"Uni","parentId":null,"parentTitle":null,
            "todo":{"id":"t1","title":"Hausarbeit","link":null,"createdAt":"2026-09-04T10:00:00Z","doneAt":null,
                    "visibleUntil":null,"dueAt":null,"today":true,"reminders":[],"children":[]}},
           {"areaId":null,"areaName":null,"parentId":null,"parentTitle":null,
            "todo":{"id":"x","title":"Aufgabe X","link":null,"createdAt":"2026-09-04T10:00:00Z","doneAt":null,
                    "visibleUntil":null,"dueAt":null,"today":true,"reminders":[],"children":[]}}]},
         "includesHidden":false,"hiddenDoneCount":0,"now":"2026-09-04T12:00:00Z"}
        """.data(using: .utf8)!
        let board = try APIClient.decoder().decode(TodoBoard.self, from: data)
        XCTAssertTrue(board.areas[0].todos[0].today)
        XCTAssertEqual(board.today?.items.map(\.id), ["t1", "x"])
        XCTAssertTrue(board.today?.items[1].isAdHoc ?? false)
    }

    /// Ein Brett ohne „Heute" - aus dem Offline-Speicher von vorher - laedt weiter.
    func testABoardWithoutTodayStillLoads() throws {
        let data = #"{"areas":[],"includesHidden":false,"hiddenDoneCount":0,"now":"2026-09-04T12:00:00Z"}"#
        let board = try APIClient.decoder().decode(TodoBoard.self, from: Data(data.utf8))
        XCTAssertNil(board.today)
    }

    /// Das Brett nach dem Senden: was das Overlay zeigte, liefert jetzt der Dienst.
    private func withToday(_ board: TodoBoard) -> TodoBoard {
        let adHoc = board.today?.items.filter(\.isAdHoc) ?? []
        return TodoBoard(areas: board.areas, includesHidden: board.includesHidden,
                         hiddenDoneCount: board.hiddenDoneCount, now: board.now,
                         today: TodoToday(openCount: adHoc.count, items: adHoc))
    }
}
