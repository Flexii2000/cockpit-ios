import XCTest
@testable import coHabit

/// Mehrere Beweisfotos je Eintrag (Vertrag §2.3a, seit 2026-10-03): bis zu
/// vier, `photoIds` in Anzeige-Reihenfolge, das erste weiter als `photoId`.
/// Gelesen wird tolerant (ein aelterer Dienst kennt nur `photoId`), der
/// Postausgang laedt alle hoch, bevor der Eintrag rausgeht - und liest seine
/// alten Auftraege mit einem Foto weiter.
@MainActor
final class MultiPhotoTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder().decode(T.self, from: Fixtures.data(json))
    }

    private func object(_ value: some Encodable) throws -> [String: Any] {
        let data = try APIClient.encoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private let day = CalendarDate(year: 2026, month: 10, day: 3)
    private var directory: URL!
    private var outbox: CohabitOutbox!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "outbox-\(UUID().uuidString)")
        outbox = CohabitOutbox(directory: directory)
        CohabitSync.shared.reset()
    }

    override func tearDown() async throws {
        let controller = CheckInController.shared
        controller.makeAPI = { Session.shared.api() }
        controller.outbox = .shared
        controller.clearError()
        CohabitSync.shared.reset()
        try? FileManager.default.removeItem(at: directory)
    }

    /// Der Eintrag aus den Fixtures mit drei Fotos.
    nonisolated static let threePhotos = Fixtures.checkin.replacingOccurrences(
        of: #""editable":true}"#, with: #""editable":true,"photoIds":["p1","p2","p3"]}"#)

    // MARK: - Lesen

    func testCheckinMessageAndTimelineCarryAllPhotos() throws {
        let checkin = try decode(Checkin.self, Self.threePhotos)
        XCTAssertEqual(checkin.photoId, "p1")
        XCTAssertEqual(checkin.photos, ["p1", "p2", "p3"])
        // Ein Dienst ohne `photoIds`: das eine Foto.
        XCTAssertEqual(try decode(Checkin.self, Fixtures.checkin).photos, ["p1"])
        let none = try decode(Checkin.self, Fixtures.checkin.replacingOccurrences(of: #""photoId":"p1""#,
                                                                                 with: #""photoId":null"#))
        XCTAssertEqual(none.photos, [])

        let post = try decode(Message.self, """
            {"id":"m1","cohabitId":"c-3f2a","kind":"CHECKIN","author":\(Fixtures.lena),"mine":false,
             "createdAt":"2026-10-03T07:00:00Z","text":null,"photoId":"p1","checkin":\(Self.threePhotos),
             "systemText":null,"reactionTarget":"event:e1","reactions":[],"deleted":false,
             "photoIds":["p1","p2","p3"]}
            """)
        XCTAssertEqual(post.photos, ["p1", "p2", "p3"])
        // Ohne eigene Fotos am Post: die des Eintrags.
        let older = try decode(Message.self, """
            {"id":"m2","cohabitId":"c-3f2a","kind":"CHECKIN","author":\(Fixtures.lena),"mine":false,
             "createdAt":"2026-10-03T07:00:00Z","text":null,"photoId":null,"checkin":\(Self.threePhotos),
             "systemText":null,"reactionTarget":"event:e1","reactions":[],"deleted":false}
            """)
        XCTAssertEqual(older.photos, ["p1", "p2", "p3"])
        let text = try decode(MessagesPage.self, Fixtures.messages).messages[1]
        XCTAssertEqual(text.photos, [], "eine Textnachricht hat keine Fotos")

        let page = try decode(TimelinePage.self, Fixtures.timeline.replacingOccurrences(
            of: #""canReply":true}"#, with: #""canReply":true,"photoIds":["p1","p9"]}"#))
        XCTAssertEqual(page.items[0].photos, ["p1", "p9"])
        XCTAssertEqual(page.items[1].photos, [], "kompakt ohne Foto")
        XCTAssertEqual(try decode(TimelinePage.self, Fixtures.timeline).items[0].photos, ["p1"])
    }

    // MARK: - Schicken

    func testRequestSendsAllPhotosAndTheFirstOnItsOwn() throws {
        let three = try object(CheckinRequest(id: "k1", date: day, photoIds: ["a", "b", "c"]))
        XCTAssertEqual(three["photoIds"] as? [String], ["a", "b", "c"])
        XCTAssertEqual(three["photoId"] as? String, "a", "das erste versteht auch ein aelterer Dienst")

        let none = try object(CheckinRequest(id: "k2", date: day))
        XCTAssertTrue(none["photoIds"] is NSNull)
        XCTAssertTrue(none["photoId"] is NSNull)

        // Ein Auftrag aus der Fassung mit einem Foto: hochgeladen, also mit `photoId`.
        var old = try decode(CheckinRequest.self,
                             #"{"id":"k3","kind":"DONE","date":"2026-09-30","value":null,"note":null,"photoId":"p-old","caption":null}"#)
        XCTAssertEqual(old.photos, ["p-old"])
        XCTAssertEqual(try object(old)["photoIds"] as? [String], ["p-old"])
        old.appendPhoto("p-new")
        XCTAssertEqual(old.photos, ["p-old", "p-new"], "hinten angehaengt, Reihenfolge bleibt")
        XCTAssertEqual(try object(old)["photoId"] as? String, "p-old")
    }

    func testUpdateSendsNullForUnchangedAndAListForANewSet() throws {
        let unchanged = try object(CheckinUpdate(value: nil, note: "x", caption: nil))
        XCTAssertTrue(unchanged["photoIds"] is NSNull, "null heisst „unveraendert“")
        let none = try object(CheckinUpdate(value: nil, note: nil, caption: nil, photoIds: []))
        XCTAssertEqual(none["photoIds"] as? [String], [], "eine leere Liste nimmt alle weg")
        let two = try object(CheckinUpdate(value: nil, note: nil, caption: nil, photoIds: ["p2", "p1"]))
        XCTAssertEqual(two["photoIds"] as? [String], ["p2", "p1"])
    }

    // MARK: - Postausgang

    /// Jedes Foto mit eigenem Schluessel, der Reihe nach - erst danach der Eintrag.
    func testOutboxUploadsEveryPhotoInOrderBeforeTheEntry() async throws {
        let counter = Counter()
        StubServer.install { request in
            guard request.path.hasSuffix("/photos") else { return .json(201, "{}") }
            return .json(201, #"{"id":"p-\#(counter.next())","width":1,"height":1}"#)
        }
        await outbox.enqueueCheckin(cohabitId: "c1", request: CheckinRequest(id: "k1", date: day),
                                    photos: [Data("a".utf8), Data("b".utf8), Data("c".utf8)])
        await outbox.replay(using: ClassicStoreTests.stubAPI())

        let sent = StubServer.requests
        XCTAssertEqual(sent.map(\.path), ["/cohabit/api/photos", "/cohabit/api/photos", "/cohabit/api/photos",
                                          "/cohabit/api/cohabits/c1/checkins"])
        let keys = sent.prefix(3).compactMap { $0.headers["Idempotency-Key"] }
        XCTAssertEqual(Set(keys).count, 3, "jedes Foto sein eigener Schluessel")
        let bodies = sent.prefix(3).map { String(decoding: $0.body, as: UTF8.self) }
        XCTAssertTrue(bodies[0].contains("\r\n\r\na\r\n") && bodies[2].contains("\r\n\r\nc\r\n"), "in der Reihenfolge des Blatts")
        XCTAssertEqual(sent.last?.json?["photoIds"] as? [String], ["p-1", "p-2", "p-3"])
        XCTAssertEqual(sent.last?.json?["photoId"] as? String, "p-1")
        let left = await outbox.entries()
        XCTAssertTrue(left.isEmpty)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.appending(path: "photos").path())) ?? []
        XCTAssertTrue(files.isEmpty, "keine Fotodatei bleibt liegen")
    }

    /// Bricht das Netz nach dem ersten Foto ab, steht dessen Kennung schon in
    /// der Anfrage - beim naechsten Mal gehen nur die uebrigen hoch.
    func testAnInterruptedUploadContinuesWhereItStopped() async throws {
        let offline = OfflineSwitch()
        let counter = Counter()
        StubServer.install { request in
            guard request.path.hasSuffix("/photos") else { return offline.isOn ? .offline : .json(201, "{}") }
            if counter.value >= 1 && offline.isOn { return .offline }
            return .json(201, #"{"id":"p-\#(counter.next())"}"#)
        }
        offline.isOn = true
        await outbox.enqueueCheckin(cohabitId: "c1", request: CheckinRequest(id: "k1", date: day),
                                    photos: [Data("a".utf8), Data("b".utf8)])
        await outbox.replay(using: ClassicStoreTests.stubAPI())
        let waiting = await outbox.entries()
        XCTAssertEqual(waiting.count, 1)
        XCTAssertEqual(waiting.first?.pendingPhotos.count, 1, "das erste ist oben")
        guard case .checkin(_, let request) = waiting.first?.operation else { return XCTFail("kein Eintrag") }
        XCTAssertEqual(request.photos, ["p-1"])

        offline.isOn = false
        await outbox.replay(using: ClassicStoreTests.stubAPI())
        let uploads = StubServer.requests.filter { $0.path.hasSuffix("/photos") }
        XCTAssertEqual(uploads.count, 3, "erstes, zweites (ohne Netz), zweites noch einmal")
        XCTAssertEqual(uploads[1].headers["Idempotency-Key"], uploads[2].headers["Idempotency-Key"])
        XCTAssertEqual(StubServer.requests.last?.json?["photoIds"] as? [String], ["p-1", "p-2"])
        let left = await outbox.entries()
        XCTAssertTrue(left.isEmpty)
    }

    /// Ein Auftrag aus der Fassung mit einem Foto (`photoFile`, kein
    /// `photoFiles`) muss weiter rausgehen - sonst verwuerfe der Postausgang alles.
    func testAnOldEntryWithOnePhotoFileStillGoesOut() async throws {
        await outbox.enqueueCheckin(cohabitId: "c1", request: CheckinRequest(id: "k1", date: day),
                                    photos: [Data("a".utf8)])
        // Auf der Platte in die alte Form bringen.
        let file = directory.appending(path: "outbox.json")
        var entries = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [[String: Any]])
        let name = try XCTUnwrap((entries[0]["photoFiles"] as? [String])?.first)
        entries[0]["photoFile"] = name
        entries[0].removeValue(forKey: "photoFiles")
        try JSONSerialization.data(withJSONObject: entries).write(to: file)

        let again = CohabitOutbox(directory: directory)
        let read = await again.entries()
        XCTAssertEqual(read.first?.pendingPhotos, [name])

        StubServer.install { request in
            request.path.hasSuffix("/photos") ? .json(201, #"{"id":"p-9"}"#) : .json(201, "{}")
        }
        await again.replay(using: ClassicStoreTests.stubAPI())
        XCTAssertEqual(StubServer.requests.first?.headers["Idempotency-Key"], (name as NSString).deletingPathExtension)
        XCTAssertEqual(StubServer.requests.last?.json?["photoIds"] as? [String], ["p-9"])
        let left = await again.entries()
        XCTAssertTrue(left.isEmpty)
    }

    // MARK: - Blatt und Bearbeiten

    /// Das Blatt schickt alle Fotos der Reihe nach, der Eintrag traegt sie in
    /// dieser Reihenfolge.
    func testSubmittingSendsAllPhotosInOrder() async throws {
        let counter = Counter()
        StubServer.install { request in
            if request.path.hasSuffix("/photos") { return .json(201, #"{"id":"p-\#(counter.next())"}"#) }
            // Abgelehnt, damit der Test nicht die Kachel neu laedt (Netz).
            return .json(400, #"{"message":"Außerhalb der Nachtragsfrist."}"#)
        }
        let controller = CheckInController.shared
        controller.makeAPI = { ClassicStoreTests.stubAPI() }
        controller.outbox = outbox
        let summary = try decode(CohabitSummary.self, Fixtures.summary)
        let images = [ProofPhotoPicker.testImage(0), ProofPhotoPicker.testImage(1), ProofPhotoPicker.testImage(2)]
        let ok = await controller.submit(CheckInTarget(summary: summary, meId: "felix"),
                                         request: CheckinRequest(id: "k1", date: day), photos: images)
        XCTAssertFalse(ok)
        XCTAssertEqual(controller.lastError, "Außerhalb der Nachtragsfrist.")
        let post = try XCTUnwrap(StubServer.requests.last)
        XCTAssertEqual(post.path, "/cohabit/api/cohabits/c-3f2a/checkins")
        XCTAssertEqual(post.json?["photoIds"] as? [String], ["p-1", "p-2", "p-3"])
        let waiting = await outbox.entries()
        XCTAssertTrue(waiting.isEmpty)
    }

    /// Bearbeiten: neue Fotos gehen vorher hoch, der neue Satz in der
    /// Reihenfolge des Blatts; unveraendert heisst `null`.
    func testEditingUploadsNewPhotosAndSendsTheNewSet() async throws {
        let result = #"{"checkin":\#(Self.threePhotos),"cohabit":\#(Fixtures.streakDetail)}"#
        StubServer.install { request in
            request.path.hasSuffix("/photos") ? .json(201, #"{"id":"p-new"}"#) : .json(200, result)
        }
        let store = CohabitDetailStore(cohabitId: "c-3f2a", makeAPI: { ClassicStoreTests.stubAPI() })
        let checkin = try decode(Checkin.self, Self.threePhotos)

        let changed = await store.update(checkin, CheckinUpdate(value: nil, note: nil, caption: "Regen"),
                                         photos: [.remote("p3"), ProofPhoto(ProofPhotoPicker.testImage(0)), .remote("p1")])
        XCTAssertTrue(changed)
        XCTAssertEqual(StubServer.requests.map(\.method), ["POST", "PUT"])
        let put = try XCTUnwrap(StubServer.requests.last)
        XCTAssertEqual(put.path, "/cohabit/api/cohabits/c-3f2a/checkins/k1")
        XCTAssertEqual(put.json?["photoIds"] as? [String], ["p3", "p-new", "p1"], "p2 entfernt, das neue dazwischen")

        StubServer.install { _ in .json(200, result) }
        _ = await store.update(checkin, CheckinUpdate(value: nil, note: "x", caption: nil))
        XCTAssertEqual(StubServer.requests.map(\.method), ["PUT"], "nichts hochzuladen")
        XCTAssertTrue(StubServer.requests.last?.json?["photoIds"] is NSNull)
    }
}

/// Zaehlt hoch - fuer Kennungen, die der Stub-Dienst der Reihe nach vergibt.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        current += 1
        return current
    }
}
