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

    /// Die Gegenrichtung - zurueck nach oben.
    ///
    /// Beginnt bei 0,30 und nicht weiter oben: darueber liegt die
    /// Navigationsleiste, und eine Ziehgeste, die dort ansetzt, scrollt
    /// nichts. Der Test sieht dann aus, als waere er unten haengengeblieben -
    /// war er auch.
    private func scrollUp(_ app: XCUIApplication, times: Int = 1) {
        for _ in 0..<times {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
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

    /// Wartet, bis eine Beschriftung wieder einen bestimmten Wert hat.
    private func waitFor(_ element: XCUIElement, toReadAgain text: String) -> Bool {
        let predicate = NSPredicate(format: "label == %@", text)
        let erwartung = expectation(for: predicate, evaluatedWith: element)
        return XCTWaiter.wait(for: [erwartung], timeout: 10) == .completed
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

    private func waitFor(_ element: XCUIElement, toChangeFrom text: String) -> Bool {
        let predicate = NSPredicate(format: "label != %@", text)
        let erwartung = expectation(for: predicate, evaluatedWith: element)
        return XCTWaiter.wait(for: [erwartung], timeout: 10) == .completed
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
        for tab in ["Gewicht", "Essen", "Zugang"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.tabBars.buttons[tab].waitForExistence(timeout: 5))
            shoot(app, "tab-\(tab.lowercased())")
        }
    }
}
