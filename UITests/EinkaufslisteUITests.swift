import XCTest

/// Die Einkaufsliste: einen Eintrag anlegen und wieder loeschen - gegen den
/// echten Dienst (oder mit COCKPIT_URL_SHOPPING gegen einen lokalen), und
/// hinterher so, wie es war. Die Liste ist geteilt: was der Test anlegt,
/// raeumt er weg.
final class EinkaufslisteUITests: XCTestCase {

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

    // MARK: - Ohne Netz (gegen einen lokalen Dienst, den man dafuer anhaelt)

    /// Der Name, unter dem die Offline-Tests einen Eintrag anlegen und spaeter suchen.
    private static let offlineName = "Offline-Test"

    /// Nur mit angehaltenem Dienst (COCKPIT_OFFLINE_TEST=1) und einem Brett im
    /// Offline-Stand (vorher einmal online geladen): Hinzufuegen und Abhaken stehen
    /// sofort da, mit der Uhr am Haken, und ueberleben einen Neustart.
    func testOfflineChangesShowAtOnceAndSurviveARestart() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipIf(environment["COCKPIT_OFFLINE_TEST"] != "1", "nur mit angehaltenem Dienst")
        let extra = ["COCKPIT_URL_SHOPPING": environment["COCKPIT_URL_SHOPPING"] ?? ""]
        var app = start(tab: "shopping", extra: extra)
        let field = app.textFields["newItem"]
        XCTAssertTrue(field.waitForExistence(timeout: 25), "kein Offline-Stand der Liste")
        XCTAssertTrue(app.otherElements["offlineBanner"].waitForExistence(timeout: 10)
                      || app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH 'Offline'")).firstMatch.exists,
                      "keine Offline-Leiste")

        field.tap()
        field.typeText(Self.offlineName + "\n")
        let row = app.staticTexts[Self.offlineName]
        // Sofort - nicht erst nach dem Zeitlimit einer Anfrage.
        XCTAssertTrue(row.waitForExistence(timeout: 3), "der neue Eintrag stand nicht sofort da")
        let cell = app.cells.containing(.staticText, identifier: Self.offlineName).firstMatch
        let toggle = cell.buttons.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        let waiting = NSPredicate(format: "value == %@", "wartet auf Netz")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: waiting, object: toggle)],
                                        timeout: 20), .completed, "keine Uhr am Haken")
        shoot(app, "einkauf-offline")

        app.terminate()
        app = start(tab: "shopping", extra: extra)
        XCTAssertTrue(app.staticTexts[Self.offlineName].waitForExistence(timeout: 25), "nach dem Neustart weg")
        shoot(app, "einkauf-offline-neustart")
    }

    /// Mit laufendem Dienst danach (COCKPIT_OFFLINE_TEST=2): was wartete, geht raus,
    /// die Uhr verschwindet - und der Test raeumt den Eintrag wieder weg.
    func testWaitingChangesArriveWhenTheServiceIsBack() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipIf(environment["COCKPIT_OFFLINE_TEST"] != "2", "nur nach dem Offline-Test, Dienst wieder an")
        let app = start(tab: "shopping", extra: ["COCKPIT_URL_SHOPPING": environment["COCKPIT_URL_SHOPPING"] ?? ""])
        let row = app.staticTexts[Self.offlineName]
        XCTAssertTrue(row.waitForExistence(timeout: 25), "der offline angelegte Eintrag fehlt")
        let cell = app.cells.containing(.staticText, identifier: Self.offlineName).firstMatch
        let toggle = cell.buttons.firstMatch
        let synced = NSPredicate(format: "value == %@", "")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: synced, object: toggle)],
                                        timeout: 30), .completed, "die Uhr blieb")
        shoot(app, "einkauf-wieder-online")
        row.swipeLeft()
        let delete = app.buttons["Löschen"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
    }
}
