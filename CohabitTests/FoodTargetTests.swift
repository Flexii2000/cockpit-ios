import XCTest
@testable import coHabit

/// Das Kalorienziel im Wochenmittel (`FOOD_TARGET_WEEKLY`, seit 2026-10-01):
/// eine automatische Quelle ohne eigene Ziele. Im Formular nur ein Name, in
/// der klassischen Liste eine Art „Track food" in Wochen - und eine Quelle,
/// die die App noch nicht kennt, kippt nichts.
final class FoodTargetTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder().decode(T.self, from: Fixtures.data(json))
    }

    private func object(_ value: some Encodable) throws -> [String: Any] {
        let data = try APIClient.encoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testSourceNamesAndUnknownSources() throws {
        let me = try decode(MeView.self, Fixtures.me.replacingOccurrences(
            of: #"["FOOD","STEPS_WEEKLY","FOCUS"]"#, with: #"["FOOD","FOOD_TARGET_WEEKLY","STEPS_WEEKLY","FOCUS","SLEEP"]"#))
        XCTAssertEqual(me.sources, ["FOOD", "FOOD_TARGET_WEEKLY", "STEPS_WEEKLY", "FOCUS", "SLEEP"])
        XCTAssertEqual(CohabitSettingsForm.sourceTitle("FOOD_TARGET_WEEKLY"), "Kalorienziel im Wochenmittel")
        XCTAssertEqual(CohabitSettingsForm.sourceTitle("FOOD"), "Track food")
        // Unbekannt: der Name, wie er kommt - kein Absturz, keine leere Kachel.
        XCTAssertEqual(CohabitSettingsForm.sourceTitle("SLEEP"), "SLEEP")
    }

    /// Zaehlt je Woche, hat keine Ziele - im Rumpf stehen alle Ziele als null.
    func testAutoCountsPerWeekWithoutGoals() throws {
        let auto = CohabitConfig.Auto(source: "FOOD_TARGET_WEEKLY", weeklyStepGoal: nil, focusMinutesGoal: nil)
        XCTAssertTrue(auto.isWeekly)
        XCTAssertFalse(CohabitConfig.Auto(source: "FOOD", weeklyStepGoal: nil, focusMinutesGoal: nil).isWeekly)
        let body = try object(auto)
        XCTAssertEqual(body["source"] as? String, "FOOD_TARGET_WEEKLY")
        for key in ["weeklyStepGoal", "focusMinutesGoal", "focusCategoryId", "focusPeriod"] {
            XCTAssertTrue(body[key] is NSNull, key)
        }
        let unknown = try decode(CohabitConfig.Auto.self, #"{"source":"SLEEP","weeklyStepGoal":null,"focusMinutesGoal":null}"#)
        XCTAssertEqual(unknown.source, "SLEEP")
        XCTAssertFalse(unknown.isWeekly)
    }

    /// In der klassischen Liste: Art FOOD, Einheit WEEKS, der Schnitt der
    /// Woche gegen das Ziel - mit „Ø", damit er nicht wie heute aussieht.
    func testClassicRowShowsTheWeeklyMean() throws {
        let habit = try decode([ClassicHabit].self, """
        [{"id":"w1","name":"Im Kalorienziel","kind":"FOOD","unit":"WEEKS","weeklyStepGoal":null,
          "focusMinutesGoal":null,"period":null,"timesPerPeriod":null,"streak":3,"doneToday":false,
          "atRisk":false,"progress":{"value":2250,"goal":2300},"recent":[true,true,true,false,true,true,true],
          "unavailable":null,"markedDays":[],"createdAt":"2026-09-01","photoRequired":false,"shared":false,
          "admin":true,"backfillFrom":"2026-09-17","summary":null,"focus":null}]
        """)[0]
        XCTAssertTrue(habit.isWeeklyFoodTarget)
        XCTAssertEqual(habit.kcalText, "Ø 2.250/2.300 kcal")
        XCTAssertEqual(habit.subtitleText, "3 Wochen")
        XCTAssertEqual(habit.kindLabel, "Kalorienziel im Wochenmittel")
        XCTAssertEqual(habit.action, .none)

        let daily = try decode([ClassicHabit].self, """
        [{"id":"d1","name":"Track food","kind":"FOOD","unit":"DAYS","weeklyStepGoal":null,"streak":5,
          "doneToday":true,"atRisk":false,"progress":{"value":1470,"goal":1840},"recent":[],"unavailable":null}]
        """)[0]
        XCTAssertFalse(daily.isWeeklyFoodTarget)
        XCTAssertEqual(daily.kcalText, "1.470/1.840 kcal")
        XCTAssertEqual(daily.kindLabel, "Track food")
    }
}
