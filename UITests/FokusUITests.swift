import XCTest

/// Habits abhaken und wieder loesen.
final class FokusUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Abhaken und wieder loesen - der eine Weg, der etwas schreibt.
    ///
    /// Laeuft gegen den echten Dienst (oder mit COCKPIT_URL_HABITS gegen einen
    /// lokalen) und laesst ihn so zurueck, wie er war: erst Haken, dann Haken
    /// weg. Sucht sich das erste Build-Habit ueber seinen Knopf - die Kennungen
    /// tragen die Habit-ID, und die ist je Installation anders.
    func testHabitCanBeCheckedOffAndUncheckedAgain() {
        let environment = ProcessInfo.processInfo.environment
        let app = start(tab: "habits", extra: [
            "COCKPIT_URL_HABITS": environment["COCKPIT_URL_HABITS"] ?? "",
        ])
        XCTAssertTrue(app.staticTexts["Logbook"].waitForExistence(timeout: 25), "Habits nicht geladen")
        shoot(app, "habits-liste")

        let toggle = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'toggle-'")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "kein abhakbares Habit")
        // Der Anfangszustand ist unbekannt (ein frueherer Lauf koennte
        // abgebrochen sein) - zweimal tippen muss auf jeden Fall dort landen,
        // wo es losging, und einmal dazwischen anders sein.
        let streak = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH 'streak-'")).element(boundBy: 1)
        let before = streak.label
        toggle.tap()
        XCTAssertTrue(waitFor(streak, toChangeFrom: before), "Straehne blieb bei \(before)")
        shoot(app, "habits-abgehakt")
        let between = streak.label
        toggle.tap()
        XCTAssertTrue(waitFor(streak, toChangeFrom: between), "Straehne blieb bei \(between)")
        XCTAssertEqual(streak.label, before, "nach Haken und Loesen muss der alte Stand dastehen")
    }
}
