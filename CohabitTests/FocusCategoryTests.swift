import XCTest
@testable import coHabit

/// Fokus-Habits nach Kategorie und Zeitraum (seit 2026-10-01): was der Dienst
/// in `auto` und in der klassischen Liste (`focus`) liefert, was die App beim
/// Anlegen und Bearbeiten schickt - und die Auswahl der Kategorien.
final class FocusCategoryTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder().decode(T.self, from: Fixtures.data(json))
    }

    private func object(_ value: some Encodable) throws -> [String: Any] {
        let data = try APIClient.encoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - auto

    /// Das Detail eines Fokus-Habits nur fuer die Bachelorarbeit, je Woche.
    func testDetailDecodesFocusCategoryAndPeriod() throws {
        let json = Fixtures.streakDetail.replacingOccurrences(of: #""auto":null"#, with: """
            "auto":{"source":"FOCUS","weeklyStepGoal":null,"focusMinutesGoal":600,
                    "focusCategoryId":"ed49-2245","focusCategoryName":"Bachelorarbeit","focusPeriod":"WEEK"}
            """)
        XCTAssertNotEqual(json, Fixtures.streakDetail, "die Fixture hat kein \"auto\":null mehr")
        let auto = try XCTUnwrap(try decode(CohabitDetail.self, json).config.auto)
        XCTAssertEqual(auto.focusMinutesGoal, 600)
        XCTAssertEqual(auto.focusCategoryId, "ed49-2245")
        XCTAssertEqual(auto.focusCategoryName, "Bachelorarbeit")
        XCTAssertTrue(auto.isWeeklyFocus)

        // Ein Dienst von vorher: keine der drei Angaben - alle Baeume, je Tag.
        let old = try decode(CohabitConfig.Auto.self, #"{"source":"FOCUS","weeklyStepGoal":null,"focusMinutesGoal":240}"#)
        XCTAssertNil(old.focusCategoryId)
        XCTAssertNil(old.focusPeriod)
        XCTAssertFalse(old.isWeeklyFocus)
    }

    /// Kategorie und Zeitraum stehen immer im Rumpf - ein fehlendes Feld liest
    /// der Dienst beim Bearbeiten als „alle Baeume" bzw. „je Tag". Den Namen
    /// traegt er selbst ein; die App schickt ihn nicht.
    func testAutoSendsCategoryAndPeriodButNotTheName() throws {
        let tagged = try object(CohabitConfig.Auto(source: "FOCUS", weeklyStepGoal: nil, focusMinutesGoal: 60,
                                                   focusCategoryId: "ed49-2245", focusCategoryName: "Bachelorarbeit",
                                                   focusPeriod: "WEEK"))
        XCTAssertEqual(tagged["focusCategoryId"] as? String, "ed49-2245")
        XCTAssertEqual(tagged["focusPeriod"] as? String, "WEEK")
        XCTAssertFalse(tagged.keys.contains("focusCategoryName"))

        let all = try object(CohabitConfig.Auto(source: "FOCUS", weeklyStepGoal: nil, focusMinutesGoal: 240))
        XCTAssertTrue(all["focusCategoryId"] is NSNull, "alle Baeume muss ausdruecklich null sein")
        XCTAssertEqual(all["focusPeriod"] as? String, "DAY")

        let steps = try object(CohabitConfig.Auto(source: "STEPS_WEEKLY", weeklyStepGoal: 70_000, focusMinutesGoal: nil,
                                                  focusCategoryId: "ed49-2245", focusPeriod: "WEEK"))
        XCTAssertTrue(steps["focusCategoryId"] is NSNull)
        XCTAssertTrue(steps["focusPeriod"] is NSNull)
    }

    // MARK: - Klassische Liste

    private func classic(kind: String = "FOCUS", unit: String = "DAYS", streak: Int = 3, atRisk: Bool = false,
                         focus: String) throws -> ClassicHabit {
        try decode([ClassicHabit].self, """
        [{"id":"f1","name":"Bachelorarbeit","kind":"\(kind)","unit":"\(unit)","weeklyStepGoal":null,
          "focusMinutesGoal":60,"period":null,"timesPerPeriod":null,"streak":\(streak),"doneToday":false,
          "atRisk":\(atRisk),"progress":{"value":135,"goal":600},"recent":[],"unavailable":null,
          "markedDays":[],"createdAt":"2026-10-01","photoRequired":false,"shared":false,"admin":true,
          "backfillFrom":"2026-09-17","summary":null,"focus":\(focus)}]
        """)[0]
    }

    /// `focus` mit Kategorie und Zeitraum; ohne Kategorie alle Baeume, ein
    /// unbekannter Zeitraum gilt als Tag, und ein Dienst ohne das Feld laesst
    /// die Zeile trotzdem stehen.
    func testClassicHabitDecodesFocus() throws {
        let weekly = try classic(unit: "WEEKS", focus: #"{"categoryId":"ed49-2245","categoryName":"Bachelorarbeit","period":"WEEK"}"#)
        XCTAssertEqual(weekly.focus, ClassicHabit.Focus(categoryId: "ed49-2245", categoryName: "Bachelorarbeit", period: .week))
        XCTAssertEqual(weekly.progress?.focusText, "2:15/10:00 h")
        XCTAssertEqual(weekly.streakText, "3 Wochen")

        let all = try classic(focus: #"{"categoryId":null,"categoryName":null,"period":"DAY"}"#)
        XCTAssertNil(all.focus?.categoryId)
        XCTAssertEqual(all.focus?.period, .day)

        let future = try classic(focus: #"{"categoryId":null,"categoryName":null,"period":"MONTH"}"#)
        XCTAssertEqual(future.focus?.period, .day)

        let old = try classic(focus: "null")
        XCTAssertNil(old.focus)
    }

    /// Unter dem Namen: „3 Tage · Bachelorarbeit" - ohne Kategorie wie bisher,
    /// gefaehrdet mit „heute noch offen" dahinter.
    func testSubtitleShowsTheCategory() throws {
        let tagged = try classic(focus: #"{"categoryId":"ed49-2245","categoryName":"Bachelorarbeit","period":"DAY"}"#)
        XCTAssertEqual(tagged.subtitleText, "3 Tage · Bachelorarbeit")
        let weekly = try classic(unit: "WEEKS", streak: 1,
                                 focus: #"{"categoryId":"c-uni","categoryName":"Uni","period":"WEEK"}"#)
        XCTAssertEqual(weekly.subtitleText, "1 Woche · Uni")
        let atRisk = try classic(atRisk: true,
                                 focus: #"{"categoryId":"ed49-2245","categoryName":"Bachelorarbeit","period":"DAY"}"#)
        XCTAssertEqual(atRisk.subtitleText, "3 Tage · Bachelorarbeit · heute noch offen")
        let all = try classic(focus: #"{"categoryId":null,"categoryName":null,"period":"DAY"}"#)
        XCTAssertEqual(all.subtitleText, "3 Tage")
    }

    /// Das alte Formular: bei Fokus-Zeit Kategorie und Zeitraum immer
    /// ausdruecklich, „alle Baeume" als `""`; bei den anderen Arten fehlen
    /// beide Schluessel - fuer den Dienst heisst das „unveraendert".
    func testDraftSendsCategoryAsIdOrEmptyAndOmitsItElsewhere() throws {
        let all = ClassicHabitDraft(form: "Fokus", kind: .focus, stepGoal: nil, focusMinutes: 240,
                                    period: nil, timesPerPeriod: 1)
        XCTAssertEqual(all.focusCategoryId, "")
        XCTAssertEqual(all.focusPeriod, .day)
        let allBody = try object(all)
        XCTAssertEqual(allBody["focusCategoryId"] as? String, "")
        XCTAssertEqual(allBody["focusPeriod"] as? String, "DAY")

        let thesis = ClassicHabitDraft(form: "Bachelorarbeit", kind: .focus, stepGoal: nil, focusMinutes: 600,
                                       period: nil, timesPerPeriod: 1, focusCategoryId: "ed49-2245", focusPeriod: .week)
        let thesisBody = try object(thesis)
        XCTAssertEqual(thesisBody["focusCategoryId"] as? String, "ed49-2245")
        XCTAssertEqual(thesisBody["focusPeriod"] as? String, "WEEK")
        XCTAssertEqual(thesisBody["focusMinutesGoal"] as? Int, 600)

        let build = ClassicHabitDraft(form: "Lesen", kind: .build, stepGoal: nil, focusMinutes: 240,
                                      period: .day, timesPerPeriod: 1, focusCategoryId: "ed49-2245", focusPeriod: .week)
        let buildBody = try object(build)
        XCTAssertFalse(buildBody.keys.contains("focusCategoryId"))
        XCTAssertFalse(buildBody.keys.contains("focusPeriod"))
        XCTAssertTrue(buildBody["focusMinutesGoal"] is NSNull)
    }

    // MARK: - Auswahl

    /// Eine im Wald geloeschte Kategorie behaelt ein bestehendes Habit - das
    /// Formular zeigt sie weiter, statt sie beim Sichern zu verlieren.
    func testChoicesKeepADeletedCategory() {
        let list = [FocusCategory(id: "c-1", name: "Bachelorarbeit"), FocusCategory(id: "c-2", name: "Uni")]
        XCTAssertEqual(FocusCategoryChoices.merged(list, keeping: nil, name: nil), list)
        XCTAssertEqual(FocusCategoryChoices.merged(list, keeping: "", name: nil), list)
        XCTAssertEqual(FocusCategoryChoices.merged(list, keeping: "c-2", name: "Uni"), list)
        XCTAssertEqual(FocusCategoryChoices.merged(list, keeping: "c-0", name: "Seminar").last,
                       FocusCategory(id: "c-0", name: "Seminar"))
    }

    /// Je Tag bis 16 Stunden in Viertelstunden wie bisher, je Woche bis 168
    /// Stunden in Stunden - so viel nimmt der Dienst (10.080 Minuten).
    func testMinutesPerDayOrWeek() {
        XCTAssertEqual(FocusCategoryChoices.range(weekly: false), 15...960)
        XCTAssertEqual(FocusCategoryChoices.range(weekly: true).upperBound, 10_080)
        XCTAssertEqual(FocusCategoryChoices.step(weekly: true), 60)
        XCTAssertEqual(FocusCategoryChoices.minutesText(240, weekly: false), "4:00 h am Tag")
        XCTAssertEqual(FocusCategoryChoices.minutesText(630, weekly: true), "10:30 h pro Woche")
    }
}
