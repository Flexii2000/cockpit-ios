import XCTest
@testable import coHabit

/// Abstinenz mit Tageslimit (Vertrag §2.5a, §5.2c): die JSON-Formen, der
/// Postausgang (je Tag die neueste Zahl) und der Zaehler gegen einen Dienst aus
/// der Dose. Nur Platzhalter - das Repo ist oeffentlich.
@MainActor
final class LimitTests: XCTestCase {

    private let today = CalendarDate(year: 2026, month: 10, day: 12)
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "limit-\(UUID().uuidString)")
        CohabitSync.shared.reset()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        CohabitSync.shared.reset()
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder().decode(T.self, from: Fixtures.data(json))
    }

    private static let todayLimit =
        #"{"date":"2026-10-12","count":2,"perDay":4,"unit":"Tassen","text":"heute 2 von 4 Tassen","over":false,"canCount":true}"#

    /// Wie `GET /cohabits` ein Tageslimit liefert.
    private static func limitSummary(limit: String = todayLimit) -> String {
        """
        {"ref":{"id":"c-limit","name":"Gewohnheit A","color":"mint","type":"ABSTINENCE"},"archived":false,
         "headline":{"value":"10","unit":"Tage","short":"10 T"},
         "typeLine":"Limit · höchstens 4 Tassen am Tag",
         "subline":"heute 2 von 4 Tassen","listLine":"heute 2 von 4 · Rekord 10 Tage",
         "status":"RUNNING","section":"RUNNING","unavailableText":null,
         "canCheckIn":false,"photoRequired":false,"valueUnit":null,"checkInLabel":null,"runEntry":false,
         "members":[\(Fixtures.felix)],"memberCount":1,"doneTodayBy":[],"progress":null,"rank":null,
         "unreadMessages":0,"limit":\(limit)}
        """
    }

    // MARK: - Formen

    func testTheSummaryCarriesTodaysCount() throws {
        let summary = try decode(CohabitSummary.self, Self.limitSummary())
        let limit = try XCTUnwrap(summary.limit)
        XCTAssertEqual(limit.date, today)
        XCTAssertEqual(limit.count, 2)
        XCTAssertEqual(limit.perDay, 4)
        XCTAssertTrue(limit.canCount)
        XCTAssertEqual(limit.liveText(3), "heute 3 von 4 Tassen")
        XCTAssertEqual(limit.liveText(2.5, withUnit: false), "heute 2,5 von 4")

        let plain = try decode(CohabitSummary.self, Fixtures.summary)
        XCTAssertNil(plain.limit, "ohne Limit - und bei einem aelteren Dienst - fehlt es")
    }

    func testWithoutTheLogbookThereIsNoNumber() throws {
        let json = Self.limitSummary(limit:
            #"{"date":"2026-10-12","count":null,"perDay":4,"unit":"Tassen","text":null,"over":false,"canCount":false}"#)
        let limit = try XCTUnwrap(try decode(CohabitSummary.self, json).limit)
        XCTAssertNil(limit.count)
        XCTAssertFalse(limit.canCount)
        XCTAssertEqual(LimitFormat.count(limit.count), "–")
    }

    func testTheLastDaysAndTheConfig() throws {
        let block = try decode(AbstinenceBlock.self, """
        {"currentDays":0,"record":9,"toRecordText":null,"members":[],"series":[],"group":null,
         "limitDays":[{"date":"2026-10-12","count":5,"countText":"5","over":true},
                      {"date":"2026-10-11","count":null,"countText":"–","over":false}]}
        """)
        XCTAssertEqual(block.limitDays?.map(\.countText), ["5", "–"])
        XCTAssertEqual(block.limitDays?.first?.over, true)
        XCTAssertNil(try decode(AbstinenceBlock.self, Fixtures.abstinence).limitDays)

        var config = try decode(CohabitConfig.self, """
        {"type":"ABSTINENCE","name":"Gewohnheit A","color":"mint","timezone":"Europe/Berlin",
         "tracking":{"mode":"CHECK"},"photoRequired":false,"backfillHours":336,"reminderTime":null,
         "membersCanInvite":false,"streak":null,
         "abstinence":{"groupMode":false,"limit":{"source":"LOGBOOK","behaviorId":"b-a","perDay":4,
                       "behaviorName":"Verhalten A","unitLabel":"Tassen"}},
         "goal":null,"challenge":null,"health":null,"auto":null}
        """)
        XCTAssertTrue(config.isLimit)
        config.abstinence?.limit?.perDay = 3
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: APIClient.encoder().encode(config)) as? [String: Any])
        let limit = try XCTUnwrap((sent["abstinence"] as? [String: Any])?["limit"] as? [String: Any])
        XCTAssertEqual(limit["perDay"] as? Int, 3, "beim Bearbeiten geht das neue Limit mit")
        XCTAssertEqual(limit["behaviorId"] as? String, "b-a")
    }

    // MARK: - Postausgang

    func testTheNewestCountPerDayWaits() async throws {
        let outbox = CohabitOutbox(directory: directory)
        await outbox.enqueueLimitCount(cohabitId: "c-limit", date: today, count: 1)
        await outbox.enqueueLimitCount(cohabitId: "c-limit", date: today, count: 2)
        await outbox.enqueueLimitCount(cohabitId: "c-limit", date: today.adding(days: -1), count: 6)
        let entries = await outbox.entries()
        XCTAssertEqual(entries.count, 2, "je Tag eine Zahl")
        XCTAssertEqual(CohabitSync.shared.pendingLimits[LimitKey(cohabitId: "c-limit", date: today)], 2)

        StubServer.install { _ in .json(200, "{}") }
        await outbox.replay(using: StubServer.api())
        XCTAssertEqual(StubServer.requests.map(\.method), ["PUT", "PUT"])
        XCTAssertEqual(StubServer.requests.first?.path, "/cohabit/api/cohabits/c-limit/count/2026-10-12")
        XCTAssertEqual(StubServer.requests.first?.json?["count"] as? Double, 2)
        XCTAssertTrue(CohabitSync.shared.pendingLimits.isEmpty)
    }

    /// Lehnt der Dienst ab, faellt die Zahl weg, und der Grund steht in der Leiste.
    func testARejectedCountIsDropped() async {
        let outbox = CohabitOutbox(directory: directory)
        await outbox.enqueueLimitCount(cohabitId: "c-limit", date: today, count: 3)
        StubServer.install { _ in .json(400, #"{"message":"Außerhalb der Nachtragsfrist."}"#) }
        await outbox.replay(using: StubServer.api())
        let entries = await outbox.entries()
        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(CohabitSync.shared.lastError, "Nicht angenommen: Außerhalb der Nachtragsfrist.")
    }

    /// Antwortet das Logbook nicht (503), wartet die Zahl - wie ohne Netz.
    func testAnUnreachableLogbookKeepsTheCount() async {
        let outbox = CohabitOutbox(directory: directory)
        await outbox.enqueueLimitCount(cohabitId: "c-limit", date: today, count: 3)
        StubServer.install { _ in .json(503, #"{"message":"Logbook nicht erreichbar"}"#) }
        await outbox.replay(using: StubServer.api())
        let entries = await outbox.entries()
        XCTAssertEqual(entries.count, 1)
    }

    // MARK: - Zaehler

    private func counter() -> LimitCounter {
        let counter = LimitCounter()
        counter.makeAPI = { StubServer.api() }
        counter.outbox = CohabitOutbox(directory: directory)
        counter.settleDelay = .milliseconds(20)
        return counter
    }

    /// Dreimal „+“ schnell hintereinander ist ein Aufruf mit der ganzen Zahl.
    func testQuickTapsBecomeOneAbsoluteCount() async throws {
        StubServer.install { _ in .json(200, "{}") }
        let counter = counter()
        let key = LimitKey(cohabitId: "c-limit", date: today)
        counter.step(key, server: 2, by: 1)
        counter.step(key, server: 2, by: 1)
        counter.step(key, server: 2, by: 1)
        XCTAssertEqual(counter.count(key, server: 2), 5, "sofort zu sehen")
        await counter.settled(key)
        XCTAssertEqual(StubServer.requests.count, 1)
        XCTAssertEqual(StubServer.requests.first?.json?["count"] as? Double, 5)
        XCTAssertEqual(counter.count(key, server: 2), 5, "bis neu geladen ist, gilt die angekommene Zahl")
        XCTAssertEqual(counter.count(key, server: 2, now: Date().addingTimeInterval(60)), 2,
                       "danach wieder der Stand des Dienstes")
    }

    /// Aus „nichts eingetragen“ gibt „−“ eine 0, nie weniger.
    func testTheCountNeverGoesBelowZero() {
        let counter = counter()
        let key = LimitKey(cohabitId: "c-limit", date: today)
        counter.step(key, server: nil, by: -1)
        XCTAssertEqual(counter.count(key, server: nil), 0)
    }

    /// Ohne Netz wartet die Zahl im Postausgang - mit Uhr.
    func testWithoutNetworkTheCountWaits() async {
        StubServer.install { _ in .offline }
        let counter = counter()
        let key = LimitKey(cohabitId: "c-limit", date: today)
        counter.step(key, server: 1, by: 1)
        await counter.settled(key)
        XCTAssertTrue(counter.isWaiting(key))
        XCTAssertEqual(counter.count(key, server: 1), 2)
        let entries = await counter.outbox.entries()
        XCTAssertEqual(entries.count, 1)
    }

    /// Abgelehnt: zurueck auf den Stand des Dienstes.
    func testARejectionGoesBackToTheService() async {
        StubServer.install { _ in .json(409, #"{"message":"Das Co-Habit ist archiviert."}"#) }
        let counter = counter()
        let key = LimitKey(cohabitId: "c-limit", date: today)
        counter.step(key, server: 1, by: 1)
        await counter.settled(key)
        XCTAssertEqual(counter.count(key, server: 1), 1)
        XCTAssertFalse(counter.isWaiting(key))
    }
}
