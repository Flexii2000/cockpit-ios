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

    func testStreakTextHandlesSingular() throws {
        let one = try APIClient.decoder().decode([HabitStatus].self, from: """
        [{"id":"q","name":"x","kind":"QUIT","unit":"DAYS","weeklyStepGoal":null,"streak":1,
          "doneToday":true,"atRisk":false,"progress":null,"recent":[true],"unavailable":null}]
        """.data(using: .utf8)!)[0]
        XCTAssertEqual(one.streakText, "1 Tag")
        XCTAssertFalse(one.kind.isAutomatic)
    }
}
