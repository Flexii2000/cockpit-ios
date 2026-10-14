import XCTest
@testable import Healthy

/// Das Gym in der App (14.10.): was wartet, liegt ueber dem Stand des Dienstes
/// (`GymOverlay`), und jede Aenderung ist ein PUT mit dem ganzen Stand ihres Ziels.
/// Platzhalter statt echter Geraete - das Repo ist oeffentlich.
final class GymTests: XCTestCase {

    private let today = CalendarDate(year: 2026, month: 10, day: 14)

    private func state() -> GymState {
        let exercise = GymExercise(id: "e-1", machineId: "m-1", sets: 3, reps: 8, weightKg: 40)
        return GymState(today: today,
                        machines: [GymMachine(id: "m-1", name: "Gerät A", archived: false, createdAt: nil)],
                        days: [GymDay(id: "d-1", name: "Tag A", position: 0, exercises: [exercise], updatedAt: nil)],
                        nextDayId: "d-1", sessions: [], last: [:])
    }

    func testATickOnANewSessionShowsAtOnce() {
        let start = Date(timeIntervalSince1970: 1_791_900_000)
        let shown = GymOverlay.apply([
            .session(id: "s-1", dayId: "d-1", date: today, startedAt: start, endedAt: nil),
            .tick(sessionId: "s-1", exerciseId: "e-1", index: 0, weightKg: 40, reps: 8, doneAt: start),
        ], to: state())

        let session = try? XCTUnwrap(shown.openSession(for: "d-1", on: today))
        XCTAssertEqual(session?.sets.count, 1)
        XCTAssertEqual(session?.sets.first?.machineId, "m-1", "das Geraet kommt aus der Uebung")
        XCTAssertTrue(session?.isDone("e-1", 0) ?? false)
    }

    func testTakingATickBackRemovesIt() {
        let start = Date(timeIntervalSince1970: 1_791_900_000)
        let shown = GymOverlay.apply([
            .session(id: "s-1", dayId: "d-1", date: today, startedAt: start, endedAt: nil),
            .tick(sessionId: "s-1", exerciseId: "e-1", index: 0, weightKg: 40, reps: 8, doneAt: start),
            .tick(sessionId: "s-1", exerciseId: "e-1", index: 0, weightKg: nil, reps: nil, doneAt: nil),
        ], to: state())
        XCTAssertEqual(shown.sessions.first?.sets.count, 0)
    }

    /// Ein beendeter Besuch ist nicht mehr der, an dem heute abgehakt wird.
    func testAnEndedSessionIsNotOpen() {
        let start = Date(timeIntervalSince1970: 1_791_900_000)
        let shown = GymOverlay.apply([
            .session(id: "s-1", dayId: "d-1", date: today, startedAt: start, endedAt: start.addingTimeInterval(3600)),
        ], to: state())
        XCTAssertNil(shown.openSession(for: "d-1", on: today))
        XCTAssertEqual(shown.sessions(for: "d-1", on: today).count, 1, "die Haken bleiben sichtbar")
    }

    func testAWeightChangeReplacesThePlan() {
        let changed = GymExercise(id: "e-1", machineId: "m-1", sets: 3, reps: 8, weightKg: 42.5)
        let shown = GymOverlay.apply([.exercise(dayId: "d-1", exercise: changed)], to: state())
        XCTAssertEqual(shown.days.first?.exercises.first?.weightKg, 42.5)
        XCTAssertEqual(shown.days.first?.exercises.count, 1)
    }

    func testNewDaysSortByPosition() {
        let shown = GymOverlay.apply([
            .day(GymDay(id: "d-0", name: "Tag 0", position: -1, exercises: [], updatedAt: nil)),
        ], to: state())
        XCTAssertEqual(shown.days.map(\.id), ["d-0", "d-1"])
    }

    // MARK: - Anfragen

    private func json(_ change: GymChange) throws -> [String: Any] {
        let body = try XCTUnwrap(change.request.body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    func testRequestsMatchTheContract() throws {
        let exercise = GymExercise(id: "e-1", machineId: "m-1", sets: 3, reps: 8, weightKg: 40)
        XCTAssertEqual(GymChange.exercise(dayId: "d-1", exercise: exercise).request.path, "/api/gym/days/d-1/exercises/e-1")
        XCTAssertEqual(try json(.exercise(dayId: "d-1", exercise: exercise))["weightKg"] as? Double, 40)

        let start = Date(timeIntervalSince1970: 1_791_900_000)
        let session = GymChange.session(id: "s-1", dayId: "d-1", date: today, startedAt: start, endedAt: nil)
        XCTAssertEqual(session.request.method, "PUT")
        XCTAssertEqual(try json(session)["date"] as? String, "2026-10-14")
        XCTAssertNotNil(try json(session)["startedAt"] as? String, "ISO-Zeitpunkt")

        let tick = GymChange.tick(sessionId: "s-1", exerciseId: "e-1", index: 2, weightKg: 40, reps: 8, doneAt: start)
        XCTAssertEqual(tick.request.path, "/api/gym/sessions/s-1/sets/e-1/2")
        XCTAssertEqual(try json(tick)["reps"] as? Int, 8)

        let back = GymChange.tick(sessionId: "s-1", exerciseId: "e-1", index: 2, weightKg: nil, reps: nil, doneAt: nil)
        XCTAssertEqual(back.request.body, Data("{}".utf8), "zuruecknehmen ist ein leerer Rumpf, kein DELETE")
        XCTAssertEqual(back.target, tick.target, "derselbe Satz - die Warteschlange fasst zusammen")
        XCTAssertEqual(back.role, .state)
    }

    func testTheDayCarriesItsWholeList() throws {
        let day = state().days[0]
        let body = try json(.day(day))
        XCTAssertEqual((body["exercises"] as? [[String: Any]])?.first?["id"] as? String, "e-1")
        XCTAssertEqual(body["position"] as? Int, 0)
        XCTAssertEqual(body["weekdays"] as? [Int], [], "immer mit - leer nimmt sie weg")
    }

    // MARK: - Wochentage

    /// Mittwoch, 14.10.2026 - ISO 3.
    private func days(_ weekdays: [[Int]], next: String?) -> GymState {
        var state = state()
        state.days = weekdays.enumerated().map { index, days in
            GymDay(id: "d-\(index)", name: "Tag \(index)", position: index, exercises: [], weekdays: days)
        }
        state.nextDayId = next
        return state
    }

    func testIsoWeekdayStartsOnMonday() {
        XCTAssertEqual(CalendarDate(year: 2026, month: 10, day: 12).isoWeekday, 1)
        XCTAssertEqual(today.isoWeekday, 3)
        XCTAssertEqual(CalendarDate(year: 2026, month: 10, day: 18).isoWeekday, 7)
    }

    func testTheDayOfTodaysWeekdayBeatsTheRotation() {
        // „Dienstags bekommt man den Dienstag“ - hier Mittwoch.
        XCTAssertEqual(days([[1, 4], [3], []], next: "d-2").suggestedDay(on: today)?.id, "d-1")
    }

    func testWithoutTodaysWeekdayTheRotationDecides() {
        XCTAssertEqual(days([[1], [5], []], next: "d-2").suggestedDay(on: today)?.id, "d-2")
        XCTAssertEqual(days([[1], [5]], next: nil).suggestedDay(on: today)?.id, "d-0")
    }

    func testTwoDaysOnTodaysWeekdayPreferTheOneInTurn() {
        XCTAssertEqual(days([[3], [3]], next: "d-1").suggestedDay(on: today)?.id, "d-1")
        XCTAssertEqual(days([[3], [3], []], next: "d-2").suggestedDay(on: today)?.id, "d-0")
    }

    func testWeekdaysReadShort() {
        XCTAssertEqual(GymFormat.weekdays([5, 2]), "Di · Fr")
        XCTAssertEqual(GymFormat.weekdays([]), "")
    }

    // MARK: - Gewicht als Zahl

    func testTypedWeightsParse() {
        XCTAssertEqual(GymFormat.parseWeight("37,5"), 37.5)
        XCTAssertEqual(GymFormat.parseWeight("37.5"), 37.5)
        XCTAssertEqual(GymFormat.parseWeight(" 40 kg"), 40)
        XCTAssertEqual(GymFormat.parseWeight("12,345"), 12.35, "auf 0,01 wie der Dienst")
        XCTAssertEqual(GymFormat.parseWeight(""), 0, "leer ist ohne Gewicht")
        XCTAssertNil(GymFormat.parseWeight("abc"))
        XCTAssertNil(GymFormat.parseWeight("-5"))
        XCTAssertNil(GymFormat.parseWeight("500,5"))
    }

    func testTheWeightFieldShowsAPlainNumber() {
        XCTAssertEqual(GymFormat.weightField(37.5), "37,5")
        XCTAssertEqual(GymFormat.weightField(40), "40")
        XCTAssertEqual(GymFormat.weightField(0), "")
    }

    // MARK: - Anzeige

    func testWeightReadsGerman() {
        XCTAssertEqual(GymFormat.weight(40), "40 kg")
        XCTAssertEqual(GymFormat.weight(37.5), "37,5 kg")
        XCTAssertEqual(GymFormat.weight(0), "ohne Gewicht")
        XCTAssertEqual(GymFormat.scheme(sets: 3, reps: 8), "3×8")
        XCTAssertEqual(GymFormat.last(GymLast(date: today, weightKg: 42.5, sets: 3, reps: 8)),
                       "letztes Mal 3×8 · 42,5 kg")
    }

    func testDurationReadsLikeAClock() {
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(GymWorkoutView.duration(since: start, now: start.addingTimeInterval(727)), "12:07")
        XCTAssertEqual(GymWorkoutView.duration(since: start, now: start.addingTimeInterval(3727)), "1:02:07")
    }

    func testAbandonedWorkoutAfterTwelveHours() {
        let start = Date(timeIntervalSince1970: 1_791_900_000)
        let workout = ActiveWorkout(sessionId: "s-1", dayId: "d-1", date: today, startedAt: start)
        XCTAssertFalse(workout.isAbandoned(now: start.addingTimeInterval(2 * 3600)))
        XCTAssertTrue(workout.isAbandoned(now: start.addingTimeInterval(13 * 3600)))
    }

    /// Der Stand des Dienstes laesst sich lesen, wie der Vertrag §6 ihn beschreibt.
    func testDecodesTheServiceState() throws {
        let json = """
        {"today":"2026-10-14","machines":[{"id":"m-1","name":"Gerät A","archived":false,"createdAt":"2026-10-14T08:00:00Z"}],
         "days":[{"id":"d-1","name":"Tag A","position":0,"updatedAt":"2026-10-14T08:00:00.123456Z",
                  "exercises":[{"id":"e-1","machineId":"m-1","sets":3,"reps":8,"weightKg":40.0}]}],
         "nextDayId":null,
         "sessions":[{"id":"s-1","dayId":"d-1","date":"2026-10-14","startedAt":"2026-10-14T16:00:00Z","endedAt":null,
                      "sets":[{"exerciseId":"e-1","machineId":"m-1","index":0,"weightKg":40.0,"reps":8,"doneAt":"2026-10-14T16:05:00Z"}]}],
         "last":{"m-1":{"date":"2026-10-11","weightKg":37.5,"sets":3,"reps":8}}}
        """
        let state = try APIClient.decoder().decode(GymState.self, from: Data(json.utf8))
        XCTAssertNil(state.nextDayId)
        XCTAssertEqual(state.last["m-1"]?.weightKg, 37.5)
        XCTAssertEqual(state.sessions.first?.sets.first?.index, 0)
        // Der Stand von vor dem Nachtrag (14.10.): ohne Wochentage und Geraeteliste.
        XCTAssertEqual(state.days.first?.weekdays, [])
        XCTAssertEqual(state.catalog, [])
    }

    func testDecodesWeekdaysAndTheCatalog() throws {
        let json = """
        {"today":"2026-10-14","machines":[],"nextDayId":"d-1","sessions":[],"last":{},
         "days":[{"id":"d-1","name":"Tag A","position":0,"weekdays":[2,5],"exercises":[]}],
         "catalog":[{"name":"Gruppe A","entries":["Gerät G","Gerät H"]}]}
        """
        let state = try APIClient.decoder().decode(GymState.self, from: Data(json.utf8))
        XCTAssertEqual(state.days.first?.weekdays, [2, 5])
        XCTAssertEqual(state.catalog.first?.entries, ["Gerät G", "Gerät H"])

        // Zwischenspeicher und Warteschlange: was die App selbst schreibt, liest sie wieder.
        let again = try APIClient.decoder().decode(GymState.self, from: APIClient.encoder().encode(state))
        XCTAssertEqual(again, state)
    }
}
