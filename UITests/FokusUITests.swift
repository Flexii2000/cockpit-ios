import XCTest

/// Fokus nach dem Umzug der Habits nach coHabit: To-Do vorn, der Wald
/// daneben, kein Habits-Tab mehr.
final class FokusUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Die Leiste hat zwei Eintraege, der erste ist To-Do.
    func testOpensOnTodoWithoutHabitsTab() {
        let app = start(tab: "", extra: [
            "COCKPIT_URL_TODO": ProcessInfo.processInfo.environment["COCKPIT_URL_TODO"] ?? "",
        ])
        let todo = app.tabBars.buttons["To-Do"]
        XCTAssertTrue(todo.waitForExistence(timeout: 20), "keine Leiste mit To-Do")
        shoot(app, "fokus-start")
        XCTAssertTrue(todo.isSelected, "To-Do muss vorn stehen")
        XCTAssertTrue(app.tabBars.buttons["Wald"].exists)
        XCTAssertFalse(app.tabBars.buttons["Habits"].exists, "der Habits-Tab ist nach coHabit umgezogen")
    }

    /// Der Wald laedt seine Baeume weiter vom Habits-Dienst und zeigt die Summe.
    func testForestShowsTheSummary() {
        let environment = ProcessInfo.processInfo.environment
        let app = start(tab: "forest", extra: [
            "COCKPIT_URL_HABITS": environment["COCKPIT_URL_HABITS"] ?? "",
            "COCKPIT_URL_COHABIT": environment["COCKPIT_URL_COHABIT"] ?? "",
            "COCKPIT_NO_SCREENTIME": "1",
            "COCKPIT_FOREST_RANGE": "week",
        ])
        let summary = app.staticTexts["forestSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 25), "Wald ohne Summe")
        shoot(app, "wald-woche")
        XCTAssertTrue(summary.label.contains("Baum") || summary.label.contains("Bäume"), summary.label)
    }
}
