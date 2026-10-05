import XCTest
@testable import coHabit

/// „Heute" nach Typ (Felix, 2026-10-05): Reihenfolge wie die klassische Liste,
/// Farbe nach Typ, Kennzahl ausgeschrieben, Balken wo es ein Ziel gibt.
final class TodayTypeTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder().decode(T.self, from: Fixtures.data(json))
    }

    /// Eine Zusammenfassung wie vom Dienst, mit Typ, Quelle, Anlegedatum und Stand.
    private func summary(_ id: String, _ type: CohabitType, auto: String? = nil, created: String? = "2026-09-01T08:00:00Z",
                         name: String? = nil, status: String = "OPEN",
                         progress: (done: Double, goal: Double, fraction: Double)? = nil) throws -> CohabitSummary {
        let autoJSON = auto.map { "\"\($0)\"" } ?? "null"
        let createdJSON = created.map { "\"\($0)\"" } ?? "null"
        let progressJSON = progress.map { #"{"done":\#($0.done),"goal":\#($0.goal),"fraction":\#($0.fraction)}"# } ?? "null"
        let ref = #"{"id":"\#(id)","name":"\#(name ?? id)","color":"rose","type":"\#(type.rawValue)","autoSource":\#(autoJSON),"createdAt":\#(createdJSON)}"#
        let json = Fixtures.summary
            .replacingOccurrences(of: Fixtures.ref, with: ref)
            .replacingOccurrences(of: #""status":"OPEN""#, with: #""status":"\#(status)""#)
            .replacingOccurrences(of: #""progress":{"done":2,"goal":3,"fraction":0.67}"#, with: #""progress":\#(progressJSON)"#)
        return try decode(CohabitSummary.self, json)
    }

    // MARK: - Neue Felder

    func testRefReadsSourceAndCreationAndAnOlderServiceWithout() throws {
        let auto = try decode(CohabitRef.self,
                              #"{"id":"c-1","name":"Schritte","color":"rose","type":"STREAK","autoSource":"STEPS_WEEKLY","createdAt":"2026-09-30T08:00:00Z"}"#)
        XCTAssertEqual(auto.autoSource, "STEPS_WEEKLY")
        XCTAssertTrue(auto.isAutomatic)
        XCTAssertEqual(auto.createdAt, Date(timeIntervalSince1970: 1_790_755_200))
        XCTAssertEqual(auto.storedColor, .rose, "die gespeicherte Farbe bleibt lesbar")
        let manual = try decode(CohabitRef.self,
                                #"{"id":"c-2","name":"Laufen","color":"peach","type":"STREAK","autoSource":null,"createdAt":"2026-09-30T08:00:00Z"}"#)
        XCTAssertFalse(manual.isAutomatic)
        let older = try decode(CohabitRef.self, Fixtures.ref)
        XCTAssertNil(older.autoSource)
        XCTAssertNil(older.createdAt)
        XCTAssertFalse(older.isAutomatic)
        // Liegt im Stand der Kachel - hin und zurueck, mit Farbe unter "color".
        let roundTrip = try APIClient.decoder().decode(CohabitRef.self, from: APIClient.encoder().encode(auto))
        XCTAssertEqual(roundTrip, auto)
        let object = try JSONSerialization.jsonObject(with: APIClient.encoder().encode(auto)) as? [String: Any]
        XCTAssertEqual(object?["color"] as? String, "rose")
    }

    func testChallengeProgressDecodes() throws {
        let challenge = try summary("c", .challenge, progress: (3, 5, 0.6))
        XCTAssertEqual(challenge.progress?.fraction, 0.6)
        XCTAssertNil(try summary("c", .challenge).progress, "vor dem Start und bei einem aelteren Dienst ohne")
    }

    // MARK: - Farbe

    func testColourByType() {
        func ref(_ type: CohabitType, _ auto: String? = nil) -> CohabitRef {
            CohabitRef(id: "x", name: "X", color: .rose, type: type, autoSource: auto)
        }
        // Die Vorgaben - so faerbt die App, solange der Dienst keine eigenen kennt.
        XCTAssertEqual(ref(.streak).typeColor(in: .defaults), .peach)
        XCTAssertEqual(ref(.abstinence).typeColor(in: .defaults), .mint)
        XCTAssertEqual(ref(.goal).typeColor(in: .defaults), .periwinkle)
        XCTAssertEqual(ref(.challenge).typeColor(in: .defaults), .butter)
        XCTAssertEqual(ref(.streak, "FOOD").typeColor(in: .defaults), .aqua)
        XCTAssertEqual(ref(.streak, "FOCUS").typeColor(in: .defaults), .aqua)
        XCTAssertEqual(ref(.goal, "SOMETHING_NEW").typeColor(in: .defaults), .aqua, "jede Quelle zaehlt als automatisch")
    }

    func testNewCohabitsGoOutInTheirTypeColour() {
        let defaults = TypeColors.defaults
        var config = CohabitConfig.draft(.challenge)
        config.color = .rose
        XCTAssertEqual(config.typeColor(in: defaults), .butter)
        config = .draft(.streak)
        config.auto = CohabitConfig.Auto(source: "STEPS_WEEKLY", weeklyStepGoal: 70_000, focusMinutesGoal: nil)
        XCTAssertEqual(config.typeColor(in: defaults), .aqua)
        XCTAssertEqual(config.typeColor(in: defaults.setting(.sage, for: .automatic)), .sage,
                       "automatisch geht vor dem Typ")
        config.auto = nil
        XCTAssertEqual(config.typeColor(in: defaults), .peach)
        XCTAssertEqual(config.typeColor(in: defaults.setting(.sky, for: .streak)), .sky)
        // Was beim Anlegen rausgeht, folgt den Farben der Sitzung (TypeColorsTests).
        MainActor.assumeIsolated {
            let model = CreateFlowModel()
            model.config = .draft(.goal)
            XCTAssertEqual(model.cleaned.color, Session.shared.typeColors[.goal])
        }
    }

    // MARK: - Reihenfolge

    func testOrderByTypeThenCreation() throws {
        let list = [
            try summary("auto-old", .streak, auto: "FOOD", created: "2026-09-01T08:00:00Z"),
            try summary("quit", .abstinence, created: "2026-08-01T08:00:00Z"),
            try summary("challenge", .challenge, created: "2026-09-20T08:00:00Z"),
            try summary("streak-new", .streak, created: "2026-10-02T08:00:00Z", status: "DONE"),
            try summary("goal", .goal, created: "2026-09-10T08:00:00Z"),
            try summary("streak-old", .streak, created: "2026-09-05T08:00:00Z"),
            try summary("auto-new", .streak, auto: "FOCUS", created: "2026-09-02T08:00:00Z"),
        ]
        XCTAssertEqual(list.typeOrder.map(\.id),
                       ["streak-old", "streak-new", "goal", "challenge", "quit", "auto-old", "auto-new"])
        XCTAssertEqual(list.typeOrder.map(\.ref.todayGroup),
                       [.streak, .streak, .goalsAndChallenges, .goalsAndChallenges, .abstinence, .automatic, .automatic])
    }

    func testTickingDoesNotMoveARow() throws {
        let open = [try summary("a", .streak, created: "2026-09-01T08:00:00Z"),
                    try summary("b", .streak, created: "2026-09-02T08:00:00Z")]
        let afterTicking = [try summary("b", .streak, created: "2026-09-02T08:00:00Z"),
                            try summary("a", .streak, created: "2026-09-01T08:00:00Z", status: "DONE")]
        XCTAssertEqual(open.typeOrder.map(\.id), afterTicking.typeOrder.map(\.id),
                       "der Dienst sortiert Erledigtes nach unten - die Liste nicht")
    }

    func testWithoutCreationDateByName() throws {
        let list = [try summary("2", .streak, created: nil, name: "Zähne"),
                    try summary("1", .streak, created: nil, name: "Ärger lassen"),
                    try summary("3", .streak, created: nil, name: "laufen")]
        XCTAssertEqual(list.typeOrder.map(\.ref.name), ["Ärger lassen", "laufen", "Zähne"])
        // Mit und ohne Datum: die mit Datum zuerst.
        let mixed = [try summary("ohne", .goal, created: nil), try summary("mit", .goal)]
        XCTAssertEqual(mixed.typeOrder.map(\.id), ["mit", "ohne"])
    }

    // MARK: - Kennzahl

    func testHeadlineSpelledOut() throws {
        let streak = Headline(value: "3", unit: "Wochen", short: "3 Wo.")
        XCTAssertEqual(streak.spelledUnit, "Wochen")
        XCTAssertEqual(streak.spokenText, "3 Wochen")
        let goal = Headline(value: "68%", unit: "", short: "68%")
        XCTAssertNil(goal.spelledUnit)
        XCTAssertEqual(goal.spokenText, "68%")
        XCTAssertEqual(Headline(value: "#2", unit: " dein Platz ", short: "#2").spokenText, "#2 dein Platz")
    }

    // MARK: - Balken

    func testBarsWhereThereIsSomethingToFill() throws {
        XCTAssertEqual(try summary("g", .goal, progress: (68, 100, 0.68)).gauge, .bar(0.68))
        XCTAssertEqual(try summary("c", .challenge, progress: (3, 5, 0.6)).gauge, .bar(0.6))
        XCTAssertEqual(try summary("s", .streak, auto: "STEPS_WEEKLY", progress: (45_000, 70_000, 0.64)).gauge, .bar(0.64))
        XCTAssertEqual(try summary("f", .streak, auto: "FOCUS", progress: (20, 30, 0.67)).gauge, .bar(0.67))
        // Kein Balken fuer Track food, das kcal-Ziel im Wochenmittel, die Evaluation, Unbekanntes.
        for source in ["FOOD", "FOOD_TARGET_WEEKLY", "EVALUATION", "SOMETHING_NEW"] {
            XCTAssertEqual(try summary("x", .streak, auto: source, progress: (1800, 2000, 0.9)).gauge, .none, source)
        }
        // Manuelle Streaks behalten ihre Punkte, Abstinenz hat nichts.
        XCTAssertEqual(try summary("m", .streak, progress: (2, 3, 0.67)).gauge, .weekDots(done: 2, goal: 3))
        XCTAssertEqual(try summary("m", .streak, progress: (10, 20, 0.5)).gauge, .none, "mehr als sieben Punkte nicht")
        XCTAssertEqual(try summary("a", .abstinence, progress: (1, 2, 0.5)).gauge, .none)
        XCTAssertEqual(try summary("c", .challenge).gauge, .none, "ohne Stand kein Balken")
    }
}
