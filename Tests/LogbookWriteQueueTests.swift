import XCTest
@testable import Healthy

/// Logbook-Werte in der Warteschlange (`PendingChanges`, Fall `.logbook`): je Tag
/// und Verhaltensweise gilt der neueste, was unterwegs ist, bleibt, und eine
/// Ablehnung nennt Verhalten und Tag.
@MainActor
final class LogbookWriteQueueTests: XCTestCase {

    private var directory: URL!
    private var file: URL { directory.appending(path: "changes.json") }
    private let day = CalendarDate(year: 2026, month: 10, day: 11)

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "logbook-queue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private final class Recorder: @unchecked Sendable {
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

    private func queue(_ recorder: Recorder) -> PendingChanges {
        let queue = PendingChanges(file: file, transport: { _, request in recorder.next(request) },
                                   sendsImmediately: false)
        queue.isForeground = false
        return queue
    }

    private func value(_ id: String, _ value: Double?, on date: CalendarDate? = nil) -> PendingChange {
        .logbook(.setValue(date: date ?? day, behaviorId: id, value: value))
    }

    func testTheNewestValuePerRowWins() {
        let queue = queue(Recorder())
        queue.enqueue(value("b-1", 1), label: "Verhalten A")
        queue.enqueue(value("b-1", 2), label: "Verhalten A")
        queue.enqueue(value("b-1", nil), label: "Verhalten A")
        queue.enqueue(value("b-2", 3), label: "Verhalten B")
        queue.enqueue(value("b-1", 1, on: day.adding(days: -1)), label: "Verhalten A")
        let changes = queue.changes(for: .weight).compactMap(\.logbook)
        XCTAssertEqual(changes.count, 3, "je Tag und Verhaltensweise einer")
        XCTAssertEqual(changes.first { $0.behaviorId == "b-1" && $0.date == day }?.value, .some(nil))
        XCTAssertTrue(queue.isWaiting(LogbookChange.key(day, "b-2"), on: .weight))
    }

    func testWhatIsUnderwayStaysAndTheNewerFollows() async {
        let recorder = Recorder()
        let gate = Gate()
        let queue = PendingChanges(file: file, transport: { _, request in
            await gate.wait()
            return recorder.next(request)
        }, sendsImmediately: false)
        queue.isForeground = false
        queue.enqueue(value("b-1", 1), label: "Verhalten A")
        let sending = Task { await queue.replay(.weight) }
        while queue.inFlight[.weight] == nil { await Task.yield() }
        queue.enqueue(value("b-1", 2), label: "Verhalten A")
        XCTAssertEqual(queue.count(for: .weight), 2, "der unterwegs bleibt, der neue wartet dahinter")
        recorder.outcomes = [.delivered(Data()), .delivered(Data())]
        await gate.open()
        await sending.value
        let bodies = recorder.sent.map { String(decoding: $0.body ?? Data(), as: UTF8.self) }
        XCTAssertEqual(bodies, [#"{"value":1}"#, #"{"value":2}"#])
        XCTAssertEqual(queue.count(for: .weight), 0)
    }

    /// Lehnt der Dienst ab, faellt der Wert weg - die Zeile zeigt wieder seinen Stand.
    func testARejectionNamesBehaviorAndDay() async {
        let recorder = Recorder()
        recorder.outcomes = [.rejected(status: 400, message: "Außerhalb der Nachtragsfrist.")]
        let queue = queue(recorder)
        var notices: [String] = []
        queue.onNotice = { text, _ in notices.append(text) }
        queue.enqueue(value("b-1", 1), label: "Verhalten A")
        await queue.replay(.weight)
        XCTAssertEqual(notices, ["„Verhalten A“ am 11.10. ließ sich nicht eintragen: Außerhalb der Nachtragsfrist."])
        XCTAssertEqual(queue.count(for: .weight), 0)
    }

    /// Eine Verhaltensweise, die ein anderes Geraet geloescht hat: ein Hinweis, kein Fehler.
    func testAGoneBehaviorIsAHint() async {
        let recorder = Recorder()
        recorder.outcomes = [.rejected(status: 404, message: "Unbekannte Verhaltensweise.")]
        let queue = queue(recorder)
        var notices: [(String, Bool)] = []
        queue.onNotice = { notices.append(($0, $1)) }
        queue.enqueue(value("b-1", 1), label: "Verhalten A")
        await queue.replay(.weight)
        XCTAssertEqual(notices.first?.0, "„Verhalten A“ gibt es im Logbook nicht mehr.")
        XCTAssertEqual(notices.first?.1, true)
    }

    /// Ohne Netz bleibt der Wert - auch ueber einen Neustart.
    func testAWaitingValueSurvivesARestart() async {
        let recorder = Recorder()
        var first: PendingChanges? = queue(recorder)
        first?.enqueue(value("b-2", 2.5), label: "Verhalten B")
        await first?.replay(.weight)
        XCTAssertEqual(first?.laneState[.weight], .offline)
        first = nil
        let second = queue(recorder)
        XCTAssertEqual(second.changes(for: .weight).compactMap(\.logbook),
                       [.setValue(date: day, behaviorId: "b-2", value: 2.5)])
    }

    /// Die Antwort ist ein Tag, kein Brett - sie darf den Offline-Stand von
    /// `/api/logbook` nicht ersetzen.
    func testTheAnswerIsNoBoard() {
        XCTAssertNil(value("b-1", 1).boardPath)
        XCTAssertEqual(PendingChange.todo(.delete(id: "a")).boardPath, "/api/board")
    }
}

/// Haelt einen Aufruf an, bis der Test ihn freigibt.
private actor Gate {
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
