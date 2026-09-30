import XCTest
@testable import coHabit

/// Der Client gegen einen Dienst im Speicher: Bearer, Fehlermeldungen, der
/// letzte Stand ohne Netz, das Hochladen von Fotos.
@MainActor
final class CohabitAPITests: XCTestCase {

    override func setUp() async throws {
        OfflineCache.clear()
    }

    func testSendsTheTokenAsBearerAndNoCookies() async throws {
        StubServer.install { _ in .json(200, Fixtures.me) }
        let me: MeView = try await StubServer.api().get("/me")
        XCTAssertEqual(me.person.id, "felix")
        let request = try XCTUnwrap(StubServer.requests.first)
        XCTAssertEqual(request.headers["Authorization"], "Bearer test-token")
        XCTAssertNil(request.headers["Cookie"])
        XCTAssertEqual(request.path, "/cohabit/api/me")
    }

    func testUnauthorizedAndMessages() async {
        StubServer.install { request in
            switch request.path {
            case "/cohabit/api/me": .json(401, #"{"message":"Nicht angemeldet."}"#)
            case "/cohabit/api/forbidden": .json(403, #"{"message":"Nur der Admin darf das."}"#)
            case "/cohabit/api/html": .json(502, "<html><body>Bad Gateway</body></html>")
            default: .json(429, "")
            }
        }
        let api = StubServer.api()
        await assertThrows(CohabitError.unauthorized) { let _: MeView = try await api.get("/me") }
        await assertThrows(.server(status: 403, message: "Nur der Admin darf das.")) {
            let _: MeView = try await api.get("/forbidden")
        }
        await assertThrows(.server(status: 502, message: "Der Dienst hat mit 502 geantwortet.")) {
            let _: MeView = try await api.get("/html")
        }
        await assertThrows(.server(status: 429, message: "Zu oft – später noch einmal.")) {
            let _: MeView = try await api.get("/nudge")
        }
    }

    func testReadingWithoutNetworkShowsTheLastStandWithItsDate() async throws {
        let offline = OfflineSwitch()
        StubServer.install { _ in offline.isOn ? .offline : .json(200, Fixtures.today) }
        let api = StubServer.api(usesCache: true)
        let fresh: Today = try await api.get("/today")
        XCTAssertNil(CohabitSync.shared.staleSince)
        offline.isOn = true
        let cached: Today = try await api.get("/today")
        XCTAssertEqual(cached, fresh)
        XCTAssertNotNil(CohabitSync.shared.staleSince, "die Leiste muss wissen, dass das alt ist")
        offline.isOn = false
        let _: Today = try await api.get("/today")
        XCTAssertNil(CohabitSync.shared.staleSince)
    }

    func testWritingWithoutNetworkThrowsOffline() async {
        StubServer.install { _ in .offline }
        await assertThrows(.offline) {
            try await StubServer.api().sendIgnoringResponse("POST", "/cohabits/c1/checkins", body: CheckinRequest())
        }
    }

    func testUploadIsMultipartWithIdempotencyKey() async throws {
        StubServer.install { _ in .json(201, #"{"id":"p-1","width":2048,"height":1536}"#) }
        let upload = try await StubServer.api().uploadPhoto(jpeg: Data([0xFF, 0xD8, 0xFF]), key: "key-1")
        XCTAssertEqual(upload.id, "p-1")
        let request = try XCTUnwrap(StubServer.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/cohabit/api/photos")
        XCTAssertEqual(request.headers["Idempotency-Key"], "key-1")
        XCTAssertTrue(request.headers["Content-Type"]?.hasPrefix("multipart/form-data; boundary=") ?? false)
        let body = String(decoding: request.body, as: UTF8.self)
        XCTAssertTrue(body.contains(#"Content-Disposition: form-data; name="photo"; filename="photo.jpg""#))
        XCTAssertTrue(body.contains("Content-Type: image/jpeg"))
    }

    func testNoContentAnswersAreFine() async throws {
        StubServer.install { _ in .json(204, "") }
        try await StubServer.api().sendIgnoringResponse("DELETE", "/me/app-links/current")
        let empty: CohabitAPI.Empty = try await StubServer.api().delete("/friends/lena")
        _ = empty
        XCTAssertEqual(StubServer.requests.map(\.method), ["DELETE", "DELETE"])
    }

    private func assertThrows(_ expected: CohabitError, _ body: () async throws -> Void,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("erwartet: \(expected)", file: file, line: line)
        } catch let error as CohabitError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unerwartet: \(error)", file: file, line: line)
        }
    }
}

/// Ein Schalter, den der Stub-Handler aus einem anderen Thread liest.
final class OfflineSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isOn: Bool {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}

/// Der Postausgang: Foto vor dem Eintrag, derselbe Schluessel bei jedem
/// Versuch, Ablehnungen fliegen raus, Konflikte beim Haken sind das Ziel.
@MainActor
final class OutboxTests: XCTestCase {

    private var directory: URL!
    private var outbox: CohabitOutbox!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)")
        outbox = CohabitOutbox(directory: directory)
        CohabitSync.shared.reset()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        CohabitSync.shared.reset()
    }

    private let day = CalendarDate(year: 2026, month: 9, day: 30)

    func testPhotoGoesUpFirstAndItsIdLandsInTheCheckin() async throws {
        StubServer.install { request in
            request.path.hasSuffix("/photos") ? .json(201, #"{"id":"p-9","width":1,"height":1}"#) : .json(201, "{}")
        }
        await outbox.enqueueCheckin(cohabitId: "c1", request: CheckinRequest(id: "k1", date: day, caption: "Regen"),
                                    photo: Data("jpeg".utf8))
        XCTAssertEqual(CohabitSync.shared.pendingCheckins, ["c1"], "der Knopf zeigt eine Uhr")
        await outbox.replay(using: StubServer.api())

        XCTAssertEqual(StubServer.requests.map(\.path), ["/cohabit/api/photos", "/cohabit/api/cohabits/c1/checkins"])
        let checkin = try XCTUnwrap(StubServer.requests.last?.json)
        XCTAssertEqual(checkin["id"] as? String, "k1")
        XCTAssertEqual(checkin["photoId"] as? String, "p-9")
        XCTAssertEqual(checkin["date"] as? String, "2026-09-30")
        XCTAssertEqual(checkin["caption"] as? String, "Regen")
        let left = await outbox.entries()
        XCTAssertTrue(left.isEmpty)
        XCTAssertEqual(CohabitSync.shared.pending, 0)
        let photos = (try? FileManager.default.contentsOfDirectory(atPath: directory.appending(path: "photos").path())) ?? []
        XCTAssertTrue(photos.isEmpty, "das Foto liegt nicht mehr herum")
    }

    func testTheSameIdempotencyKeyOnEveryAttempt() async throws {
        let offline = OfflineSwitch()
        offline.isOn = true
        StubServer.install { request in
            if offline.isOn { return .offline }
            return request.path.hasSuffix("/photos") ? .json(201, #"{"id":"p-1"}"#) : .json(201, "{}")
        }
        await outbox.enqueueCheckin(cohabitId: "c1", request: CheckinRequest(id: "k1", date: day), photo: Data([1, 2, 3]))
        await outbox.replay(using: StubServer.api())
        let stillThere = await outbox.entries()
        XCTAssertEqual(stillThere.count, 1, "ohne Netz bleibt es liegen")
        offline.isOn = false
        await outbox.replay(using: StubServer.api())
        let keys = StubServer.requests.filter { $0.path.hasSuffix("/photos") }.compactMap { $0.headers["Idempotency-Key"] }
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(Set(keys).count, 1, "sonst entstuende das Foto zweimal")
    }

    func testRejectedChangesAreDroppedWithTheReason() async {
        StubServer.install { _ in .json(400, #"{"message":"Außerhalb der Nachtragsfrist."}"#) }
        await outbox.enqueueCheckin(cohabitId: "c1", request: CheckinRequest(date: day), photo: nil)
        await outbox.replay(using: StubServer.api())
        let left = await outbox.entries()
        XCTAssertTrue(left.isEmpty)
        XCTAssertEqual(CohabitSync.shared.lastError, "Nicht angenommen: Außerhalb der Nachtragsfrist.")
    }

    func testConflictOnACheckinMeansAlreadyDone() async {
        StubServer.install { _ in .json(409, #"{"message":"Heute schon erledigt."}"#) }
        await outbox.enqueueCheckin(cohabitId: "c1", request: CheckinRequest(date: day), photo: nil)
        await outbox.replay(using: StubServer.api())
        let left = await outbox.entries()
        XCTAssertTrue(left.isEmpty)
        XCTAssertNil(CohabitSync.shared.lastError)
    }

    func testServerTroubleAndRevokedTokensKeepEverything() async {
        StubServer.install { _ in .json(503, "") }
        await outbox.enqueueMessage(cohabitId: "c1", request: MessageRequest(id: "m1", text: "Hallo"), photo: nil)
        await outbox.enqueueCheckin(cohabitId: "c1", request: CheckinRequest(date: day), photo: nil)
        await outbox.replay(using: StubServer.api())
        var left = await outbox.entries()
        XCTAssertEqual(left.count, 2)
        XCTAssertEqual(StubServer.requests.count, 1, "nach dem ersten 5xx wird nicht weitergemacht")

        StubServer.install { _ in .json(401, "") }
        await outbox.replay(using: StubServer.api())
        left = await outbox.entries()
        XCTAssertEqual(left.count, 2)
        XCTAssertEqual(CohabitSync.shared.pendingMessages["c1"]?.first?.text, "Hallo")
    }

    func testMessagesAndReactionsGoOutInOrder() async throws {
        StubServer.install { request in request.method == "DELETE" ? .json(200, #"{"reactions":[]}"#) : .json(201, "{}") }
        await outbox.enqueueMessage(cohabitId: "c1", request: MessageRequest(id: "m1", text: "Bin dabei!"), photo: nil)
        await outbox.enqueueReaction(ReactionRequest(target: "event:e1", reaction: .stark), add: true)
        await outbox.enqueueReaction(ReactionRequest(target: "message:m9", reaction: .haha), add: false)
        await outbox.replay(using: StubServer.api())
        XCTAssertEqual(StubServer.requests.map(\.method), ["POST", "POST", "DELETE"])
        XCTAssertEqual(StubServer.requests[0].json?["text"] as? String, "Bin dabei!")
        XCTAssertEqual(StubServer.requests[1].json?["reaction"] as? String, "STARK")
        let query = URLComponents(url: StubServer.requests[2].url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "target" }?.value, "message:m9")
        XCTAssertEqual(query.first { $0.name == "reaction" }?.value, "HAHA")
    }

    func testTappingTwiceOfflineCancelsOut() async {
        let reaction = ReactionRequest(target: "event:e1", reaction: .respekt)
        await outbox.enqueueReaction(reaction, add: true)
        await outbox.enqueueReaction(reaction, add: false)
        let left = await outbox.entries()
        XCTAssertTrue(left.isEmpty)
    }

    func testSurvivesARestart() async {
        await outbox.enqueueCheckin(cohabitId: "c2", request: CheckinRequest(id: "k7", date: day), photo: nil)
        let again = CohabitOutbox(directory: directory)
        let entries = await again.entries()
        XCTAssertEqual(entries.count, 1)
        if case .checkin(let cohabitId, let request) = entries.first?.operation {
            XCTAssertEqual(cohabitId, "c2")
            XCTAssertEqual(request.id, "k7")
        } else {
            XCTFail("falsche Art")
        }
    }
}
