import XCTest
@testable import Healthy

/// Was die App zeigt, waehrend Aenderungen warten: der Stand des Dienstes und
/// darueber das Wartende - so, wie der Dienst es danach zeigen wird.
final class TodoOverlayTests: XCTestCase {

    private let earlier = Date(timeIntervalSince1970: 1_790_000_000)
    private let now = Date(timeIntervalSince1970: 1_790_100_000)

    private func item(_ id: String, _ title: String, done: Date? = nil, children: [TodoItem] = []) -> TodoItem {
        TodoItem(id: id, title: title, link: nil, createdAt: earlier, doneAt: done, visibleUntil: nil,
                 dueAt: nil, reminders: [], children: children)
    }

    private func board(_ todos: [TodoItem]) -> TodoBoard {
        TodoBoard(areas: [TodoArea(id: "privat", name: "Privat", position: 0, openCount: 1, hiddenDoneCount: 0,
                                   todos: todos)],
                  includesHidden: false, hiddenDoneCount: 0, now: earlier)
    }

    func testANewTaskAndSubtaskStandWhereTheServiceWouldPutThem() {
        let base = board([item("a", "Aufgabe A")])
        let shown = TodoOverlay.apply([
            .create(id: "b", areaId: "privat", parentId: nil, title: "Aufgabe B", dueAt: nil, at: now),
            .create(id: "c", areaId: "privat", parentId: "b", title: "Aufgabe C", dueAt: nil, at: now),
        ], to: base)
        let area = shown.areas[0]
        XCTAssertEqual(area.todos.map(\.id), ["a", "b"], "neue offene unten, wie beim Dienst nach createdAt")
        XCTAssertEqual(area.todos[1].children.map(\.id), ["c"])
        XCTAssertEqual(area.openCount, 3)
    }

    func testCheckingMovesItDownAndCountsIt() {
        let base = board([item("a", "Aufgabe A"), item("b", "Aufgabe B")])
        let shown = TodoOverlay.apply([.setDone(id: "a", done: true, at: now)], to: base)
        XCTAssertEqual(shown.areas[0].todos.map(\.id), ["b", "a"], "Erledigtes hinter die offenen")
        XCTAssertEqual(shown.areas[0].todos[1].doneAt, now)
        XCTAssertEqual(shown.areas[0].openCount, 1)

        let back = TodoOverlay.apply([.setDone(id: "a", done: true, at: now), .setDone(id: "a", done: false, at: now)],
                                     to: base)
        XCTAssertNil(back.areas[0].todos.first { $0.id == "a" }?.doneAt)
    }

    func testCheckingKeepsTheFirstTime() {
        let base = board([item("a", "Aufgabe A", done: earlier)])
        let shown = TodoOverlay.apply([.setDone(id: "a", done: true, at: now)], to: base)
        XCTAssertEqual(shown.areas[0].todos[0].doneAt, earlier)
    }

    func testRenamingAndDeletingWithChildren() {
        let base = board([item("a", "Aufgabe A", children: [item("c", "Aufgabe C")]), item("b", "Aufgabe B")])
        var shown = TodoOverlay.apply([.update(id: "c", title: "Aufgabe D", dueAt: CalendarDate(year: 2026, month: 11, day: 1))],
                                      to: base)
        XCTAssertEqual(shown.areas[0].todos[0].children[0].title, "Aufgabe D")
        XCTAssertEqual(shown.areas[0].todos[0].children[0].dueAt, CalendarDate(year: 2026, month: 11, day: 1))
        shown = TodoOverlay.apply([.delete(id: "a")], to: base)
        XCTAssertEqual(shown.areas[0].todos.map(\.id), ["b"])
        XCTAssertEqual(shown.areas[0].openCount, 1)
    }

    /// Kam die Antwort schon, steht die Aufgabe im Brett - dann nicht doppelt.
    func testWhatTheServiceAlreadyHasIsNotAddedTwice() {
        let base = board([item("a", "Aufgabe A")])
        let shown = TodoOverlay.apply([.create(id: "a", areaId: "privat", parentId: nil, title: "Aufgabe A",
                                               dueAt: nil, at: now)], to: base)
        XCTAssertEqual(shown.areas[0].todos.count, 1)
    }

    func testASubtaskUnderAMissingTaskIsNotShown() {
        let shown = TodoOverlay.apply([.create(id: "c", areaId: "privat", parentId: "weg", title: "Aufgabe C",
                                               dueAt: nil, at: now)], to: board([]))
        XCTAssertTrue(shown.areas[0].todos.isEmpty)
    }
}

final class ShoppingOverlayTests: XCTestCase {

    private let earlier = Date(timeIntervalSince1970: 1_790_000_000)
    private let now = Date(timeIntervalSince1970: 1_790_100_000)

    private func category(_ key: String) -> ShoppingCategory {
        ShoppingCategory(key: key, label: key, emoji: "", symbol: "", color: nil)
    }

    private func item(_ id: String, _ name: String, quantity: String? = nil, category: String = "dairy",
                      checked: Date? = nil) -> ShoppingItem {
        ShoppingItem(id: id, name: name, quantity: quantity, note: nil, addedAt: earlier, addedBy: "joana",
                     checkedAt: checked, checkedBy: checked == nil ? nil : "joana", dishId: nil, ruleId: nil,
                     category: category)
    }

    private func board(_ items: [ShoppingItem]) -> ShoppingBoard {
        ShoppingBoard(me: "felix", categories: [category("produce"), category("dairy"), category("other")],
                      items: items, dishes: [], recurring: [])
    }

    func testSameNameBecomesOneEntryLikeAtTheService() {
        let base = board([item("m", "Milch", quantity: "1 l")])
        let shown = ShoppingOverlay.apply([.add(id: "n", name: "  milch ", quantity: "2 l", note: nil, category: nil,
                                                at: now, by: "felix")], to: base)
        XCTAssertEqual(shown.items.count, 1)
        XCTAssertEqual(shown.items[0].id, "m", "der Eintrag der anderen Person bleibt, die Menge waechst")
        XCTAssertEqual(shown.items[0].quantity, "3 l")
    }

    func testANewNameGoesToTheEndUntilTheServiceKnowsItsCategory() {
        let base = board([item("m", "Milch"), item("a", "Äpfel", category: "produce")])
        let shown = ShoppingOverlay.apply([.add(id: "n", name: "Batterien", quantity: nil, note: nil, category: nil,
                                                at: now, by: "felix")], to: base)
        XCTAssertEqual(shown.items.map(\.id), ["a", "m", "n"])
        XCTAssertEqual(shown.items[2].addedBy, "felix")
    }

    func testCheckingMovesItIntoTheCartNewestFirst() {
        let base = board([item("m", "Milch"), item("b", "Butter"), item("k", "Käse", checked: earlier)])
        let shown = ShoppingOverlay.apply([.setChecked(id: "m", checked: true, at: now, by: "felix")], to: base)
        XCTAssertEqual(shown.items.map(\.id), ["b", "m", "k"])
        XCTAssertEqual(shown.items[1].checkedBy, "felix")
    }

    func testClearingOnlyTheListedCheckedOnes() {
        let base = board([item("m", "Milch", checked: earlier), item("b", "Butter", checked: earlier), item("k", "Käse")])
        let shown = ShoppingOverlay.apply([.clearChecked(ids: ["m", "k"])], to: base)
        XCTAssertEqual(shown.items.map(\.id), ["k", "b"], "Butter nicht genannt, Käse nicht abgehakt")
    }

    func testADishMergesWhatIsThereAndAddsTheRest() {
        let base = board([item("z", "Zwiebeln", quantity: "1 Stk", category: "produce")])
        let shown = ShoppingOverlay.apply([.addDish(dishId: "d", dishName: "Suppe", items: [
            .init(id: "x", name: "Zwiebeln", quantity: "2 Stk"),
            .init(id: "y", name: "Lauch", quantity: "1 Stange"),
        ], at: now, by: "felix")], to: base)
        XCTAssertEqual(shown.items.map(\.id), ["z", "y"])
        XCTAssertEqual(shown.items[0].quantity, "3 Stk")
        XCTAssertEqual(shown.items[0].note, "Suppe")
        XCTAssertEqual(shown.items[1].note, "Suppe")
        XCTAssertEqual(shown.items[1].dishId, "d")
    }

    func testEditingAndDeleting() {
        let base = board([item("m", "Milch")])
        var shown = ShoppingOverlay.apply([.update(id: "m", name: "Hafermilch", quantity: "2 l", note: "ohne Zucker",
                                                   category: nil)], to: base)
        XCTAssertEqual(shown.items[0].name, "Hafermilch")
        XCTAssertEqual(shown.items[0].category, "dairy", "ohne gewaehlte Kategorie bleibt die alte")
        shown = ShoppingOverlay.apply([.delete(id: "m")], to: base)
        XCTAssertTrue(shown.items.isEmpty)
    }
}

/// Wie die App eine Antwort beim Nachsenden einordnet - gegen einen Dienst aus der Dose.
final class DeliveryOutcomeTests: XCTestCase {

    private final class Stub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var contentType = "application/json"
        nonisolated(unsafe) static var body = Data()
        nonisolated(unsafe) static var fails = false

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            if Self.fails {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil,
                                           headerFields: ["Content-Type": Self.contentType])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Stub.self]
        return URLSession(configuration: configuration)
    }

    private func outcome(status: Int = 200, type: String = "application/json", body: String = "{}",
                         fails: Bool = false) async -> DeliveryOutcome {
        Stub.status = status
        Stub.contentType = type
        Stub.body = Data(body.utf8)
        Stub.fails = fails
        return await APIClient(backend: .shopping).deliver(
            PendingRequest(method: "POST", path: "/api/items/m/check", body: Data("{}".utf8)), session: session)
    }

    func testTheAnswersAreSortedIntoWhatHappensNext() async {
        let delivered = await outcome(body: #"{"items":[]}"#)
        XCTAssertEqual(delivered, .delivered(Data(#"{"items":[]}"#.utf8)))
        let loginPage = await outcome(type: "text/html; charset=utf-8", body: "<html>Anmelden</html>")
        XCTAssertEqual(loginPage, .accessDenied, "die Anmeldeseite nach der Weiterleitung ist kein Erfolg")
        let forbidden = await outcome(status: 403)
        XCTAssertEqual(forbidden, .accessDenied)
        let gone = await outcome(status: 404, type: "text/plain", body: "Eintrag nicht gefunden.")
        XCTAssertEqual(gone, .rejected(status: 404, message: "Eintrag nicht gefunden."))
        let busy = await outcome(status: 503)
        XCTAssertEqual(busy, .serverDown)
        let tooMany = await outcome(status: 429)
        XCTAssertEqual(tooMany, .serverDown)
        let offline = await outcome(fails: true)
        XCTAssertEqual(offline, .offline)
    }
}
