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

    /// Der Verlauf geht bis 180 Tage zurueck: vier Zeitraeume nebeneinander,
    /// und der laengste laesst sich waehlen.
    func testFoodHistoryOffersHalfAYear() {
        let app = start(tab: "food")
        XCTAssertTrue(app.staticTexts["Frühstück"].waitForExistence(timeout: 20))

        // Unterhalb der Ringe ansetzen: dort liegt die Liste, nicht der
        // Pager mit den Tagen. Die Liste baut den Verlauf erst, wenn er ins
        // Bild kommt - deshalb scrollen, bis der Umschalter da ist.
        let halfYear = app.buttons["180 Tage"]
        for _ in 0..<10 where !halfYear.isHittable {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(halfYear.waitForExistence(timeout: 5))
        halfYear.tap()
        // Das Diagramm laedt nach - kurz Zeit lassen, sonst zeigt das Bild
        // noch die 30 Tage.
        sleep(3)
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40))
        start.press(forDuration: 0.05, thenDragTo: end)
        shoot(app, "essen-verlauf-180")
        XCTAssertTrue(halfYear.isSelected)
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

    /// Ein Wisch nach links ueber den Tachos blaettert auf morgen - dieselbe
    /// Regel wie der Pfeil. Der einzige Ort, an dem sich die Geste pruefen
    /// laesst: simctl kann nicht wischen.
    func testSwipingLeftOnTheGaugesShowsTheNextDay() {
        let app = start(tab: "food")
        XCTAssertTrue(app.staticTexts["Frühstück"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.navigationBars["Heute"].waitForExistence(timeout: 10))

        // Ueber den Tachos ansetzen, knapp unter der Leiste: dort liegt die
        // Geste. Weiter unten kaemen Eintragszeilen (wischen loescht) oder das
        // Diagramm (wischen liest Werte ab).
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.22))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.22))
        start.press(forDuration: 0.05, thenDragTo: end)

        // Erst aufnehmen, dann pruefen.
        _ = app.navigationBars["Morgen"].waitForExistence(timeout: 10)
        shoot(app, "essen-gewischt")
        XCTAssertTrue(app.navigationBars["Morgen"].exists,
                      "Nach dem Wisch nach links muss „Morgen“ in der Leiste stehen")
    }

    // MARK: - Evaluation

    /// Ein Jahr erfundener Antworten (nur im Speicher): Antworten oben, darunter
    /// Linien, je Frage eine Heatmap und die Zusammenhaenge - unterhalb des
    /// ersten Bildschirms, den `run-simulator.sh` allein zeigt.
    func testEvaluationShowsAnswersChartAndHeatmaps() {
        let app = start(tab: "evaluation", extra: ["COCKPIT_EVALUATION_DEMO": "1"])
        XCTAssertTrue(app.staticTexts["Frage A"].firstMatch.waitForExistence(timeout: 15))
        shoot(app, "evaluation-top")

        let three = app.buttons.matching(identifier: "3").firstMatch
        three.tap()
        XCTAssertTrue(three.isSelected, "die getippte Zahl ist gesetzt")
        three.tap()
        XCTAssertFalse(three.isSelected, "noch einmal nimmt sie zurueck")

        app.buttons["14 Tage"].tap()
        scrollDown(app, times: 2)
        shoot(app, "evaluation-fortnight")
        scrollUp(app, times: 3)

        app.buttons["1 Jahr"].tap()
        scrollDown(app, times: 2)
        shoot(app, "evaluation-year-heatmaps")
        scrollDown(app, times: 3)
        XCTAssertTrue(app.staticTexts["Zusammenhänge"].waitForExistence(timeout: 5))
        shoot(app, "evaluation-correlations")
        scrollDown(app, times: 4)
        shoot(app, "evaluation-bottom")
    }

    /// Ohne Fragen: festlegen, eine beantworten - mit einer frischen Datei je
    /// Lauf (`COCKPIT_EVALUATION_SCRATCH`), damit nichts liegen bleibt.
    func testEvaluationQuestionsCanBeSetUp() {
        let app = start(tab: "evaluation", extra: ["COCKPIT_EVALUATION_SCRATCH": "1"])
        let setUp = app.buttons["Fragen festlegen"]
        XCTAssertTrue(setUp.waitForExistence(timeout: 15))
        shoot(app, "evaluation-empty")
        setUp.tap()

        let field = app.textFields["Frage"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Frage X")
        shoot(app, "evaluation-questions-sheet")
        app.buttons["Fertig"].tap()

        XCTAssertTrue(app.staticTexts["Frage X"].firstMatch.waitForExistence(timeout: 5))
        let seven = app.buttons.matching(identifier: "7").firstMatch
        seven.tap()
        XCTAssertTrue(seven.isSelected)
        shoot(app, "evaluation-answered")
    }

    func testTabsAreReachable() {
        let app = start(tab: "food")
        for tab in ["Gewicht", "Evaluation", "Essen"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10), tab)
        }
        shoot(app, "tabs")
    }
}
