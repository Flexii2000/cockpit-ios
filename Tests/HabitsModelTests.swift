import XCTest
@testable import Healthy

/// Die Antwort des Habits-Dienstes, so wie sie wirklich aussieht.
///
/// Die Schluessel hier sind die, die `HabitStatus` in Java serialisiert -
/// weicht einer ab, faellt es genau hier auf und nicht erst als leere Liste
/// auf dem Handy.
final class HabitsModelTests: XCTestCase {

    private static let sample = """
    [{"id":"s1","name":"70.000 Schritte / Woche","kind":"STEPS","unit":"WEEKS",
      "weeklyStepGoal":70000,"streak":3,"doneToday":false,"atRisk":false,
      "progress":{"value":55432,"goal":70000},
      "recent":[true,true,true,true,true,true,false],"unavailable":null},
     {"id":"b1","name":"Logbook","kind":"BUILD","unit":"DAYS","weeklyStepGoal":null,
      "streak":12,"doneToday":false,"atRisk":true,"progress":null,
      "recent":[true,true,true,true,true,true,false],"unavailable":null},
     {"id":"f1","name":"Track food","kind":"FOOD","unit":"DAYS","weeklyStepGoal":null,
      "streak":0,"doneToday":false,"atRisk":false,"progress":null,
      "recent":[],"unavailable":"Kalorienzähler nicht erreichbar"}]
    """.data(using: .utf8)!

    func testDecodesTheServerShape() throws {
        let habits = try APIClient.decoder().decode([HabitStatus].self, from: Self.sample)
        XCTAssertEqual(habits.count, 3)
        XCTAssertEqual(habits[0].kind, .steps)
        XCTAssertEqual(habits[0].unit, .weeks)
        XCTAssertEqual(habits[0].progress?.stepsText, "55/70k")
        XCTAssertTrue(habits[1].atRisk)
        XCTAssertEqual(habits[1].streakText, "12 Tage")
        XCTAssertEqual(habits[2].unavailable, "Kalorienzähler nicht erreichbar")
    }

    func testStepsTextRoundsToThousandsAndKeepsOvershoot() {
        XCTAssertEqual(HabitProgress(value: 98_400, goal: 70_000).stepsText, "98/70k")
        XCTAssertEqual(HabitProgress(value: 499, goal: 70_000).stepsText, "0/70k")
        XCTAssertEqual(HabitProgress(value: 500, goal: 70_000).stepsText, "1/70k")
        // Kein runder Tausender: dann die vollen Zahlen, sonst wuerde 75.500 zu "75k".
        XCTAssertEqual(HabitProgress(value: 1_000, goal: 75_500).stepsText, "1.000/75.500")
    }

    func testFractionIsCappedAtOne() {
        XCTAssertEqual(HabitProgress(value: 98_400, goal: 70_000).fraction, 1)
        XCTAssertEqual(HabitProgress(value: 35_000, goal: 70_000).fraction, 0.5)
        XCTAssertEqual(HabitProgress(value: 10, goal: 0).fraction, 0)
    }

    /// Die fuenfte Art: Fokus-Zeit mit Tagesziel in Minuten, Stand als „h:mm".
    func testDecodesFocusHabitAndFormatsHours() throws {
        let habit = try APIClient.decoder().decode([HabitStatus].self, from: """
        [{"id":"x1","name":"Fokus","kind":"FOCUS","unit":"DAYS","weeklyStepGoal":null,
          "streak":2,"doneToday":false,"atRisk":true,"progress":{"value":135,"goal":240},
          "recent":[false,false,false,false,true,true,false],"unavailable":null,
          "focusMinutesGoal":240}]
        """.data(using: .utf8)!)[0]
        XCTAssertEqual(habit.kind, .focus)
        XCTAssertTrue(habit.kind.isAutomatic)
        XCTAssertEqual(habit.focusMinutesGoal, 240)
        XCTAssertEqual(habit.progress?.focusText, "2:15/4:00 h")
        XCTAssertEqual(HabitProgress.hours(0), "0:00")
        XCTAssertEqual(HabitProgress.hours(605), "10:05")
    }

    /// Eine Session, wie `/api/focus/sessions` sie liefert - Zeitpunkte mit
    /// Nachkommastellen, der Tag als yyyy-MM-dd.
    func testDecodesFocusSession() throws {
        let session = try APIClient.decoder().decode([FocusSession].self, from: """
        [{"id":"a1","start":"2026-09-20T12:00:00.123456Z","end":"2026-09-20T13:30:00Z",
          "minutes":90,"day":"2026-09-20"}]
        """.data(using: .utf8)!)[0]
        XCTAssertEqual(session.minutes, 90)
        XCTAssertEqual(session.day, CalendarDate(year: 2026, month: 9, day: 20))
        XCTAssertEqual(session.end.timeIntervalSince(session.start), 5_400, accuracy: 1)
    }

    /// Was die App meldet, muss Jacksons `Instant` lesen koennen: ISO mit `Z`,
    /// keine Sekunden-seit-2001.
    func testFocusSessionDraftSendsInstants() throws {
        let start = Date(timeIntervalSince1970: 1_789_000_000)
        let draft = FocusSessionDraft(id: "b2", start: start, end: start.addingTimeInterval(1_800))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: APIClient.encoder().encode(draft)) as? [String: Any])
        XCTAssertEqual(object["id"] as? String, "b2")
        XCTAssertEqual(object["start"] as? String, "2026-09-10T00:26:40Z")
        XCTAssertEqual(object["end"] as? String, "2026-09-10T00:56:40Z")
        // Und zurueck: derselbe Zeitpunkt, wie ihn der Dienst spaeter liefert.
        XCTAssertEqual(APIClient.parseInstant("2026-09-10T00:26:40Z"), start)
    }

    func testStreakTextHandlesSingular() throws {
        let one = try APIClient.decoder().decode([HabitStatus].self, from: """
        [{"id":"q","name":"x","kind":"QUIT","unit":"DAYS","weeklyStepGoal":null,"streak":1,
          "doneToday":true,"atRisk":false,"progress":null,"recent":[true],"unavailable":null}]
        """.data(using: .utf8)!)[0]
        XCTAssertEqual(one.streakText, "1 Tag")
        XCTAssertFalse(one.kind.isAutomatic)
    }
}
