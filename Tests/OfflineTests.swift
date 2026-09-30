import XCTest
@testable import Healthy

final class OfflineTests: XCTestCase {

    override func setUp() {
        OfflineCache.clear()
    }

    func testStoresAndLoadsPerAddress() {
        let month = URL(string: "https://weight.fherrmann.com/api/weight/month")!
        let year = URL(string: "https://weight.fherrmann.com/api/weight/year")!
        OfflineCache.store(Data("[1]".utf8), for: month)
        OfflineCache.store(Data("[2]".utf8), for: year)
        XCTAssertEqual(OfflineCache.load(for: month)?.data, Data("[1]".utf8))
        XCTAssertEqual(OfflineCache.load(for: year)?.data, Data("[2]".utf8))
        XCTAssertNotNil(OfflineCache.load(for: month)?.fetchedAt)
    }

    func testQueryParametersMakeDifferentEntries() {
        // "30 Tage" und "3 Jahre" laufen ueber denselben Pfad mit anderen
        // Parametern - ein Cache, der die Abfrage ignoriert, zeigte das falsche.
        let a = URL(string: "https://weight.fherrmann.com/api/steps?from=2026-08-01&to=2026-08-31")!
        let b = URL(string: "https://weight.fherrmann.com/api/steps?from=2026-09-01&to=2026-09-30")!
        OfflineCache.store(Data("a".utf8), for: a)
        XCTAssertNil(OfflineCache.load(for: b))
        XCTAssertNotEqual(OfflineCache.file(for: a), OfflineCache.file(for: b))
    }

    func testClearRemovesEverything() {
        let url = URL(string: "https://fherrmann.com/habits/api/focus/sessions")!
        OfflineCache.store(Data("x".utf8), for: url)
        OfflineCache.clear()
        XCTAssertNil(OfflineCache.load(for: url))
    }

    func testOnlyTransportErrorsCountAsOffline() {
        XCTAssertTrue(OfflineCache.isOffline(URLError(.notConnectedToInternet)))
        XCTAssertTrue(OfflineCache.isOffline(URLError(.cannotConnectToHost)))
        XCTAssertTrue(OfflineCache.isOffline(URLError(.timedOut)))
        // Der Dienst hat geantwortet - das ist kein "kein Netz", und den alten
        // Stand darueberzulegen hiesse, ein Problem zu verstecken.
        XCTAssertFalse(OfflineCache.isOffline(APIError.http(500, nil)))
        XCTAssertFalse(OfflineCache.isOffline(APIError.notAuthorised))
        XCTAssertFalse(OfflineCache.isOffline(URLError(.cancelled)))
    }

    /// Ohne Netz kommt der letzte Stand - und die Leiste weiss, wie alt er ist.
    ///
    /// Port 9 auf dem eigenen Rechner: "connection refused" ist fuer
    /// URLSession ein Transportfehler, genau wie fehlendes Netz - und es geht
    /// nichts nach draussen.
    @MainActor
    func testReadFallsBackToTheCacheWithoutNetwork() async throws {
        setenv("COCKPIT_URL_HABITS", "http://127.0.0.1:9/habits", 1)
        defer { unsetenv("COCKPIT_URL_HABITS") }
        let from = CalendarDate(year: 2026, month: 9, day: 1)
        let to = CalendarDate(year: 2026, month: 9, day: 30)
        var components = URLComponents(url: Backend.habits.url.appending(path: "/api/focus/sessions"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "from", value: from.iso), URLQueryItem(name: "to", value: to.iso)]
        OfflineCache.store(Data("""
        [{"id":"a1","start":"2026-09-20T12:00:00Z","end":"2026-09-20T13:30:00Z","minutes":90,"day":"2026-09-20"}]
        """.utf8), for: components.url!)

        let sessions = try await FocusSessionsAPI().sessions(from: from, to: to)
        XCTAssertEqual(sessions.first?.minutes, 90)
        XCTAssertNotNil(OfflineStatus.shared.staleSince[.habits], "die Leiste muss wissen, dass das alt ist")
    }

    @MainActor
    func testWriteWithoutNetworkGoesToTheOutbox() async throws {
        setenv("COCKPIT_URL_HABITS", "http://127.0.0.1:9/habits", 1)
        defer { unsetenv("COCKPIT_URL_HABITS") }
        let before = await Outbox.shared.count
        let start = Date(timeIntervalSince1970: 1_789_000_000)
        do {
            _ = try await FocusSessionsAPI().plant(FocusSessionDraft(id: "t1", start: start,
                                                                     end: start.addingTimeInterval(1_800)))
            XCTFail("ohne Netz darf das nicht durchgehen")
        } catch APIError.queued {
            let after = await Outbox.shared.count
            XCTAssertEqual(after, before + 1)
            XCTAssertEqual(OfflineStatus.shared.pending, after)
        }
        // Nachsenden gegen denselben toten Port: bleibt liegen, geht nicht verloren.
        await Outbox.shared.replay()
        let still = await Outbox.shared.count
        XCTAssertEqual(still, before + 1)
    }
}
