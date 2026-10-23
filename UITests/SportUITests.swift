import XCTest

/// Padel und Gym (seit 23.10. in Sport, vorher Healthy).
final class SportUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Wie `start`, dazu die Umleitung auf einen lokal gestarteten Weight Tracker oder
    /// Padel-Dienst, falls `uitest.sh` sie durchreicht.
    private func launch(tab: String, extra: [String: String] = [:]) -> XCUIApplication {
        let environment = ProcessInfo.processInfo.environment
        var merged = extra
        for key in ["COCKPIT_URL_WEIGHT", "COCKPIT_URL_PADEL"] {
            if let value = environment[key], !value.isEmpty { merged[key] = value }
        }
        return start(tab: tab, extra: merged)
    }

    // MARK: - Gym

    /// Gegen einen lokalen Weight Tracker (`COCKPIT_URL_WEIGHT=http://127.0.0.1:…`,
    /// leerer Datenordner): Tag A ohne, Tag B mit dem heutigen Wochentag anlegen,
    /// an A ein eigenes Geraet mit getipptem Gewicht, an B eines aus der
    /// Geraeteliste, Satz abhaken, Training starten (vorgewaehlt: B, weil heute
    /// sein Wochentag ist), „Satz erledigt“, beenden. Was beim Dienst ankam,
    /// prueft der Aufrufer danach per curl (`/api/gym`).
    func testGymPlanTickAndTraining() throws {
        let url = ProcessInfo.processInfo.environment["COCKPIT_URL_WEIGHT"] ?? ""
        try XCTSkipIf(!url.hasPrefix("http://127.0.0.1"), "nur gegen einen lokalen Weight Tracker")
        let app = launch(tab: "gym")

        let first = app.buttons["gymAddFirstDay"]
        XCTAssertTrue(first.waitForExistence(timeout: 20), "leeres Gym ohne Knopf")
        shoot(app, "gym-leer")
        first.tap()
        addDay(app, "Tag A", weekday: nil)
        app.buttons["gymMenu"].tap()
        app.buttons["Trainingstag anlegen"].tap()
        // ISO-Wochentag von heute (1 = Montag), wie in der App.
        let weekday = (Calendar(identifier: .gregorian).component(.weekday, from: Date()) + 5) % 7 + 1
        addDay(app, "Tag B", weekday: weekday)

        // Tag A: ein eigenes Geraet ueber die Suche.
        let adds = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gymAddExercise-'"))
        XCTAssertTrue(adds.firstMatch.waitForExistence(timeout: 10), "neuer Tag ohne „Gerät hinzufügen“")
        adds.element(boundBy: 0).tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Geraeteauswahl ohne Suche")
        shoot(app, "gym-geraeteliste")
        search.tap()
        search.typeText("Gerät A")
        app.buttons["gymAddNewMachine"].tap()

        // Tag B: das erste aus der Geraeteliste des Dienstes (darueber steht „Gerät A“ als eigenes).
        XCTAssertTrue(adds.firstMatch.waitForExistence(timeout: 10))
        adds.firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gymOwn-'")).firstMatch
            .waitForExistence(timeout: 5), "eigenes Geraet fehlt in der Auswahl")
        let pick = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gymPick-'")).firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 5), "keine Geraeteliste vom Dienst")
        let picked = String(pick.identifier.dropFirst("gymPick-".count))
        shoot(app, "gym-geraeteliste-tag-b")
        pick.tap()
        XCTAssertTrue(app.staticTexts[picked].waitForExistence(timeout: 10), "„\(picked)“ nicht am Tag")

        // Gewicht tippen: am Geraet von Tag A.
        let exercise = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gymExercise-'")).firstMatch
        XCTAssertTrue(exercise.waitForExistence(timeout: 10))
        exercise.tap()
        let weight = app.textFields["gymWeight"]
        XCTAssertTrue(weight.waitForExistence(timeout: 5), "kein Gewichtsfeld")
        weight.tap()
        weight.typeText("37.5")
        app.buttons["gymWeightDone"].tap()
        shoot(app, "gym-gewicht")
        XCTAssertEqual(weight.value as? String, "37,5", "deutsch mit Komma zurueck")
        app.navigationBars.buttons["Fertig"].tap()
        XCTAssertTrue(exercise.waitForExistence(timeout: 5))
        XCTAssertTrue(exercise.label.contains("37,5 kg"), exercise.label)

        let set0 = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'gymSet-' AND identifier ENDSWITH '-0'")).firstMatch
        XCTAssertTrue(set0.waitForExistence(timeout: 10), "Geraet ohne Satz-Kreise")
        set0.tap()
        shoot(app, "gym-abgehakt")
        XCTAssertEqual(set0.value as? String, "erledigt")

        // Heute ist der Wochentag von B - B ist vorgewaehlt, nicht A aus der Reihe.
        XCTAssertTrue(app.buttons["gymDayMenu"].label.contains("Tag B"), app.buttons["gymDayMenu"].label)
        app.buttons["gymStart"].tap()
        let done = app.buttons["gymSetDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "keine Trainingsansicht")
        XCTAssertTrue(app.navigationBars["Tag B"].exists, "Training mit dem falschen Tag")
        done.tap()
        shoot(app, "gym-training")
        scrollDown(app, times: 1)
        app.buttons["gymFinish"].tap()
        XCTAssertTrue(app.buttons["gymStart"].waitForExistence(timeout: 10), "nach „Beenden“ zurueck in der Uebersicht")
        shoot(app, "gym-beendet")
    }

    /// Spanne, Notiz und Wiederholungen je Satz (19.10.) an den Vorfuehrdaten
    /// (`COCKPIT_GYM_DEMO=1`: nur im Speicher, braucht keinen Dienst). Im Blatt
    /// macht „mindestens“ aus 3×10 eine Spanne, die Notiz bleibt nach „Fertig“;
    /// im Training aendert − nur den naechsten Satz, nach dem Haken steht
    /// wieder die obere Grenze da, und der Plan bleibt.
    func testGymRangeNoteAndRepsPerSet() {
        let app = launch(tab: "gym", extra: ["COCKPIT_GYM_DEMO": "1"])

        let row = app.buttons["gymExercise-e-demo-b"]
        XCTAssertTrue(row.waitForExistence(timeout: 20), "keine Vorfuehrdaten")
        XCTAssertTrue(row.label.contains("3×10 · 27,5 kg"), row.label)
        row.tap()
        let lower = app.buttons["mindestens: weniger"]
        XCTAssertTrue(lower.waitForExistence(timeout: 5), "kein „mindestens“ im Blatt")
        lower.tap()
        lower.tap()
        let note = app.descendants(matching: .any)["gymNote"]
        note.tap()
        note.typeText("Sitz 2")
        shoot(app, "gym-blatt-spanne-notiz")
        XCTAssertTrue(reps(app, "mindestens", 8).exists, "„mindestens“ nicht auf 8")
        app.navigationBars.buttons["Fertig"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("3×8–10 · 27,5 kg"), row.label)

        // Wieder offen: die Notiz ist uebernommen; „mindestens“ ganz hoch nimmt die Spanne weg.
        row.tap()
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertEqual(note.value as? String, "Sitz 2")
        let higher = app.buttons["mindestens: mehr"]
        higher.tap()
        higher.tap()
        higher.tap()
        XCTAssertTrue(reps(app, "mindestens", 10).exists, "„mindestens“ geht nicht ueber die obere Grenze")
        app.navigationBars.buttons["Fertig"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("3×10 · 27,5 kg"), row.label)

        // Training mit Tag A (vorgewaehlt ist er nur an seinen Wochentagen): Geraet A
        // hat 8–10 und die Notiz „Sitz 4“.
        app.buttons["gymDayMenu"].tap()
        app.buttons.matching(NSPredicate(format: "label == 'Tag A' AND identifier != 'gymDayMenu'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["gymDayMenu"].label.contains("Tag A"), app.buttons["gymDayMenu"].label)
        app.buttons["gymStart"].tap()
        let done = app.buttons["gymSetDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "keine Trainingsansicht")
        XCTAssertEqual(note.value as? String, "Sitz 4")
        XCTAssertTrue(app.staticTexts["8–10"].exists, "keine Spanne neben „Wiederholungen“")
        app.buttons["Wiederholungen: weniger"].tap()
        XCTAssertTrue(reps(app, "Wiederholungen", 9).exists, "− aendert den Satz nicht")
        shoot(app, "gym-training-spanne")
        done.tap()
        XCTAssertTrue(app.staticTexts["Satz 2 von 3"].waitForExistence(timeout: 5))
        XCTAssertTrue(reps(app, "Wiederholungen", 10).exists, "nach dem Haken nicht wieder die obere Grenze")

        // Die Notiz im Training: tippen, „Fertig“ ueber der Tastatur uebernimmt. Hinter
        // den Text tippen - `tap()` trifft ein Textfeld an seinem Anfang, und der
        // Zusatz landete vorn.
        note.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        note.typeText(" · Lehne 2")
        app.buttons["gymNoteDone"].tap()
        shoot(app, "gym-training-notiz")
        XCTAssertEqual(note.value as? String, "Sitz 4 · Lehne 2")

        scrollDown(app, times: 1)
        app.buttons["gymFinish"].tap()
        let planned = app.buttons["gymExercise-e-demo-a"]
        XCTAssertTrue(planned.waitForExistence(timeout: 10))
        XCTAssertTrue(planned.label.contains("3×8–10 · 40 kg"), "der Plan hat sich geaendert: \(planned.label)")
    }

    /// Die Zahl eines „− n +“: Beschriftung wie die Zeile, Wert die Zahl.
    private func reps(_ app: XCUIApplication, _ label: String, _ value: Int) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@ AND value == %@", label, "\(value)")).firstMatch
    }

    /// Im offenen Tag-Blatt: Name, wahlweise ein Wochentag, „Fertig“.
    private func addDay(_ app: XCUIApplication, _ name: String, weekday: Int?) {
        let field = app.textFields["gymName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(name)
        if let weekday {
            app.buttons["gymWeekday-\(weekday)"].tap()
            shoot(app, "gym-tag")
        }
        app.buttons["gymDayDone"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10), name)
    }

    // MARK: - Padel

    /// Alle Abschnitte des Padel-Tabs an den Vorfuehrdaten (`COCKPIT_PADEL_DEMO=1`, kein Dienst
    /// noetig): naechster Termin mit Countdown, Gebucht, Ergebnisse, Geplant, Serien, Plaetze.
    func testPadelDemoShowsEverySection() {
        let app = launch(tab: "padel", extra: ["COCKPIT_PADEL_DEMO": "1", "COCKPIT_NO_HEALTH": "1"])
        XCTAssertTrue(app.descendants(matching: .any)["padelNext"].waitForExistence(timeout: 20), "kein naechster Termin")
        shoot(app, "padel-1")
        XCTAssertTrue(app.buttons["Einladen"].firstMatch.exists, "kein Einladen an der Buchung")
        for page in 2...5 {
            scrollDown(app, times: 3)
            shoot(app, "padel-\(page)")
        }
        XCTAssertTrue(app.staticTexts["Mo · 18:00 bis 21:30 · 90′"].waitForExistence(timeout: 5), "keine Serie")
        app.buttons["padelAdd"].tap()
        app.buttons["Serie …"].tap()
        XCTAssertTrue(app.navigationBars["Neue Serie"].waitForExistence(timeout: 5))
        shoot(app, "padel-neue-serie")
    }

    func testTabsAreReachable() {
        let app = launch(tab: "padel", extra: ["COCKPIT_GYM_DEMO": "1", "COCKPIT_PADEL_DEMO": "1"])
        XCTAssertTrue(app.navigationBars["Padel"].waitForExistence(timeout: 20))
        for tab in ["Gym", "Padel"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10), tab)
            XCTAssertTrue(app.tabBars.buttons[tab].isSelected, tab)
        }
        shoot(app, "tabs")
    }
}
