import XCTest

/// Die Einkaufsliste: einen Eintrag anlegen und wieder loeschen - gegen den
/// echten Dienst (oder mit COCKPIT_URL_SHOPPING gegen einen lokalen), und
/// hinterher so, wie es war. Die Liste ist geteilt: was der Test anlegt,
/// raeumt er weg.
final class EinkaufUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testItemCanBeAddedAndDeleted() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let token = environment["COCKPIT_SHOPPING_TOKEN"], !token.isEmpty else {
            throw XCTSkip("COCKPIT_SHOPPING_TOKEN fehlt - siehe Kopf von tools/uitest.sh")
        }
        let app = start(tab: "shopping", extra: [
            "COCKPIT_URL_SHOPPING": environment["COCKPIT_URL_SHOPPING"] ?? "",
        ])
        let field = app.textFields["newItem"]
        XCTAssertTrue(field.waitForExistence(timeout: 25), "Liste nicht geladen")
        shoot(app, "einkauf-liste")

        let name = "UI-Test \(Int(Date().timeIntervalSince1970))"
        field.tap()
        field.typeText(name + "\n")
        let row = app.staticTexts[name]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Eintrag nicht in der Liste")
        shoot(app, "einkauf-neu")

        row.swipeLeft()
        let delete = app.buttons["Löschen"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "keine Wischaktion")
        delete.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: row)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "Eintrag blieb stehen")
    }
}
