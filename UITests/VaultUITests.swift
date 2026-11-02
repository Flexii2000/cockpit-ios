import XCTest

/// Noten hinter der Sperre - und der Tipp auf "Neue Note".
final class VaultUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Der Noten-Tab, von oben bis unten.
    ///
    /// Braucht einen erreichbaren Notendienst **und** ein Passwort. Beides
    /// steht nicht im Schluesselbund - das Passwort ist Felix' Anmeldung, kein
    /// Dienstgeheimnis. Der Test ueberspringt sich deshalb, wenn die
    /// Umgebungsvariablen fehlen; wie man ihn laufen laesst, steht im Kopf von
    /// `tools/run-simulator.sh`.
    func testGradesTabFromTopToBottom() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipIf((environment["COCKPIT_GRADES_TOKEN"] ?? "").isEmpty,
                      "Kein Noten-Zugang in der Umgebung - siehe tools/run-simulator.sh")

        let app = start(tab: "grades", extra: gradesEnvironment(environment))

        let note = app.staticTexts["finalGrade"]
        XCTAssertTrue(note.waitForExistence(timeout: 25), "Abschlussnote fehlt")
        clearAssumptions(app)
        shoot(app, "noten-oben")

        // Bis zu den offenen Modulen und dem Fussteil. Begrenzt, nicht als
        // while-Schleife: eine unbegrenzte lief schon einmal in die
        // 600-Sekunden-Grenze des ganzen Laufs.
        for _ in 0..<8 {
            scrollDown(app)
        }
        shoot(app, "noten-unten")
        XCTAssertTrue(app.staticTexts["Wie gerechnet wird"].exists
                      || app.staticTexts["Fortschritt"].exists,
                      "Weder Fortschritt noch Rechenregel im Bild")
    }

    /// Eine angenommene Note aendert die Abschlussnote - und nur sie.
    ///
    /// Der eine Weg, der nicht nur anzeigt, sondern etwas schickt: die
    /// Annahme geht an den Server, der rechnet sie in die Szenarien ein.
    func testAssumptionChangesTheFinalGrade() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipIf((environment["COCKPIT_GRADES_TOKEN"] ?? "").isEmpty,
                      "Kein Noten-Zugang in der Umgebung - siehe tools/run-simulator.sh")

        let app = start(tab: "grades", extra: gradesEnvironment(environment))
        let note = app.staticTexts["finalGrade"]
        XCTAssertTrue(note.waitForExistence(timeout: 25))
        clearAssumptions(app)
        let vorher = note.label

        // Bis zu den offenen Modulen - die stehen unten, sie haben noch keine
        // Note.
        for _ in 0..<8 {
            scrollDown(app)
        }
        let auswahl = app.buttons["assumptionPicker"].firstMatch
        XCTAssertTrue(auswahl.waitForExistence(timeout: 10), "Kein offenes Modul gefunden")
        auswahl.tap()
        let vierNull = app.buttons["4,0"].firstMatch
        XCTAssertTrue(vierNull.waitForExistence(timeout: 5), "Notenauswahl kam nicht")
        vierNull.tap()

        scrollUp(app, times: 8)
        // Erst aufnehmen, dann pruefen: schlaegt die Pruefung fehl, endet der
        // Test sofort - und ohne Bild weiss man nur, DASS etwas nicht stimmt.
        shoot(app, "noten-mit-annahme")
        XCTAssertTrue(app.buttons["Verwerfen"].waitForExistence(timeout: 10),
                      "Ohne Verwerfen-Knopf ist die Annahme nicht angekommen")
        // Eine 4,0 kann die Abschlussnote nur verschlechtern - bliebe sie
        // gleich, waere die Annahme nicht eingerechnet worden.
        XCTAssertNotEqual(note.label, vorher, "Abschlussnote unveraendert")

        app.buttons["Verwerfen"].tap()
        XCTAssertTrue(waitFor(note, toReadAgain: vorher),
                      "Nach dem Verwerfen muss wieder \(vorher) dastehen")
    }

    /// Ein Tipp auf eine Benachrichtigung darf die App nicht umbringen.
    ///
    /// Die Benachrichtigung kommt von aussen (`xcrun simctl push`), nicht aus
    /// dem Test - der wartet nur darauf. Deshalb nur mit COCKPIT_PUSH_TEST=1,
    /// sonst ueberspringt er sich; wie man ihn faehrt, steht in
    /// tools/pushtest.sh.
    func testTappingAPushNotificationDoesNotCrashTheApp() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["COCKPIT_PUSH_TEST"] != "1",
                      "nur mit tools/pushtest.sh")
        // Erlaubnis erfragen lassen und den Systemdialog wegtippen - ohne sie
        // zeigt der Simulator keine Benachrichtigung.
        let app = start(tab: "food", extra: ["COCKPIT_ASK_PUSH": "1"])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"].exists ? springboard.buttons["Allow"]
                                                         : springboard.buttons["Erlauben"]
        if allow.waitForExistence(timeout: 10) { allow.tap() }
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 20))
        XCUIDevice.shared.press(.home)

        // Der Titel kommt aus der Nutzlast, die tools/pushtest.sh schickt.
        let title = ProcessInfo.processInfo.environment["COCKPIT_PUSH_TITLE"] ?? "Vorschlag ist fertig"
        let banner = springboard.staticTexts[title]
        XCTAssertTrue(banner.waitForExistence(timeout: 90), "keine Benachrichtigung angekommen")
        shoot(app, "push-banner")
        banner.tap()

        // Der Tipp bringt die App nach vorn - oder eben nicht.
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15),
                      "App laeuft nach dem Tipp nicht im Vordergrund (Zustand \(app.state.rawValue))")
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground, "App ist nach dem Tipp weg")
        shoot(app, "push-getippt")
    }

    /// Der Cloud-Tab von oben bis unten, hell und dunkel, samt aufgeklappter Posten -
    /// erst AWS, darunter Verda, wenn der Dienst es liefert.
    ///
    /// Nur lesend - gegen den lokal gestarteten Dienst `../cloud-usage` oder einen
    /// Schein-Server (`COCKPIT_URL_CLOUD`); ohne die Variable ueberspringt er sich.
    func testCloudTabFromTopToBottom() throws {
        let app = try startCloud()
        for appearance in [XCUIDevice.Appearance.light, .dark] {
            XCUIDevice.shared.appearance = appearance
            let suffix = appearance == .dark ? "dunkel" : "hell"
            sleep(1)
            shoot(app, "cloud-oben-\(suffix)")
            // Eine Kategorie aufklappen - ihre Posten.
            let llm = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'LLM'")).firstMatch
            if llm.exists, !app.staticTexts["EC2-Rechenzeit"].exists { llm.tap() }
            scrollDown(app, times: 2)
            shoot(app, "cloud-posten-\(suffix)")
            scrollDown(app, times: 3)
            shoot(app, "cloud-laeuft-\(suffix)")
            scrollDown(app, times: 4)
            shoot(app, "cloud-vormonate-\(suffix)")
            scrollDown(app, times: 4)
            shoot(app, "cloud-verda-\(suffix)")
            scrollDown(app, times: 4)
            shoot(app, "cloud-verda-unten-\(suffix)")
            scrollUp(app, times: 17)
        }
        XCUIDevice.shared.appearance = .light
        XCTAssertTrue(app.staticTexts["Vormonate"].exists || app.staticTexts["Kategorien"].exists,
                      "Tab nicht vollstaendig")
    }

    /// Budget aendern: Dialog, Betrag, neuer Stand vom Dienst.
    ///
    /// ⚠️ Schickt `PUT /api/budget` - beim echten Dienst aendert das das AWS-Budget.
    /// Deshalb nur mit `COCKPIT_CLOUD_STUB=1` gegen den Schein-Server (Budget 50 $,
    /// ausgegeben 41,37 $; nach 60 $ stehen dort 69 %).
    func testChangingTheAWSBudget() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["COCKPIT_CLOUD_STUB"] != "1",
                      "Nur gegen den Schein-Server (COCKPIT_CLOUD_STUB=1)")
        let app = try startCloud()
        // Der erste Budget-Knopf ist der von AWS - der von Verda steht weiter unten.
        let budget = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Budget'")).firstMatch
        XCTAssertTrue(budget.waitForExistence(timeout: 5), "Kein Budget-Knopf")
        budget.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Kein Budget-Dialog")
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "60")
        shoot(app, "cloud-budget-dialog")
        app.alerts.buttons["Speichern"].tap()
        let percent = app.staticTexts["69\u{00A0}%"]
        let arrived = percent.waitForExistence(timeout: 10)
        shoot(app, "cloud-budget-60")
        XCTAssertTrue(arrived, "Neuer Stand nach dem Budget kam nicht")
    }

    /// Startet Vault im Cloud-Tab gegen `COCKPIT_URL_CLOUD` - nie gegen den Server.
    private func startCloud() throws -> XCUIApplication {
        let url = ProcessInfo.processInfo.environment["COCKPIT_URL_CLOUD"] ?? ""
        try XCTSkipIf(url.isEmpty || url.contains("fherrmann.com"),
                      "Nur gegen einen lokalen Dienst - siehe tools/run-simulator.sh")
        // Die Noten-Variablen nur, damit das Zugang-Blatt nicht ueber dem Tab aufgeht.
        let app = start(tab: "cloud", extra: [
            "COCKPIT_URL_CLOUD": url,
            "COCKPIT_GRADES_TOKEN": "x", "COCKPIT_GRADES_USER": "x", "COCKPIT_GRADES_PASSWORD": "x",
        ])
        XCTAssertTrue(app.staticTexts["Kategorien"].waitForExistence(timeout: 20), "Kein Stand")
        return app
    }

    /// Raeumt Annahmen aus einem frueheren Lauf weg.
    ///
    /// Sie ueberleben den Neustart der App (sie liegen in den UserDefaults) -
    /// und ein Test, der gegen eine Abschlussnote misst, in der schon eine
    /// Annahme steckt, misst gegen den falschen Wert. Genau daran ist der
    /// Test beim zweiten Lauf gescheitert, nicht an der App.
    private func clearAssumptions(_ app: XCUIApplication) {
        let verwerfen = app.buttons["Verwerfen"]
        guard verwerfen.exists else { return }
        verwerfen.tap()
        let weg = expectation(for: NSPredicate(format: "exists == false"),
                              evaluatedWith: verwerfen)
        _ = XCTWaiter.wait(for: [weg], timeout: 10)
    }

    /// Der Noten-Zugang aus der Umgebung, fuer beide Noten-Tests.
    private func gradesEnvironment(_ environment: [String: String]) -> [String: String] {
        [
            "COCKPIT_URL_GRADES": environment["COCKPIT_URL_GRADES"] ?? "",
            "COCKPIT_GRADES_TOKEN": environment["COCKPIT_GRADES_TOKEN"] ?? "",
            "COCKPIT_GRADES_USER": environment["COCKPIT_GRADES_USER"] ?? "",
            "COCKPIT_GRADES_PASSWORD": environment["COCKPIT_GRADES_PASSWORD"] ?? "",
            // Im Simulator ist kein Gesicht hinterlegt; ohne das bliebe der
            // Sperrbildschirm stehen und der Test saehe nie eine Note.
            "COCKPIT_NO_LOCK": "1",
        ]
    }
}
