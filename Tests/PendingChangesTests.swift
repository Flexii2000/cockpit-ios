import XCTest
@testable import Healthy

/// Die Warteschlange der sofort gezeigten Aenderungen - ohne Netz: der Weg zum
/// Dienst ist eine Attrappe, die der Reihe nach vorgegebene Antworten liefert.
@MainActor
final class PendingChangesTests: XCTestCase {

    /// Liefert die Antworten der Reihe nach und merkt sich, was gesendet wurde.
    private final class FakeService: @unchecked Sendable {
        var outcomes: [DeliveryOutcome] = []
        var sent: [PendingRequest] = []
        let lock = NSLock()

        func next(_ request: PendingRequest) -> DeliveryOutcome {
            lock.lock()
            defer { lock.unlock() }
            sent.append(request)
            return outcomes.isEmpty ? .offline : outcomes.removeFirst()
        }
    }

    private var directory: URL!
    private var file: URL { directory.appending(path: "changes.json") }

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "pending-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func queue(_ service: FakeService) -> PendingChanges {
        let queue = PendingChanges(file: file, transport: { _, request in service.next(request) }, sendsImmediately: false)
        // Kein Nachversuch im Takt - die Tests schicken selbst.
        queue.isForeground = false
        return queue
    }

    private static let board = Data(#"{"areas":[]}"#.utf8)

    private func create(_ id: String, title: String = "Aufgabe A", parent: String? = nil) -> PendingChange {
        .todo(.create(id: id, areaId: "privat", parentId: parent, title: title, dueAt: nil, at: Date()))
    }

    // MARK: - Senden

    func testADeliveredChangeLeavesAndTheStoreGetsTheBoard() async {
        let service = FakeService()
        service.outcomes = [.delivered(Self.board)]
        let queue = queue(service)
        var events: [PendingEvent] = []
        queue.observe(.todo) { events.append($0) }

        queue.enqueue(create("a"), label: "Aufgabe A")
        XCTAssertEqual(queue.count(for: .todo), 1, "sofort in der Warteschlange")
        await queue.replay(.todo)

        XCTAssertEqual(queue.count(for: .todo), 0)
        XCTAssertEqual(service.sent.first?.method, "POST")
        XCTAssertEqual(service.sent.first?.path, "/api/todos")
        let body = String(data: service.sent.first?.body ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains(#""id":"a""#), body)
        guard case .delivered(let data, _) = events.first else { return XCTFail("\(events)") }
        XCTAssertEqual(data, Self.board)
        guard case .drained = events.last else { return XCTFail("\(events)") }
        XCTAssertEqual(queue.laneState[.todo], .idle)
    }

    func testWithoutNetworkEverythingStaysAndTheLaneSaysSo() async {
        let service = FakeService()
        service.outcomes = [.offline]
        let queue = queue(service)
        queue.enqueue(create("a"), label: "Aufgabe A")
        await queue.replay(.todo)
        XCTAssertEqual(queue.count(for: .todo), 1)
        XCTAssertEqual(queue.laneState[.todo], .offline)
        XCTAssertTrue(queue.showsWaiting("a", on: .todo), "jetzt mit Uhr")
    }

    func testOneServiceDoesNotHoldUpTheOther() async {
        let service = FakeService()
        let queue = queue(service)
        queue.enqueue(create("a"), label: "Aufgabe A")
        queue.enqueue(.shopping(.add(id: "m", name: "Milch", quantity: nil, note: nil, category: nil,
                                     at: Date(), by: "felix")), label: "Milch")
        service.outcomes = [.serverDown]
        await queue.replay(.todo)
        service.outcomes = [.delivered(Data())]
        await queue.replay(.shopping)
        XCTAssertEqual(queue.count(for: .todo), 1)
        XCTAssertEqual(queue.count(for: .shopping), 0)
        XCTAssertEqual(queue.laneState[.todo], .serverDown)
    }

    func testARejectionDropsWhatBuildsOnItAndNamesTheItem() async {
        let service = FakeService()
        service.outcomes = [.rejected(status: 400, message: "Bereich nicht gefunden.")]
        let queue = queue(service)
        var notices: [String] = []
        queue.onNotice = { text, _ in notices.append(text) }
        var events: [PendingEvent] = []
        queue.observe(.todo) { events.append($0) }

        queue.enqueue(create("p", title: "Aufgabe A"), label: "Aufgabe A")
        queue.enqueue(create("c", title: "Aufgabe B", parent: "p"), label: "Aufgabe B")
        queue.enqueue(.todo(.setDone(id: "c", done: true, at: Date())), label: "Aufgabe B")
        queue.enqueue(create("x", title: "Aufgabe C"), label: "Aufgabe C")
        service.outcomes.append(.delivered(Self.board))
        await queue.replay(.todo)

        XCTAssertEqual(notices, ["„Aufgabe A“ wurde nicht angelegt: Bereich nicht gefunden."])
        XCTAssertEqual(queue.count(for: .todo), 0, "die Unteraufgabe und ihr Haken mit weg, Aufgabe C gesendet")
        XCTAssertEqual(service.sent.count, 2)
        XCTAssertEqual(queue.lastRejection[.todo], "„Aufgabe A“ wurde nicht angelegt: Bereich nicht gefunden.")
        XCTAssertTrue(events.contains { if case .rejected = $0 { true } else { false } })
    }

    func testGoneIsAHintNotAnError() async {
        let service = FakeService()
        service.outcomes = [.rejected(status: 404, message: "Eintrag nicht gefunden.")]
        let queue = queue(service)
        var notices: [(String, Bool)] = []
        queue.onNotice = { notices.append(($0, $1)) }
        queue.enqueue(.shopping(.setChecked(id: "m", checked: true, at: Date(), by: "felix")), label: "Milch")
        await queue.replay(.shopping)
        XCTAssertEqual(notices.first?.0, "„Milch“ stand nicht mehr auf der Liste.")
        XCTAssertEqual(notices.first?.1, true)
        XCTAssertNil(queue.lastRejection[.shopping], "ein Hinweis bleibt nicht in der Leiste stehen")
    }

    func testDeletingSomethingAlreadyGoneIsDone() async {
        let service = FakeService()
        service.outcomes = [.rejected(status: 404, message: nil)]
        let queue = queue(service)
        var notices: [String] = []
        queue.onNotice = { text, _ in notices.append(text) }
        queue.enqueue(.todo(.delete(id: "a")), label: "Aufgabe A")
        await queue.replay(.todo)
        XCTAssertEqual(queue.count(for: .todo), 0)
        XCTAssertTrue(notices.isEmpty)
    }

    func testWithoutAccessEverythingWaits() async {
        let service = FakeService()
        service.outcomes = [.accessDenied]
        let queue = queue(service)
        queue.enqueue(create("a"), label: "Aufgabe A")
        queue.enqueue(create("b"), label: "Aufgabe B")
        await queue.replay(.todo)
        XCTAssertEqual(queue.count(for: .todo), 2)
        XCTAssertEqual(queue.laneState[.todo], .accessDenied)
        XCTAssertEqual(service.sent.count, 1, "nach dem ersten „kein Zugang“ nichts mehr")
    }

    // MARK: - Zusammenfassen

    func testTogglingTwiceKeepsTheLastState() {
        let queue = queue(FakeService())
        queue.enqueue(.todo(.setDone(id: "a", done: true, at: Date())), label: "Aufgabe A")
        queue.enqueue(.todo(.setDone(id: "a", done: false, at: Date())), label: "Aufgabe A")
        guard case .todo(.setDone(_, let done, _)) = queue.changes(for: .todo).first else { return XCTFail() }
        XCTAssertFalse(done)
        XCTAssertEqual(queue.count(for: .todo), 1)
    }

    func testAnEditFoldsIntoAWaitingCreate() {
        let queue = queue(FakeService())
        queue.enqueue(create("a", title: "Aufgabe A"), label: "Aufgabe A")
        queue.enqueue(.todo(.update(id: "a", title: "Aufgabe B", dueAt: CalendarDate(year: 2026, month: 10, day: 20))),
                      label: "Aufgabe B")
        XCTAssertEqual(queue.count(for: .todo), 1)
        guard case .todo(.create(_, _, _, let title, let dueAt, _, _)) = queue.changes(for: .todo).first else {
            return XCTFail()
        }
        XCTAssertEqual(title, "Aufgabe B")
        XCTAssertEqual(dueAt, CalendarDate(year: 2026, month: 10, day: 20))
    }

    func testDeletingSomethingOnlyLocalSendsNothing() {
        let queue = queue(FakeService())
        queue.enqueue(create("p"), label: "Aufgabe A")
        queue.enqueue(create("c", parent: "p"), label: "Aufgabe B")
        queue.enqueue(.todo(.setDone(id: "c", done: true, at: Date())), label: "Aufgabe B")
        queue.enqueue(.todo(.delete(id: "p")), label: "Aufgabe A")
        XCTAssertEqual(queue.count(for: .todo), 0, "Aufgabe, Unteraufgabe und Haken - nichts davon geht raus")
    }

    func testWhatIsUnderwayIsNotTouched() async {
        let service = FakeService()
        let gate = AsyncGate()
        let queue = PendingChanges(file: file, transport: { _, request in
            await gate.wait()
            return service.next(request)
        }, sendsImmediately: false)
        queue.isForeground = false
        queue.enqueue(create("a"), label: "Aufgabe A")
        let sending = Task { await queue.replay(.todo) }
        await Task.yield()
        while queue.inFlight[.todo] == nil { await Task.yield() }
        // Das Anlegen ist unterwegs - Loeschen muss also gesendet werden.
        queue.enqueue(.todo(.delete(id: "a")), label: "Aufgabe A")
        XCTAssertEqual(queue.count(for: .todo), 2)
        service.outcomes = [.delivered(Self.board), .delivered(Self.board)]
        await gate.open()
        await sending.value
        XCTAssertEqual(service.sent.map(\.method), ["POST", "DELETE"])
        XCTAssertEqual(queue.count(for: .todo), 0)
    }

    // MARK: - Ablage

    func testWhatWaitsSurvivesARestart() async {
        let service = FakeService()
        var first: PendingChanges? = queue(service)
        first?.enqueue(create("a"), label: "Aufgabe A")
        first?.enqueue(.shopping(.clearChecked(ids: ["x"])), label: "Abgehakte")
        first = nil
        let second = queue(service)
        XCTAssertEqual(second.count(for: .todo), 1)
        XCTAssertEqual(second.count(for: .shopping), 1)
        XCTAssertTrue(second.isLocal("a", on: .todo))
    }

    func testAnUnreadableFileIsSetAsideNotOverwritten() throws {
        try Data("kaputt".utf8).write(to: file)
        let queue = PendingChanges(file: file, transport: { _, _ in .offline }, sendsImmediately: false)
        XCTAssertEqual(queue.count(for: .todo), 0)
        queue.enqueue(create("a"), label: "Aufgabe A")
        let aside = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("changes-unreadable-") }
        XCTAssertEqual(aside.count, 1, "die kaputte Datei liegt daneben")
    }

    func testClearingAServiceDropsOnlyItsChanges() {
        let queue = queue(FakeService())
        queue.enqueue(create("a"), label: "Aufgabe A")
        queue.enqueue(.shopping(.delete(id: "m")), label: "Milch")
        queue.clear([.shopping])
        XCTAssertEqual(queue.count(for: .todo), 1)
        XCTAssertEqual(queue.count(for: .shopping), 0)
    }
}

/// Haelt einen Aufruf an, bis der Test ihn freigibt.
private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}
