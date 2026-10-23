import XCTest
@testable import Sport

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
        // ... und von vor dem 19.10.: ohne Notiz, Spanne und Saetze einzeln.
        XCTAssertNil(state.machines.first?.note)
        XCTAssertNil(state.days.first?.exercises.first?.repsMin)
        XCTAssertEqual(state.last["m-1"]?.setReps, [])
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

    // MARK: - Notiz, Spanne, Saetze einzeln (19.10.)

    func testDecodesNotesRangesAndSetReps() throws {
        let json = """
        {"today":"2026-10-19","nextDayId":"d-1","sessions":[],
         "machines":[{"id":"m-1","name":"Gerät A","archived":false,"createdAt":"2026-10-14T08:00:00Z","note":"Sitz 4 · Lehne 2"},
                     {"id":"m-2","name":"Gerät B","archived":false,"createdAt":"2026-10-14T08:00:00Z","note":null}],
         "days":[{"id":"d-1","name":"Tag A","position":0,"weekdays":[],
                  "exercises":[{"id":"e-1","machineId":"m-1","sets":3,"reps":10,"repsMin":8,"weightKg":40.0},
                               {"id":"e-2","machineId":"m-2","sets":3,"reps":10,"repsMin":null,"weightKg":20.0}]}],
         "last":{"m-1":{"date":"2026-10-16","weightKg":42.5,"sets":3,"reps":10,"setReps":[10,9,8]}}}
        """
        let state = try APIClient.decoder().decode(GymState.self, from: Data(json.utf8))
        XCTAssertEqual(state.machine("m-1")?.note, "Sitz 4 · Lehne 2")
        XCTAssertNil(state.machine("m-2")?.note)
        XCTAssertEqual(state.days.first?.exercises.first?.repsRange, 8...10)
        XCTAssertNil(state.days.first?.exercises.last?.repsRange)
        XCTAssertEqual(state.last["m-1"]?.setReps, [10, 9, 8])
        let again = try APIClient.decoder().decode(GymState.self, from: APIClient.encoder().encode(state))
        XCTAssertEqual(again, state)

        let history = try APIClient.decoder().decode([GymHistoryPoint].self, from: Data("""
        [{"date":"2026-10-12","weightKg":40.0,"sets":3,"reps":10},
         {"date":"2026-10-16","weightKg":42.5,"sets":3,"reps":10,"setReps":[10,9,8]}]
        """.utf8))
        XCTAssertEqual(history.map(\.setReps), [[], [10, 9, 8]], "ein aelterer Dienst schickt keine")
    }

    func testSchemeShowsARangeWithAnEnDash() {
        XCTAssertEqual(GymFormat.scheme(sets: 2, reps: 10, repsMin: 8), "2×8\u{2013}10")
        XCTAssertEqual(GymFormat.scheme(sets: 3, reps: 8, repsMin: nil), "3×8")
        XCTAssertEqual(GymFormat.scheme(sets: 3, reps: 8, repsMin: 8), "3×8", "gleich reps: keine Spanne")
        XCTAssertEqual(GymFormat.scheme(sets: 3, reps: 8, repsMin: 9), "3×8")
        XCTAssertEqual(GymFormat.scheme(sets: 3, reps: 8, repsMin: 0), "3×8", "0 heisst beim Dienst keine Spanne")
    }

    func testLastShowsEachSetAtTheHeaviestWeight() {
        func last(_ setReps: [Int]) -> String {
            GymFormat.last(GymLast(date: today, weightKg: 40, sets: 3, reps: 10, setReps: setReps))
        }
        XCTAssertEqual(last([10, 9]), "letztes Mal 10, 9 · 40 kg")
        XCTAssertEqual(last([10, 10]), "letztes Mal 2×10 · 40 kg", "die Saetze mit diesem Gewicht, nicht alle drei")
        XCTAssertEqual(last([]), "letztes Mal 3×10 · 40 kg", "aeltere Staende wie bisher")

        let point = GymHistoryPoint(date: today, weightKg: 37.5, sets: 3, reps: 8, setReps: [8, 8, 7])
        XCTAssertEqual(GymFormat.history(point), "8, 8, 7 · 37,5 kg")
        XCTAssertEqual(GymFormat.history(GymHistoryPoint(date: today, weightKg: 37.5, sets: 3, reps: 8)),
                       "3×8 · 37,5 kg")
    }

    func testANoteGoesOnlyWhenThereIsOne() throws {
        var machine = state().machines[0]
        XCTAssertNil(try json(.machine(machine))["note"], "ohne fehlt das Feld - beim Dienst bleibt die Notiz")
        machine.note = "Sitz 4"
        XCTAssertEqual(try json(.machine(machine))["note"] as? String, "Sitz 4")
        machine.note = ""
        XCTAssertEqual(try json(.machine(machine))["note"] as? String, "", "leer loescht sie")
    }

    func testARangeGoesOnlyWhenThereIsOne() throws {
        let plain = state().days[0].exercises[0]
        let ranged = GymExercise(id: "e-2", machineId: "m-1", sets: 2, reps: 10, repsMin: 8, weightKg: 40)
        XCTAssertNil(try json(.exercise(dayId: "d-1", exercise: plain))["repsMin"])
        let body = try json(.exercise(dayId: "d-1", exercise: ranged))
        XCTAssertEqual(body["repsMin"] as? Int, 8)
        XCTAssertEqual(body["reps"] as? Int, 10, "reps bleibt die obere Grenze")

        let day = GymDay(id: "d-1", name: "Tag A", position: 0, exercises: [plain, ranged], updatedAt: nil)
        let exercises = try XCTUnwrap(try json(.day(day))["exercises"] as? [[String: Any]])
        XCTAssertNil(exercises[0]["repsMin"], "auch im ganzen Tag nur mit Spanne")
        XCTAssertEqual(exercises[1]["repsMin"] as? Int, 8)
    }

    func testTheOverlayShowsANoteAndARangeAtOnce() {
        var machine = state().machines[0]
        machine.note = "Sitz 4"
        let ranged = GymExercise(id: "e-1", machineId: "m-1", sets: 3, reps: 10, repsMin: 8, weightKg: 40)
        let shown = GymOverlay.apply([.machine(machine), .exercise(dayId: "d-1", exercise: ranged)], to: state())
        XCTAssertEqual(shown.machine("m-1")?.note, "Sitz 4")
        XCTAssertEqual(shown.days.first?.exercises.first?.repsRange, 8...10)
    }

    /// Was vor dem 19.10. in der Warteschlange lag, kennt beide Felder nicht -
    /// und schickt sie deshalb auch nicht mit.
    func testOlderQueuedChangesStillRead() throws {
        let machine = try JSONDecoder().decode(PendingChange.self, from: Data("""
        {"gym":{"_0":{"machine":{"_0":{"id":"m-1","name":"Gerät A","archived":false}}}}}
        """.utf8))
        let exercise = try JSONDecoder().decode(PendingChange.self, from: Data("""
        {"gym":{"_0":{"exercise":{"dayId":"d-1","exercise":{"id":"e-1","machineId":"m-1","sets":3,"reps":8,"weightKg":40}}}}}
        """.utf8))
        let machineChange = try XCTUnwrap(machine.gym)
        let exerciseChange = try XCTUnwrap(exercise.gym)
        XCTAssertNil(try json(machineChange)["note"])
        XCTAssertNil(try json(exerciseChange)["repsMin"])
        XCTAssertEqual(try json(exerciseChange)["reps"] as? Int, 8)
    }

    func testRepsAndTheirRangeMoveTogether() {
        let ranged = GymExercise(id: "e-1", machineId: "m-1", sets: 2, reps: 10, repsMin: 8, weightKg: 40)
        XCTAssertEqual(ranged.repsLower, 8)
        XCTAssertEqual(ranged.withReps(12).repsRange, 8...12, "nach oben bleibt die untere Grenze")
        XCTAssertNil(ranged.withReps(8).repsRange, "bis auf „mindestens“ gesenkt: keine Spanne mehr")
        XCTAssertEqual(ranged.withReps(7).repsMin, 7, "repsMin = reps - so nimmt der Dienst sie weg")

        // Eben entfernt, aber noch nicht beim Dienst: ein Plus darf sie nicht zurueckholen.
        let removed = GymExercise(id: "e-1", machineId: "m-1", sets: 2, reps: 10, repsMin: 10, weightKg: 40)
        XCTAssertEqual(removed.repsLower, 10)
        XCTAssertNil(removed.withReps(11).repsRange)
        XCTAssertEqual(removed.withReps(11).repsMin, 11)

        let plain = state().days[0].exercises[0]
        XCTAssertEqual(plain.repsLower, 8, "ohne Spanne zeigt „mindestens“ dieselbe Zahl")
        XCTAssertNil(plain.withReps(9).repsMin, "ohne Spanne bleibt das Feld weg")
    }

    func testANoteIsTrimmedAndCutLikeTheService() {
        XCTAssertEqual(GymFormat.note("  Sitz 4\n"), "Sitz 4")
        XCTAssertEqual(GymFormat.note("Sitz 4\nLehne 2"), "Sitz 4\nLehne 2", "Zeilenumbrueche bleiben")
        XCTAssertEqual(GymFormat.note(String(repeating: "a", count: 250)).count, 200)
        XCTAssertEqual(GymFormat.note(String(repeating: "\u{1F4AA}", count: 150)).utf16.count, 200, "Java zaehlt UTF-16")
    }

    // MARK: - Wiederholungen je Satz (19.10.)

    /// Im Training mit Spanne zaehlt die Zahl nur fuer den Satz, der Plan bleibt.
    @MainActor
    func testATickCarriesTheRepsOfThisSetOnly() throws {
        var gym = state()
        gym.days[0].exercises[0] = GymExercise(id: "e-1", machineId: "m-1", sets: 3, reps: 10, repsMin: 8, weightKg: 40)
        let store = GymStore(memory: gym)
        let day = try XCTUnwrap(store.state?.days.first)
        let exercise = day.exercises[0]

        store.tickNext(exercise, on: day, reps: 9)
        store.tickNext(exercise, on: day)
        store.toggle(exercise, 2, on: day, reps: 0)

        let sets = try XCTUnwrap(store.state?.sessions.first?.sets).sorted { $0.index < $1.index }
        XCTAssertEqual(sets.map(\.reps), [9, 10, 1], "ohne Angabe der Plan, nie unter 1")
        XCTAssertEqual(sets.map(\.weightKg), [40, 40, 40])
        XCTAssertEqual(store.state?.days.first?.exercises.first, exercise, "der Plan bleibt")
    }

    @MainActor
    func testANoteIsSetAndCleared() {
        let store = GymStore(memory: state())
        store.setNote(machineId: "m-1", to: "  Sitz 4 \n")
        XCTAssertEqual(store.state?.machine("m-1")?.note, "Sitz 4")
        store.setNote(machineId: "m-1", to: " ")
        XCTAssertEqual(store.state?.machine("m-1")?.note, "", "leer geht als \"\" - nil hiesse „bleibt“")
    }

    // MARK: - Uhr

    func testSetDoneCarriesTheRepsFromTheCrown() throws {
        let message = WorkoutMessage.setDone(id: "x", exerciseId: "e-1", reps: 9)
        XCTAssertEqual(WorkoutMessage.decode(try XCTUnwrap(message.encoded())), message)

        let plan = try XCTUnwrap(WorkoutMessage.setDone(id: "y", exerciseId: "e-1", reps: nil).encoded())
        XCTAssertFalse(String(decoding: plan, as: UTF8.self).contains("reps"), "ohne Spanne wie bisher")

        // Eine Uhr von vor dem 19.10. schickt keine Wiederholungen.
        XCTAssertEqual(WorkoutMessage.decode(Data(#"{"setDone":{"id":"z","exerciseId":"e-1"}}"#.utf8)),
                       .setDone(id: "z", exerciseId: "e-1", reps: nil))
    }

    func testTheWatchGetsThePlanWithNoteRangeAndAllMachines() throws {
        let current = WorkoutCurrent(exerciseId: "e-1", name: "Gerät A", note: "Sitz 4", set: 2, sets: 3,
                                     reps: 10, repsMin: 8, weightKg: 40)
        let plan = WorkoutPlan(current: current,
                               stations: [WorkoutStation(exerciseId: "e-1", name: "Gerät A", done: 1, sets: 3),
                                          WorkoutStation(exerciseId: "e-2", name: "Gerät B", done: 2, sets: 2)],
                               lastSetAt: Date(timeIntervalSince1970: 1_761_000_000))
        let message = WorkoutMessage.plan(plan)
        XCTAssertEqual(WorkoutMessage.decode(try XCTUnwrap(message.encoded())), message)
        XCTAssertTrue(plan.stations[1].isDone)
        XCTAssertFalse(plan.stations[0].isDone)

        // Alles erledigt: kein aktuelles Geraet, die Liste bleibt.
        let done = WorkoutMessage.plan(WorkoutPlan(current: nil, stations: plan.stations, lastSetAt: nil))
        XCTAssertEqual(WorkoutMessage.decode(try XCTUnwrap(done.encoded())), done)
    }

    func testChoosingAMachineOnTheWatchIsAcknowledgedOnce() throws {
        let message = WorkoutMessage.choose(id: "c-1", exerciseId: "e-2")
        XCTAssertEqual(WorkoutMessage.decode(try XCTUnwrap(message.encoded())), message)
    }

    @MainActor
    func testTheLastTickOfTheDayIsWhenThePauseStarted() throws {
        let store = GymStore(memory: state())
        let day = try XCTUnwrap(store.state?.days.first)
        XCTAssertNil(store.lastSetAt(on: day))
        let exercise = try XCTUnwrap(day.exercises.first)
        store.toggle(exercise, 0, on: day)
        let first = try XCTUnwrap(store.lastSetAt(on: day))
        XCTAssertLessThan(abs(first.timeIntervalSinceNow), 5)
    }
}
