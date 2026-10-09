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

    /// Weckt HealthKit die App bei gesperrtem iPhone, ist die Datei des
    /// Postausgangs nicht lesbar. Frueher hiess das „leer" - und der naechste
    /// Eintrag ueberschrieb, was dort wartete. Ein Verzeichnis an ihrer Stelle
    /// ist im Test dasselbe: da, aber nicht zu lesen.
    @MainActor
    func testUnreadableOutboxIsNeitherOverwrittenNorForgotten() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "outbox.json")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)

        let outbox = Outbox(file: file)
        let count = await outbox.count
        XCTAssertEqual(count, 0, "nichts zu lesen - aber auch nichts gelesen")
        var request = URLRequest(url: URL(string: "https://weight.fherrmann.com/api/weight")!)
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"date":"2026-10-09","weightKg":82.4}"#.utf8)
        await outbox.enqueue(request, backend: .weight)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue, "eine ungelesene Datei wird nicht ueberschrieben")

        // Entsperrt: die wartenden Eintraege aus der Datei kommen zuerst, der
        // neue haengt hinten an, und erst jetzt wird gespeichert.
        try FileManager.default.removeItem(at: file)
        let waiting = Outbox.Item(id: UUID(), backend: Backend.food.rawValue,
                                  url: "https://food.fherrmann.com/api/food/entries", method: "POST",
                                  body: Data("{}".utf8), createdAt: Date(timeIntervalSince1970: 1_790_000_000))
        try JSONEncoder().encode([waiting]).write(to: file)
        let merged = await outbox.count
        XCTAssertEqual(merged, 2)
        let stored = try JSONDecoder().decode([Outbox.Item].self, from: Data(contentsOf: file))
        XCTAssertEqual(stored.map(\.backend), ["food", "weight"])
    }

    // MARK: - Ueberholte PUTs

    private func request(_ method: String, _ path: String, body: String? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://weight.fherrmann.com" + path)!)
        request.httpMethod = method
        request.httpBody = body.map { Data($0.utf8) }
        return request
    }

    private func stored(_ file: URL) throws -> [Outbox.Item] {
        try JSONDecoder().decode([Outbox.Item].self, from: Data(contentsOf: file))
    }

    /// Ein Logbook-Tag zweimal offline gespeichert: nur der neuere wartet. Ein
    /// PUT ersetzt beim Dienst den ganzen Stand der Adresse - der aeltere,
    /// nachgesendet, ueberschriebe den neueren. POST und DELETE bleiben.
    @MainActor
    func testNewerPutReplacesTheWaitingOne() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "outbox.json")
        let outbox = Outbox(file: file)

        await outbox.enqueue(request("PUT", "/api/logbook/days/2026-10-08", body: "alt"), backend: .weight)
        await outbox.enqueue(request("POST", "/api/weight", body: "a"), backend: .weight)
        await outbox.enqueue(request("POST", "/api/weight", body: "b"), backend: .weight)
        await outbox.enqueue(request("PUT", "/api/logbook/days/2026-10-07", body: "anderer Tag"), backend: .weight)
        await outbox.enqueue(request("PUT", "/api/logbook/days/2026-10-08", body: "neu"), backend: .weight)

        let items = try stored(file)
        XCTAssertEqual(items.map(\.method), ["POST", "POST", "PUT", "PUT"])
        XCTAssertEqual(items.compactMap { $0.body.map { String(decoding: $0, as: UTF8.self) } },
                       ["a", "b", "anderer Tag", "neu"], "zwei POSTs bleiben beide, der alte PUT faellt weg")
    }

    /// Kam ein PUT mit Netz an, ist der wartende an dieselbe Adresse ueberholt -
    /// nur der, nichts sonst.
    @MainActor
    func testDeliveredPutDiscardsOnlyWaitingPutsToTheSameAddress() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "outbox.json")
        let outbox = Outbox(file: file)

        await outbox.enqueue(request("PUT", "/api/logbook/days/2026-10-08", body: "alt"), backend: .weight)
        await outbox.enqueue(request("PUT", "/api/logbook/days/2026-10-07", body: "anderer Tag"), backend: .weight)
        await outbox.enqueue(request("DELETE", "/api/logbook/days/2026-10-08"), backend: .weight)
        await outbox.discardPuts(to: URL(string: "https://weight.fherrmann.com/api/logbook/days/2026-10-08")!)

        let items = try stored(file)
        XCTAssertEqual(items.map(\.method), ["PUT", "DELETE"])
        XCTAssertEqual(items.first?.url, "https://weight.fherrmann.com/api/logbook/days/2026-10-07")
        let count = await outbox.count
        XCTAssertEqual(count, 2)
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
