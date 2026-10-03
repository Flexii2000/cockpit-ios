import XCTest
@testable import coHabit

/// Laufpunkte (Vertrag §2.6a, seit 2026-10-03): eine Challenge-Wertung aus
/// Dauer und Distanz je Lauf. Gerechnet wird im Dienst - hier geht es um die
/// Formen: was die App liest (tolerant, auch ohne die neuen Felder), was sie
/// schickt, und dass eine Ablehnung (Pace) sichtbar bleibt.
@MainActor
final class RunPointsTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder().decode(T.self, from: Fixtures.data(json))
    }

    private func object(_ value: some Encodable) throws -> [String: Any] {
        let data = try APIClient.encoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Fixtures

    nonisolated static let runRef = #"{"id":"c-run","name":"Laufen","color":"butter","type":"CHALLENGE"}"#

    /// Die Zusammenfassung aus den Fixtures als Lauf-Challenge (mit Foto-Pflicht).
    nonisolated static let runSummary = Fixtures.summary
        .replacingOccurrences(of: Fixtures.ref, with: runRef)
        .replacingOccurrences(of: #""checkInLabel":"Beweisfoto & abhaken","#,
                              with: #""checkInLabel":"Lauf eintragen","runEntry":true,"#)

    nonisolated static let run = """
    {"durationMinutes":35,"distanceKm":5.8,"paceText":"6:02 min/km","points":20,
     "pointsText":"+20 P","breakdownText":"Basis 10 · Distanz 5 · Dauer 5"}
    """

    nonisolated static let runCheckin = Fixtures.checkin
        .replacingOccurrences(of: #""valueText":null"#, with: #""valueText":"5,8 km · 35 Min. · 6:02 min/km · +20 P""#)
        .replacingOccurrences(of: #""editable":true}"#, with: #""editable":true,"run":\#(run)}"#)

    /// Das Detail aus den Fixtures mit der Lauf-Zusammenfassung.
    nonisolated static let runDetail = Fixtures.streakDetail
        .replacingOccurrences(of: Fixtures.ref, with: runRef)
        .replacingOccurrences(of: #""checkInLabel":"Beweisfoto & abhaken","#,
                              with: #""checkInLabel":"Lauf eintragen","runEntry":true,"#)

    nonisolated static func runConfig(_ run: String) -> String {
        """
        {"type":"CHALLENGE","name":"Laufen","color":"butter","timezone":"Europe/Berlin",
         "tracking":{"mode":"CHECK"},"photoRequired":true,"backfillHours":48,"reminderTime":null,
         "membersCanInvite":false,"streak":null,"abstinence":null,"goal":null,
         "challenge":{"start":"2026-10-01","end":"2026-10-31","scoring":"RUN_POINTS","target":null,
                      "stake":null,"recurrence":"NONE","run":\(run)},
         "health":null,"auto":null}
        """
    }

    nonisolated static let paceMessage = "Ø-Pace 8:30 min/km – zählt nur unter 8:00 min/km."

    private let day = CalendarDate(year: 2026, month: 10, day: 3)
    /// Ein eigener Postausgang je Test - der der App liegt in der App-Gruppe.
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

    // MARK: - Lesen

    func testSummaryKnowsTheRunEntryAndOlderServicesDoNot() throws {
        let summary = try decode(CohabitSummary.self, Self.runSummary)
        XCTAssertTrue(summary.isRunEntry)
        XCTAssertEqual(summary.checkInLabel, "Lauf eintragen")
        XCTAssertNil(summary.valueUnit)
        // Ein Dienst ohne das Feld: kein Lauf, und nichts kippt.
        let old = try decode(CohabitSummary.self, Fixtures.summary)
        XCTAssertNil(old.runEntry)
        XCTAssertFalse(old.isRunEntry)
    }

    func testCheckinCarriesTheRunWithItsPoints() throws {
        let checkin = try decode(Checkin.self, Self.runCheckin)
        let run = try XCTUnwrap(checkin.run)
        XCTAssertEqual(run.durationMinutes, 35)
        XCTAssertEqual(run.distanceKm, 5.8)
        XCTAssertEqual(run.paceText, "6:02 min/km")
        XCTAssertEqual(run.points, 20)
        XCTAssertEqual(run.pointsText, "+20 P")
        XCTAssertEqual(run.breakdownText, "Basis 10 · Distanz 5 · Dauer 5")
        XCTAssertEqual(checkin.valueText, "5,8 km · 35 Min. · 6:02 min/km · +20 P")

        XCTAssertNil(try decode(Checkin.self, Fixtures.checkin).run, "ohne das Feld kein Lauf")
        let sparse = try decode(Checkin.self, Fixtures.checkin.replacingOccurrences(
            of: #""editable":true}"#, with: #""editable":true,"run":{"pointsText":"+3 P"}}"#))
        XCTAssertEqual(sparse.run?.pointsText, "+3 P", "ein unvollstaendiger Lauf macht den Eintrag nicht unlesbar")
        XCTAssertNil(sparse.run?.durationMinutes)

        // Antwort auf POST/PUT, und ein Lauf im Chat.
        let result = try decode(CheckinResult.self, #"{"checkin":\#(Self.runCheckin),"cohabit":\#(Self.runDetail)}"#)
        XCTAssertEqual(result.checkin.run?.pointsText, "+20 P")
        XCTAssertTrue(result.cohabit.summary.isRunEntry)
        let message = try decode(Message.self, """
            {"id":"m1","cohabitId":"c-run","kind":"CHECKIN","author":\(Fixtures.lena),"mine":false,
             "createdAt":"2026-10-03T07:00:00Z","text":null,"photoId":"p1","checkin":\(Self.runCheckin),
             "systemText":null,"reactionTarget":"event:e1","reactions":[],"deleted":false}
            """)
        XCTAssertEqual(message.checkin?.valueText, "5,8 km · 35 Min. · 6:02 min/km · +20 P")
    }

    func testConfigReadsTheRunAndFillsMissingFieldsWithTheDefaults() throws {
        let full = try decode(CohabitConfig.self, Self.runConfig(
            #"{"basePoints":15,"pointsPerKm":2,"minutesPerPoint":5,"baseMinMinutes":25,"paceLimitSeconds":450}"#))
        XCTAssertTrue(full.challenge?.isRunPoints ?? false)
        XCTAssertEqual(full.challenge?.run, RunScoring(basePoints: 15, pointsPerKm: 2, minutesPerPoint: 5,
                                                       baseMinMinutes: 25, paceLimitSeconds: 450))

        let partial = try decode(CohabitConfig.self, Self.runConfig(#"{"basePoints":5}"#))
        XCTAssertEqual(partial.challenge?.run, RunScoring(basePoints: 5, pointsPerKm: 1, minutesPerPoint: 6,
                                                          baseMinMinutes: 20, paceLimitSeconds: 480))

        let missing = try decode(CohabitConfig.self, Self.runConfig("null"))
        XCTAssertNil(missing.challenge?.run)
        XCTAssertTrue(missing.challenge?.isRunPoints ?? false)

        // Die Wertung im Detail-Block bleibt Text - auch eine unbekannte.
        let block = try decode(ChallengeBlock.self, Fixtures.challenge
            .replacingOccurrences(of: #""scoring":"MOST_ENTRIES","scoringText":"Meiste Einträge""#,
                                  with: #""scoring":"RUN_POINTS","scoringText":"Laufpunkte""#))
        XCTAssertEqual(block.scoring, ChallengeScoring.runPoints)
        XCTAssertEqual(block.scoringText, "Laufpunkte")
        let future = try decode(CohabitConfig.self, Self.runConfig("null")
            .replacingOccurrences(of: "RUN_POINTS", with: "FASTEST_LAP"))
        XCTAssertEqual(future.challenge?.scoring, "FASTEST_LAP", "geht beim Sichern unveraendert zurueck")
    }

    // MARK: - Schicken

    func testChallengeSendsTheRunOnlyForRunPoints() throws {
        var config = CohabitConfig.draft(.challenge, today: CalendarDate(year: 2026, month: 10, day: 1))
        config.name = "Laufen"
        config.challenge?.scoring = ChallengeScoring.runPoints
        var challenge = try XCTUnwrap(try object(config)["challenge"] as? [String: Any])
        let defaults = try XCTUnwrap(challenge["run"] as? [String: Any], "ohne eigene Werte die Vorgaben")
        XCTAssertEqual(defaults["basePoints"] as? Int, 10)
        XCTAssertEqual(defaults["pointsPerKm"] as? Int, 1)
        XCTAssertEqual(defaults["minutesPerPoint"] as? Int, 6)
        XCTAssertEqual(defaults["baseMinMinutes"] as? Int, 20)
        XCTAssertEqual(defaults["paceLimitSeconds"] as? Int, 480)
        XCTAssertTrue(challenge["target"] is NSNull)

        config.challenge?.run = RunScoring(basePoints: 0, pointsPerKm: 2, minutesPerPoint: 5,
                                           baseMinMinutes: 30, paceLimitSeconds: 450)
        challenge = try XCTUnwrap(try object(UpdateCohabitRequest(config: config))["challenge"] as? [String: Any])
        let run = try XCTUnwrap(challenge["run"] as? [String: Any])
        XCTAssertEqual(run["basePoints"] as? Int, 0)
        XCTAssertEqual(run["paceLimitSeconds"] as? Int, 450)

        config.challenge?.scoring = ChallengeScoring.mostEntries
        challenge = try XCTUnwrap(try object(config)["challenge"] as? [String: Any])
        XCTAssertTrue(challenge["run"] is NSNull, "bei jeder anderen Wertung null")
    }

    func testCheckinRequestAndUpdateSendDurationAndDistance() throws {
        let run = try object(CheckinRequest(id: "r1", date: day, caption: "Regen",
                                            durationMinutes: 35, distanceKm: 5.8))
        XCTAssertEqual(run["durationMinutes"] as? Int, 35)
        XCTAssertEqual(run["distanceKm"] as? Double, 5.8)
        XCTAssertTrue(run["value"] is NSNull)
        XCTAssertEqual(run["caption"] as? String, "Regen")

        let plain = try object(CheckinRequest(id: "r2", date: day))
        XCTAssertTrue(plain["durationMinutes"] is NSNull)
        XCTAssertTrue(plain["distanceKm"] is NSNull)

        let update = try object(CheckinUpdate(value: nil, note: nil, caption: nil, durationMinutes: 40, distanceKm: 7.25))
        XCTAssertEqual(update["durationMinutes"] as? Int, 40)
        XCTAssertEqual(update["distanceKm"] as? Double, 7.25)
        let unchanged = try object(CheckinUpdate(value: 3, note: "x", caption: nil))
        XCTAssertTrue(unchanged["durationMinutes"] is NSNull, "null heisst beim Bearbeiten „unveraendert“")
        XCTAssertTrue(unchanged["distanceKm"] is NSNull)
    }

    /// Der Postausgang liegt auf der Platte - ein Auftrag aus der Fassung vor
    /// den Laeufen muss weiter lesbar sein, sonst verwirft er alle.
    func testOldOutboxRequestsStillDecode() throws {
        let old = try decode(CheckinRequest.self,
                             #"{"id":"k1","kind":"DONE","date":"2026-09-30","value":null,"note":null,"photoId":null,"caption":null}"#)
        XCTAssertEqual(old.id, "k1")
        XCTAssertNil(old.durationMinutes)
        XCTAssertNil(old.distanceKm)
        XCTAssertNil(old.runText)
    }

    // MARK: - Eintragen

    /// Von ueberall dasselbe Blatt: Karte, Detailseite, klassische Liste - auch
    /// bei Foto-Pflicht (das Foto steckt im Lauf-Blatt).
    func testRunEntryOpensTheRunSheetEverywhere() throws {
        let summary = try decode(CohabitSummary.self, Self.runSummary)
        XCTAssertTrue(summary.photoRequired)
        let fromCard = CheckInTarget(summary: summary, meId: "felix")
        XCTAssertEqual(CheckInController.step(for: fromCard), .run)
        XCTAssertEqual(fromCard.label, "Lauf eintragen")

        let detail = try decode(CohabitDetail.self, Self.runDetail)
        XCTAssertEqual(CheckInController.step(for: CheckInTarget(detail: detail, meId: "felix")), .run)

        let classic = try APIClient.decoder().decode([ClassicHabit].self, from: Fixtures.data(
            "[" + ClassicGoalChallengeTests.habitJSON(id: "c-run", kind: "CHALLENGE", summary: Self.runSummary,
                                                      doneToday: false) + "]"))
        XCTAssertEqual(classic.first?.action, .checkIn)
        let classicSummary = try XCTUnwrap(classic.first?.summary)
        XCTAssertEqual(CheckInController.step(for: CheckInTarget(summary: classicSummary, meId: "felix")), .run)

        // Ohne `runEntry` bleibt alles wie bisher.
        let plain = try decode(CohabitSummary.self, Fixtures.summary)
        XCTAssertEqual(CheckInController.step(for: CheckInTarget(summary: plain, meId: "felix")), .photo)
    }

    func testRunInputs() {
        XCTAssertEqual(RunEntrySheet.minutes("35"), 35)
        XCTAssertEqual(RunEntrySheet.minutes(" 120 "), 120)
        XCTAssertNil(RunEntrySheet.minutes("0"))
        XCTAssertNil(RunEntrySheet.minutes("3,5"), "ganze Minuten")
        XCTAssertNil(RunEntrySheet.minutes(""))
        XCTAssertEqual(RunEntrySheet.distance("5,8"), 5.8)
        XCTAssertEqual(RunEntrySheet.distance("5.8"), 5.8)
        XCTAssertEqual(RunEntrySheet.distance("10"), 10)
        XCTAssertNil(RunEntrySheet.distance("0"))
        XCTAssertNil(RunEntrySheet.distance("abc"))
    }

    // MARK: - Formular

    func testPaceLimitIsTypedAsMinutesAndSeconds() {
        XCTAssertEqual(CohabitSettingsForm.paceSeconds("8:00"), 480)
        XCTAssertEqual(CohabitSettingsForm.paceSeconds("7:30"), 450)
        XCTAssertEqual(CohabitSettingsForm.paceSeconds(" 6:05 "), 365)
        XCTAssertEqual(CohabitSettingsForm.paceSeconds("8"), 480)
        XCTAssertEqual(CohabitSettingsForm.paceSeconds("60:00"), 3600)
        XCTAssertNil(CohabitSettingsForm.paceSeconds("8:5"), "Sekunden zweistellig")
        XCTAssertNil(CohabitSettingsForm.paceSeconds("8:60"))
        XCTAssertNil(CohabitSettingsForm.paceSeconds("8:"))
        XCTAssertNil(CohabitSettingsForm.paceSeconds(""))
        XCTAssertNil(CohabitSettingsForm.paceSeconds("a:00"))
        XCTAssertNil(CohabitSettingsForm.paceSeconds("1:00:00"))
        XCTAssertEqual(CohabitSettingsForm.paceText(480), "8:00")
        XCTAssertEqual(CohabitSettingsForm.paceText(365), "6:05")
        XCTAssertEqual(CohabitSettingsForm.paceText(3600), "60:00")
        XCTAssertEqual(CohabitSettingsForm.wholeNumber("10"), 10)
        XCTAssertEqual(CohabitSettingsForm.wholeNumber("0"), 0)
        XCTAssertNil(CohabitSettingsForm.wholeNumber("-1"))
        XCTAssertNil(CohabitSettingsForm.wholeNumber(""))
    }

    func testSettingsValidationForRunPoints() {
        var config = CohabitConfig.draft(.challenge)
        config.name = "Laufen"
        config.challenge?.scoring = ChallengeScoring.runPoints
        XCTAssertNil(CohabitSettingsForm.problem(config), "ohne eigene Werte gelten die Vorgaben")
        config.challenge?.run = .defaults
        config.challenge?.run?.basePoints = 0
        XCTAssertNil(CohabitSettingsForm.problem(config), "0 Punkte Basis ist erlaubt")
        config.challenge?.run?.paceLimitSeconds = nil
        XCTAssertEqual(CohabitSettingsForm.problem(config), "Pace-Grenze fehlt")
        config.challenge?.run?.paceLimitSeconds = 30
        XCTAssertEqual(CohabitSettingsForm.problem(config), "Pace-Grenze fehlt")
        config.challenge?.run?.paceLimitSeconds = 480
        config.challenge?.run?.minutesPerPoint = 0
        XCTAssertEqual(CohabitSettingsForm.problem(config), "Minuten je Punkt fehlen")
        config.challenge?.run?.minutesPerPoint = 6
        config.challenge?.run?.pointsPerKm = 1001
        XCTAssertEqual(CohabitSettingsForm.problem(config), "Punkte je km fehlen")
        config.challenge?.run?.pointsPerKm = 1
        XCTAssertNil(CohabitSettingsForm.problem(config))
        XCTAssertTrue(CohabitSettingsForm.scorings.contains { $0 == (ChallengeScoring.runPoints, "Laufpunkte") })
    }

    // MARK: - Mit dem Dienst

    /// Ein Lauf geht mit Dauer und Distanz raus; die Antwort traegt die
    /// Punkte, die danach gross oben stehen.
    func testPostingARunAndShowingItsPoints() async throws {
        StubServer.install { _ in .json(201, #"{"checkin":\#(Self.runCheckin),"cohabit":\#(Self.runDetail)}"#) }
        let request = CheckinRequest(id: "r1", date: day, durationMinutes: 35, distanceKm: 5.8)
        let result: CheckinResult = try await ClassicStoreTests.stubAPI()
            .send("POST", "/cohabits/c-run/checkins", body: request)
        let sent = try XCTUnwrap(StubServer.requests.first)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.path, "/cohabit/api/cohabits/c-run/checkins")
        XCTAssertEqual(sent.json?["durationMinutes"] as? Int, 35)
        XCTAssertEqual(sent.json?["distanceKm"] as? Double, 5.8)

        CheckInController.announcePoints(result.checkin)
        XCTAssertEqual(Toast.shared.message, "+20 P")
        XCTAssertEqual(Toast.shared.detail, "Basis 10 · Distanz 5 · Dauer 5")
        XCTAssertFalse(Toast.shared.isError)
        // Ein Eintrag ohne Lauf meldet nichts.
        let plain = try decode(Checkin.self, Fixtures.checkin)
        CheckInController.announcePoints(plain)
        XCTAssertEqual(Toast.shared.message, "+20 P")
    }

    /// Lehnt der Dienst den Lauf ab (Pace), bleibt das Blatt offen
    /// (`submit` → false), seine Meldung steht darin - und nichts wartet
    /// still im Postausgang.
    func testARejectedRunStaysInTheSheetWithTheReason() async throws {
        let controller = CheckInController.shared
        controller.makeAPI = { ClassicStoreTests.stubAPI() }
        controller.outbox = outbox
        StubServer.install { _ in .json(400, #"{"message":"\#(Self.paceMessage)"}"#) }

        let summary = try decode(CohabitSummary.self, Self.runSummary)
        let target = CheckInTarget(summary: summary, meId: "felix")
        let ok = await controller.submit(target, request: CheckinRequest(date: day, durationMinutes: 35, distanceKm: 4.1))
        XCTAssertFalse(ok, "das Blatt bleibt offen, die Eingaben stehen noch")
        XCTAssertEqual(controller.lastError, Self.paceMessage)
        XCTAssertEqual(StubServer.requests.first?.json?["distanceKm"] as? Double, 4.1)
        let waiting = await outbox.entries()
        XCTAssertTrue(waiting.isEmpty)
    }

    /// Ohne Netz wartet der Lauf; lehnt der Dienst ihn beim Nachsenden ab,
    /// steht in der Leiste, welcher Lauf es war und warum.
    func testARunRejectedFromTheOutboxNamesTheRun() async throws {
        await outbox.enqueueCheckin(cohabitId: "c-run",
                                    request: CheckinRequest(id: "r9", date: day, durationMinutes: 35, distanceKm: 4.1),
                                    photo: nil)
        StubServer.install { _ in .json(400, #"{"message":"\#(Self.paceMessage)"}"#) }
        await outbox.replay(using: ClassicStoreTests.stubAPI())

        XCTAssertEqual(StubServer.requests.first?.json?["durationMinutes"] as? Int, 35)
        XCTAssertEqual(StubServer.requests.first?.json?["id"] as? String, "r9")
        let left = await outbox.entries()
        XCTAssertTrue(left.isEmpty, "abgelehnt wartet nichts mehr")
        XCTAssertEqual(CohabitSync.shared.lastError, "Lauf 4,1 km in 35 Min. nicht angenommen: \(Self.paceMessage)")
        XCTAssertEqual(CohabitSync.shared.pending, 0)
    }
}
