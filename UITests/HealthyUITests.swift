import XCTest

/// Essen und Gewicht - und der Tipp auf die Meldung der Schnellerfassung.
final class HealthyUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
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

    func testWeightTabShowsStepsCardBelowTheChart() {
        let app = start(tab: "weight")
        XCTAssertTrue(app.staticTexts["Gewicht"].waitForExistence(timeout: 20))

        // Erst warten, bis der Inhalt vollstaendig steht. Wischt man frueher,
        // scrollt die Liste zwar - aber sobald die Daten nachkommen, aendert
        // sich die Inhaltshoehe und sie springt zurueck nach oben. Das Bild
        // sieht dann aus, als haette der Wisch gar nicht stattgefunden.
        // Auf die Beschriftung IN der Karte pruefen, nicht auf die Karte
        // selbst: ein Accessibility-Container ist nie „hittable", egal ob er
        // im Bild steht. Danach zu fragen liefert immer falsch - und der Test
        // meldet einen Fehler, den es nicht gibt.
        let karte = app.staticTexts["stepsValue"]
        XCTAssertTrue(karte.waitForExistence(timeout: 20),
                      "Die Schritte-Karte muss unter dem Diagramm stehen")

        // Ueber den Kacheln wischen, nicht ueber dem Diagramm: dort liegt die
        // Ziehgeste zum Werte-Ablesen, und `app.swipeUp()` setzt in der
        // Bildmitte an - also mitten auf dem Diagramm.
        // Begrenzt: eine Schleife ohne Obergrenze laeuft in einem UI-Test bis
        // ins Zeitlimit und meldet dann nichts Brauchbares.
        for _ in 0..<6 where !karte.isHittable {
            scrollDown(app)
        }
        // Erst aufnehmen, dann pruefen: schlaegt die Pruefung fehl, endet der
        // Test sofort - und ohne Bild weiss man nur, DASS etwas nicht stimmt,
        // nicht was. Genau so ist der erste Anlauf ausgegangen.
        shoot(app, "gewicht-schritte")
        XCTAssertTrue(karte.exists, "Die Schritte-Karte muss unter dem Diagramm stehen")
        // `exists` allein reicht nicht: ein Element ausserhalb des Bildes
        // existiert auch. Genau daran ist der erste Anlauf vorbeigelaufen -
        // gruen, und auf dem Bild war die Karte angeschnitten.
        XCTAssertTrue(karte.isHittable,
                      "Die Karte muss nach dem Scrollen wirklich sichtbar sein")
    }

    func testFoodTabShowsHistoryBelowTheMeals() {
        let app = start(tab: "food")
        XCTAssertTrue(app.staticTexts["Frühstück"].waitForExistence(timeout: 20))

        scrollDown(app, times: 6)

        _ = app.staticTexts["Verlauf"].waitForExistence(timeout: 5)
        shoot(app, "essen-verlauf")
        XCTAssertTrue(app.staticTexts["Verlauf"].exists,
                      "Der Verlauf muss unterhalb der Mahlzeiten erreichbar sein")
    }

    /// Wischt einen Eintrag an, ohne zu loeschen: die Muelltonne muss
    /// erscheinen, und zwar ohne das Wort daneben.
    func testSwipeOnAnEntryRevealsTheTrashButton() throws {
        let app = start(tab: "food")
        XCTAssertTrue(app.staticTexts["Frühstück"].waitForExistence(timeout: 20))

        // Ueber die Kennung und nicht ueber die Position: `cells[1]` war die
        // Tacho-Karte, und der Wisch ging ins Leere - der Test war gruen, das
        // Bild zeigte nichts.
        let ersterEintrag = app.descendants(matching: .any)
            .matching(identifier: "foodEntry").firstMatch
        guard ersterEintrag.waitForExistence(timeout: 10) else {
            throw XCTSkip("Kein Eintrag zum Wischen - heute ist noch nichts erfasst.")
        }
        ersterEintrag.swipeLeft()

        shoot(app, "essen-wischen")
        // Der Knopf traegt "Löschen" als Beschriftung fuer VoiceOver, zeigt
        // aber nur das Symbol. Genau das soll er.
        XCTAssertTrue(app.buttons["Löschen"].waitForExistence(timeout: 3))
    }

    func testTabsAreReachable() {
        let app = start(tab: "food")
        for tab in ["Gewicht", "Essen"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10), tab)
        }
        shoot(app, "tabs")
    }
}
