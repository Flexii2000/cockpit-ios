import XCTest

/// Was der Simulator allein nicht kann: tippen, wischen, scrollen.
///
/// Der Anlass steht in docs/STAND.md - mehrere Stellen waren gebaut, aber nie
/// angesehen, weil sie unterhalb des Bildschirms lagen oder hinter einer
/// Geste. Von hier aus geht beides.
final class CockpitUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: - Start

    /// Startet die App mit Zugang und ohne Systemdialoge.
    ///
    /// Die drei Schalter sind kein Beiwerk: den Health-Dialog kann
    /// `addUIInterruptionMonitor` nicht verlaesslich wegklicken (er ist kein
    /// Springboard-Alert), Face ID kann XCUITest gar nicht bedienen, und ohne
    /// den dritten meldet jeder Lauf eine Push-Kennung beim food-Backend an.
    private func start(tab: String, extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        let environment = ProcessInfo.processInfo.environment
        app.launchEnvironment = [
            "COCKPIT_FH_PRIVATE_TOKEN": environment["COCKPIT_FH_PRIVATE_TOKEN"] ?? "",
            "COCKPIT_WEIGHT_TOKEN": environment["COCKPIT_WEIGHT_TOKEN"] ?? "",
            "COCKPIT_TAB": tab,
            "COCKPIT_NO_HEALTH": "1",
            "COCKPIT_NO_PUSH": "1",
        ].merging(extra) { _, neu in neu }
        app.launch()
        return app
    }


    /// Wischt von oberhalb der Bildmitte nach oben.
    ///
    /// Zwei Wege, die beide nicht taugen: `element.swipeUp()` wischt nur
    /// innerhalb des Rahmens des Elements - bei einer Beschriftung sind das
    /// dreissig Punkte, zu wenig zum Scrollen. Und `app.swipeUp()` setzt in
    /// der Bildmitte an, also mitten auf dem Diagramm, wo die Ziehgeste zum
    /// Werte-Ablesen liegt.
    private func scrollDown(_ app: XCUIApplication, times: Int = 1) {
        for _ in 0..<times {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    /// Legt einen Screenshot ab.
    ///
    /// `.keepAlways` ist der Punkt: die Vorgabe ist `.deleteOnSuccess`, und
    /// bei gruenen Testlaeufen wirft Xcode alles weg. Der Lauf meldet dann
    /// Erfolg und das Verzeichnis ist leer - der stillste aller stillen
    /// Fehler.
    private func shoot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Tests

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
        for tab in ["Gewicht", "Essen", "Zugang"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout: 5))
            shoot(app, "tab-\(tab.lowercased())")
        }
    }
}
