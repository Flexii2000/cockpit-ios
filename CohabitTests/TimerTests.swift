import XCTest
@testable import coHabit

/// Minuten pro Woche mit Timer (Vertrag §2.4b, §5.2d): die JSON-Formen, der
/// Postausgang fuer Start und Stopp und der Timer gegen einen Dienst aus der
/// Dose. Nur Platzhalter - das Repo ist oeffentlich.
@MainActor
final class TimerTests: XCTestCase {

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "timer-\(UUID().uuidString)")
        CohabitSync.shared.reset()
        let controller = TimerController.shared
        controller.reset()
        controller.activities = false
        controller.makeAPI = { StubServer.api() }
        controller.outbox = CohabitOutbox(directory: directory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        CohabitSync.shared.reset()
        TimerController.shared.reset()
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder().decode(T.self, from: Fixtures.data(json))
    }

    /// Wie `GET /cohabits` ein Co-Habit mit Timer liefert.
    private static func timerSummary(startedAt: String = "null") -> String {
        """
        {"ref":{"id":"c-timer","name":"Gewohnheit A","color":"peach","type":"STREAK"},"archived":false,
         "headline":{"value":"2","unit":"Wochen","short":"2 Wo."},
         "typeLine":"Streak · 140 Min. pro Woche",
         "subline":"noch 100 Min. diese Woche","listLine":"40 von 140 Min.",
         "status":"OPEN","section":"OPEN_TODAY","unavailableText":null,
         "canCheckIn":true,"photoRequired":false,"valueUnit":"MINUTES","checkInLabel":"Minuten eintragen",
         "runEntry":false,"members":[\(Fixtures.felix)],"memberCount":1,"doneTodayBy":[],
         "progress":{"done":40,"goal":140,"fraction":0.29},"rank":null,"unreadMessages":0,"limit":null,
         "timer":{"startedAt":\(startedAt)}}
        """
    }

    // MARK: - Formen

    func testTheSummaryCarriesTheTimer() throws {
        let stopped = try decode(CohabitSummary.self, Self.timerSummary())
        XCTAssertNotNil(stopped.timer)
        XCTAssertNil(stopped.timer?.startedAt)
        XCTAssertEqual(stopped.gauge, .bar(0.29), "Minuten gegen das Wochenziel als Balken, nicht 140 Punkte")

        let running = try decode(CohabitSummary.self, Self.timerSummary(startedAt: #""2026-10-28T17:05:00.123456Z""#))
        // Bruchteile einer Sekunde liest die App nicht - wie bei jedem Zeitpunkt des Dienstes.
        XCTAssertEqual(try XCTUnwrap(running.timer?.startedAt).timeIntervalSince1970, 1_793_207_100, accuracy: 1)

        XCTAssertNil(try decode(CohabitSummary.self, Fixtures.summary).timer, "ohne Timer fehlt er")
    }

    func testTheConfigSendsMinutesAndTimer() throws {
        var config = try decode(CohabitConfig.self, """
        {"type":"STREAK","name":"Gewohnheit A","color":"peach","timezone":"Europe/Berlin",
         "tracking":{"mode":"VALUE","unit":"MINUTES","timer":true},"photoRequired":false,"backfillHours":336,
         "reminderTime":null,"membersCanInvite":false,
         "streak":{"rhythm":{"kind":"MINUTES_PER_WEEK","minutes":140},"groupStreak":false},
         "abstinence":null,"goal":null,"challenge":null,"health":null,"auto":null}
        """)
        XCTAssertTrue(config.isMinutesPerWeek)
        XCTAssertTrue(config.tracking.isTimer)
        config.streak?.rhythm.minutes = 150
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: APIClient.encoder().encode(config)) as? [String: Any])
        let rhythm = try XCTUnwrap((sent["streak"] as? [String: Any])?["rhythm"] as? [String: Any])
        XCTAssertEqual(rhythm["kind"] as? String, "MINUTES_PER_WEEK")
        XCTAssertEqual(rhythm["minutes"] as? Int, 150)
        XCTAssertEqual((sent["tracking"] as? [String: Any])?["timer"] as? Bool, true)

        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: APIClient.encoder().encode(
            CohabitConfig.Tracking(mode: "VALUE", unit: "KM"))) as? [String: Any])
        XCTAssertNil(plain["timer"], "ohne Timer kein Schluessel - ein Bearbeiten laesst ihn dann stehen")
    }

    // MARK: - Postausgang

    func testStartAndStopWaitWithTheirTapTimes() async throws {
        let outbox = CohabitOutbox(directory: directory)
        let start = Date(timeIntervalSince1970: 1_793_207_100)
        await outbox.enqueueTimerStart(cohabitId: "c-timer", request: TimerStartRequest(startedAt: start))
        XCTAssertEqual(CohabitSync.shared.pendingTimers["c-timer"], .running(since: start))
        let stop = TimerStopRequest(stoppedAt: start.addingTimeInterval(25 * 60))
        await outbox.enqueueTimerStop(cohabitId: "c-timer", request: stop)
        XCTAssertEqual(CohabitSync.shared.pendingTimers["c-timer"], .stopped)

        StubServer.install { _ in .json(201, "{}") }
        await outbox.replay(using: StubServer.api())
        XCTAssertEqual(StubServer.requests.map(\.path), ["/cohabit/api/cohabits/c-timer/timer",
                                                         "/cohabit/api/cohabits/c-timer/timer/stop"])
        XCTAssertEqual(StubServer.requests.first?.json?["startedAt"] as? String, "2026-10-28T17:05:00Z")
        XCTAssertEqual(StubServer.requests.last?.json?["stoppedAt"] as? String, "2026-10-28T17:30:00Z")
        XCTAssertEqual(StubServer.requests.last?.json?["id"] as? String, stop.id)
        XCTAssertTrue(CohabitSync.shared.pendingTimers.isEmpty)
    }

    /// „Der Timer läuft nicht.“ heisst: schon gestoppt (etwa im Web) - kein Fehler.
    func testAStopForAStoppedTimerIsDone() async {
        let outbox = CohabitOutbox(directory: directory)
        await outbox.enqueueTimerStop(cohabitId: "c-timer", request: TimerStopRequest(stoppedAt: Date()))
        StubServer.install { _ in .json(409, #"{"message":"Der Timer läuft nicht."}"#) }
        await outbox.replay(using: StubServer.api())
        let entries = await outbox.entries()
        XCTAssertTrue(entries.isEmpty)
        XCTAssertNil(CohabitSync.shared.lastError)
    }

    // MARK: - Timer

    func testStartingShowsTheTimerAtOnceAndWaitsWithoutNetwork() async throws {
        StubServer.install { _ in .offline }
        let summary = try decode(CohabitSummary.self, Self.timerSummary())
        let controller = TimerController.shared
        controller.start(TimerTarget(summary: summary))
        XCTAssertNotNil(controller.startedAt("c-timer", server: summary.timer), "der Timer laeuft sofort")
        await controller.settled("c-timer")
        let entries = await controller.outbox.entries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(controller.isWaiting("c-timer"))
    }

    /// Lehnt der Dienst den Stopp ab (lief ueber 24 Stunden), laeuft der Timer weiter.
    func testARejectedStopKeepsTheTimerRunning() async throws {
        StubServer.install { _ in .json(400, #"{"message":"Der Timer lief länger als 24 Stunden."}"#) }
        let summary = try decode(CohabitSummary.self, Self.timerSummary(startedAt: #""2026-10-26T08:00:00Z""#))
        let controller = TimerController.shared
        controller.stop(TimerTarget(summary: summary))
        XCTAssertNil(controller.startedAt("c-timer", server: summary.timer), "der Stopp zeigt sofort")
        await controller.settled("c-timer")
        XCTAssertEqual(controller.startedAt("c-timer", server: summary.timer), summary.timer?.startedAt)
        XCTAssertEqual(StubServer.requests.last?.path, "/cohabit/api/cohabits/c-timer/timer/stop")
    }

    func testAStopEntersTheMinutes() async throws {
        StubServer.install { _ in .json(201, #"{"checkin":null,"cohabit":null}"#) }
        let summary = try decode(CohabitSummary.self, Self.timerSummary(startedAt: #""2026-10-28T08:00:00Z""#))
        let controller = TimerController.shared
        controller.stop(TimerTarget(summary: summary))
        await controller.settled("c-timer")
        XCTAssertNil(controller.startedAt("c-timer", server: summary.timer))
        XCTAssertNotNil(StubServer.requests.last?.json?["stoppedAt"])
    }
}
