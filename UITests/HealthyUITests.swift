import XCTest

/// Dashboard, Essen, Gewicht - und der Tipp auf die Meldung der Schnellerfassung. Die
/// Evaluation wohnt seit 14.10. in Fokus (FokusUITests), das Gym seit 23.10. in Sport
/// (SportUITests).
final class HealthyUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Wie `start`, dazu die Umleitung auf einen lokal gestarteten Weight
    /// Tracker oder Kalorienzaehler, falls `uitest.sh` sie durchreicht.
    private func launch(tab: String, extra: [String: String] = [:]) -> XCUIApplication {
        let environment = ProcessInfo.processInfo.environment
        var merged = extra
        for key in ["COCKPIT_URL_WEIGHT", "COCKPIT_URL_FOOD"] {
            if let value = environment[key], !value.isEmpty { merged[key] = value }
        }
        return start(tab: tab, extra: merged)
    }

    /// Erfundene Recovery und Energie (`DashboardDemo`) - der Simulator
    /// bekommt keine Health-Daten.
    private let demo = ["COCKPIT_DASHBOARD_DEMO": "1"]

    /// Scrollt die Liste des Essen-Tabs ueber ihren Rand links.
    ///
    /// Nicht ueber die Zeilen: Tachos, Mahlzeit-Ueberschriften und
    /// „Hinzufuegen" tragen die Ziehgeste zum Blaettern zwischen Tagen
    /// (`simultaneousGesture`), und unter iOS 26 haelt die das Scrollen der
    /// Liste auf, sobald der Finger dort ansetzt. Welche Zeile unter einem
    /// festen Punkt liegt, haengt vom Tag ab - der Rand links gehoert keiner.
    private func scrollFoodList(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.75))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.3))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    // MARK: - Zugang (seit 10.11.: persoenlicher Token)

    /// Ein iPhone ohne jeden Token: das Blatt fragt nach dem persoenlichen Token,
    /// Felix' Token stehen zugeklappt darunter und gehen erst auf Tipp auf.
    func testSetupOnAFreshPhoneAsksForThePersonalToken() {
        let app = start(tab: "setup", extra: demo.merging([
            "COCKPIT_FH_PRIVATE_TOKEN": "none", "COCKPIT_WEIGHT_TOKEN": "none",
            "COCKPIT_HEALTH_TOKEN": "none",
        ]) { _, neu in neu })
        let field = app.secureTextFields["healthToken"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        shoot(app, "zugang-frisch")
        XCTAssertFalse(app.secureTextFields["privateToken"].exists, "Felix' Token stehen zugeklappt")
        XCTAssertFalse(app.staticTexts["healthAccess"].exists, "ohne Token keine Kopfzeile")

        app.buttons["Besitzer-Token"].firstMatch.tap()
        XCTAssertTrue(app.secureTextFields["privateToken"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["weightToken"].exists)
        shoot(app, "zugang-frisch-besitzer")
    }

    /// Mit persoenlichem Token: nur dessen Feld, die Person in der Kopfzeile.
    /// „Entfernen“ nimmt ihn weg - danach sieht das Blatt aus wie auf einem
    /// frischen iPhone.
    func testSetupAsAPersonShowsOnlyThePersonalToken() {
        let app = start(tab: "setup", extra: demo.merging([
            "COCKPIT_FH_PRIVATE_TOKEN": "none", "COCKPIT_WEIGHT_TOKEN": "none",
            "COCKPIT_HEALTH_TOKEN": "ui-test-person", "COCKPIT_HEALTH_NAME": "person-a",
        ]) { _, neu in neu })
        XCTAssertTrue(app.secureTextFields["healthToken"].waitForExistence(timeout: 10))
        shoot(app, "zugang-person")
        XCTAssertEqual(app.staticTexts["healthAccess"].label.lowercased(), "✓ person-a")
        XCTAssertFalse(app.buttons["Besitzer-Token"].exists)
        XCTAssertFalse(app.secureTextFields["privateToken"].exists)

        app.buttons["Entfernen"].tap()
        XCTAssertTrue(app.buttons["Besitzer-Token"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Entfernen"].exists)
        shoot(app, "zugang-person-entfernt")
    }

    /// Der Weg eines zweiten iPhones von Anfang bis Ende: ohne Zugang geht das
    /// Blatt auf, ein falscher Token wird abgelehnt, der Setup-Link angenommen,
    /// das Blatt schliesst sich und die App zeigt die Daten der Person.
    ///
    /// Laeuft nur gegen **lokal gestartete** Dienste mit einer Testperson
    /// (`COCKPIT_URL_FOOD`, `COCKPIT_URL_WEIGHT`, `COCKPIT_PERSON_TOKEN` =
    /// ihr Token aus `HEALTH_TOKENS`) - sonst ueberspringt er sich.
    func testEnteringAPersonalTokenOpensTheApp() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let token = environment["COCKPIT_PERSON_TOKEN"], !token.isEmpty,
              let food = environment["COCKPIT_URL_FOOD"], !food.isEmpty,
              let weight = environment["COCKPIT_URL_WEIGHT"], !weight.isEmpty else {
            throw XCTSkip("Braucht lokal gestartete Dienste und COCKPIT_PERSON_TOKEN.")
        }
        let fresh = ["COCKPIT_FH_PRIVATE_TOKEN": "none", "COCKPIT_WEIGHT_TOKEN": "none",
                     "COCKPIT_URL_FOOD": food, "COCKPIT_URL_WEIGHT": weight]
        let app = start(tab: "dashboard", extra: fresh.merging(["COCKPIT_HEALTH_TOKEN": "none"]) { _, neu in neu })
        // Ohne jeden Zugang geht das Blatt von selbst auf.
        let field = app.secureTextFields["healthToken"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))

        field.tap()
        field.typeText("kein-gueltiger-token")
        app.buttons["Speichern"].tap()
        let refusal = app.staticTexts["Essen: Kein Zugang – Token prüfen."]
        let refused = refusal.waitForExistence(timeout: 20)
        shoot(app, "zugang-abgelehnt")
        XCTAssertTrue(refused, "ein Token, den der Dienst nicht kennt, darf nicht gespeichert werden")

        // Nach der Absage ist das Feld wieder leer - der Link haengt sich nicht an.
        field.tap()
        field.typeText("\(food)/setup?token=\(token)")
        app.buttons["Speichern"].tap()
        // Angenommen: das Blatt geht zu, das Dashboard laedt als diese Person.
        XCTAssertTrue(field.waitForNonExistence(timeout: 20), "nach dem Speichern geht das Blatt zu")
        XCTAssertTrue(app.staticTexts["Recovery"].waitForExistence(timeout: 15))
        shoot(app, "zugang-angenommen-dashboard")
        XCTAssertFalse(app.staticTexts["Kein Zugang - Token prüfen."].exists)

        // Der Token ueberlebt den Neustart, und das Blatt nennt die Person, wie
        // der Dienst sie meldet. Leer heisst hier: nichts an der Ablage aendern.
        app.terminate()
        let again = start(tab: "setup", extra: fresh.merging(["COCKPIT_HEALTH_TOKEN": ""]) { _, neu in neu })
        XCTAssertTrue(again.staticTexts["healthAccess"].waitForExistence(timeout: 10))
        shoot(again, "zugang-nach-neustart")
        XCTAssertTrue(again.staticTexts["healthAccess"].label.hasPrefix("✓ "))
        XCTAssertFalse(again.buttons["Besitzer-Token"].exists)
    }

    /// Felix' iPhone: das Blatt von vorher, ohne das neue Feld.
    func testSetupWithOwnerTokensIsAsBefore() {
        let app = start(tab: "setup", extra: demo)
        XCTAssertTrue(app.secureTextFields["privateToken"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.secureTextFields["weightToken"].exists)
        XCTAssertFalse(app.secureTextFields["healthToken"].exists)
        XCTAssertFalse(app.buttons["Besitzer-Token"].exists)
        shoot(app, "zugang-besitzer")
    }

    // MARK: - Dashboard

    /// Ohne Vorgabe macht die App im Dashboard auf (Felix, 09.10.).
    func testAppOpensOnTheDashboard() {
        let app = launch(tab: "")
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 20))
        shoot(app, "dashboard-start")
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].isSelected)
    }

    /// Jede Karte fuehrt dorthin, wo das Einzelne steht: Recovery auf ihre
    /// Seite, Energie in den Essen-Tab mit heute, Gewicht in seinen Tab.
    func testDashboardCardsLeadToTheirPlaces() {
        let app = launch(tab: "dashboard", extra: demo)
        let recovery = app.buttons["recoveryCard"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 20))
        shoot(app, "dashboard-demo")
        recovery.tap()
        XCTAssertTrue(app.navigationBars["Recovery"].waitForExistence(timeout: 10))
        shoot(app, "recovery-top")
        scrollDown(app, times: 3)
        _ = app.descendants(matching: .any).matching(identifier: "hrvChart").firstMatch.waitForExistence(timeout: 5)
        shoot(app, "recovery-hrv")
        XCTAssertTrue(app.staticTexts["Atemfrequenz"].exists)
        app.navigationBars["Recovery"].buttons.firstMatch.tap()

        let energy = app.buttons["energyCard"]
        XCTAssertTrue(energy.waitForExistence(timeout: 10))
        energy.tap()
        XCTAssertTrue(app.navigationBars["Heute"].waitForExistence(timeout: 10))
        shoot(app, "dashboard-energie-essen")
        XCTAssertTrue(app.tabBars.buttons["Essen"].isSelected)

        app.tabBars.buttons["Dashboard"].tap()
        let weight = app.buttons["weightCard"]
        XCTAssertTrue(weight.waitForExistence(timeout: 10))
        weight.tap()
        XCTAssertTrue(app.navigationBars["Gewicht"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Gewicht"].isSelected)
    }

    /// Eiweiss von heute steht seit 10.11. in der Essen-Kachel des Dashboards,
    /// mit Farbpunkt (in der Vorfuehrung 150 von 180 g bei Erhalt 130 - gelb).
    func testDashboardShowsTodaysProtein() {
        let app = launch(tab: "dashboard", extra: demo)
        let protein = app.descendants(matching: .any).matching(identifier: "dashboardProtein").firstMatch
        XCTAssertTrue(protein.waitForExistence(timeout: 20))
        shoot(app, "dashboard-eiweiss")
        XCTAssertEqual(protein.label, "Eiweiß 150/180 g")
    }

    /// Die Strain-Karte (seit 10.11.) zeigt den Stand von heute gegen das Ziel
    /// (in der Vorfuehrung 12,4 bei Ziel 14,1) und oeffnet das Fenster mit dem
    /// Verlauf: vier Zeitraeume, darunter die Form-Kurve. Aufgenommen hell und
    /// dunkel - der Simulator bekommt keinen Puls, anders ist das nie zu sehen.
    func testStrainCardOpensTheWindow() {
        XCUIDevice.shared.appearance = .light
        addTeardownBlock { XCUIDevice.shared.appearance = .light }
        let app = launch(tab: "dashboard", extra: demo)
        let card = app.buttons["strainCard"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        shoot(app, "dashboard-strain-hell")
        XCTAssertTrue(card.label.contains("12,4"), card.label)
        XCTAssertTrue(card.label.contains("Ziel 14,1"), card.label)

        card.tap()
        XCTAssertTrue(app.navigationBars["Strain"].waitForExistence(timeout: 10))
        // Der Zeitraum wird gemerkt - der Test beginnt und endet bei sechs Wochen.
        app.buttons["6 Wo."].tap()
        let chart = app.descendants(matching: .any).matching(identifier: "strainChart").firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        shoot(app, "strain-6-wochen-hell")
        XCTAssertTrue(app.staticTexts["Form"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "formChart").firstMatch.exists)

        for (title, name) in [("3 Mon.", "3-monate"), ("6 Mon.", "6-monate"), ("1 Jahr", "1-jahr")] {
            app.buttons[title].tap()
            XCTAssertTrue(chart.waitForExistence(timeout: 10))
            shoot(app, "strain-\(name)-hell")
        }

        XCUIDevice.shared.appearance = .dark
        shoot(app, "strain-1-jahr-dunkel")
        app.buttons["6 Wo."].tap()
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        // Ein Tipp ins Diagramm zeigt die Sprechblase des Tages - nur im Bild
        // zu pruefen: was in einem Diagramm steht, kennt der Testlaeufer nicht.
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()
        shoot(app, "strain-6-wochen-dunkel-sprechblase")

        app.buttons["Fertig"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        shoot(app, "dashboard-strain-dunkel")
    }

    /// Das Ziele-Blatt hat seit 10.11. unter „Eiweiß“ den Erhalt, und das
    /// Gewicht-Menue die Koerpergroesse - beide kommen vom Dienst.
    func testSheetsOfferProteinFloorAndHeight() {
        var app = launch(tab: "food", extra: demo)
        let foodMenu = app.navigationBars.buttons["foodMenu"].firstMatch
        XCTAssertTrue(foodMenu.waitForExistence(timeout: 20))
        foodMenu.tap()
        app.buttons["Tagesziele …"].tap()
        XCTAssertTrue(app.staticTexts["Eiweiß Erhalt (g)"].waitForExistence(timeout: 10))
        shoot(app, "ziele-blatt-erhalt")
        app.terminate()

        app = launch(tab: "weight", extra: demo)
        let weightMenu = app.navigationBars.buttons["weightMenu"].firstMatch
        XCTAssertTrue(weightMenu.waitForExistence(timeout: 20))
        weightMenu.tap()
        app.buttons["Größe …"].tap()
        let field = app.textFields["heightField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        shoot(app, "groesse-blatt")
        XCTAssertEqual(field.value as? String, "188")
    }

    /// Das Logbook im Dashboard (seit 12.10.): gestern ist halb beantwortet und
    /// hat den Punkt, jeder Tipp speichert, ein zweiter Tipp auf die gewaehlte
    /// Antwort macht die Zeile wieder offen, der Zaehler zaehlt weiter. Sind alle
    /// Zeilen beantwortet, ist der Punkt weg. Mit erfundenen Werten - nichts davon
    /// erreicht den Dienst.
    func testLogbookAnswersSaveOnTap() {
        let app = launch(tab: "logbook", extra: demo)
        let yes = app.buttons["logbook-yes-b-demo-b"]
        XCTAssertTrue(yes.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Gestern, offen"].exists, "gestern ist noch offen")
        shoot(app, "logbook-gestern")

        yes.tap()
        XCTAssertTrue(yes.isSelected)
        yes.tap()
        XCTAssertFalse(yes.isSelected, "ein zweiter Tipp macht die Zeile wieder offen")

        let plus = app.buttons["logbook-plus-b-demo-c"]
        plus.tap()
        plus.tap()
        XCTAssertTrue(waitFor(app.buttons["logbook-amount-b-demo-c"], toReadAgain: "Verhalten C: 5"))

        yes.tap()
        app.buttons["logbook-no-b-demo-d"].tap()
        XCTAssertTrue(app.buttons["Gestern"].waitForExistence(timeout: 5), "alles beantwortet - kein Punkt mehr")
        shoot(app, "logbook-beantwortet")

        app.buttons["Heute"].tap()
        XCTAssertTrue(waitFor(app.buttons["logbook-amount-b-demo-c"], toReadAgain: "Verhalten C: 1"))
        app.buttons["Tag davor"].tap()
        app.buttons["Tag davor"].tap()
        XCTAssertTrue(app.buttons["Tag danach"].waitForExistence(timeout: 5), "vor gestern: mit Datum und ›")
        shoot(app, "logbook-vorgestern")

        scrollDown(app, times: 2)
        let all = app.buttons["logbookAllEffects"]
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        shoot(app, "logbook-effekte")
        all.tap()
        shoot(app, "logbook-alle-effekte")

        scrollUp(app, times: 2)
        app.buttons["Verhalten"].tap()
        XCTAssertTrue(app.navigationBars["Verhalten"].waitForExistence(timeout: 5))
        shoot(app, "logbook-verhalten")
        XCTAssertTrue(app.staticTexts["Verhalten E"].exists, "archivierte stehen unten")
    }

    // MARK: - Essen ohne Netz (Runde 4)

    private static let offlineDish = "Offline-Gericht"

    /// Nur mit angehaltenem Kalorienzaehler (COCKPIT_OFFLINE_TEST=food-offline) und
    /// einem Tag im Offline-Stand (vorher einmal online geladen): der Eintrag steht
    /// sofort da, mit Uhr, die Summen sind „vorläufig“ - auch nach einem Neustart.
    func testOfflineFoodShowsAtOnceProvisionally() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["COCKPIT_OFFLINE_TEST"] != "food-offline",
                      "nur mit angehaltenem Kalorienzaehler")
        var app = launch(tab: "food")
        let add = app.buttons["Hinzufügen"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 25), "kein Offline-Stand des Tages")
        add.tap()
        let toggle = app.switches["Gericht neu anlegen"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(Self.offlineDish)
        // Die Zahlenfelder stehen rechtsbuendig in ihrer Zeile - dort antippen, nicht in der Mitte.
        // Alle vier Werte je 100 g - ohne sie nimmt der Kalorienzaehler kein Gericht.
        for (label, value) in [("kcal / 100 g", "200"), ("Eiweiß / 100 g", "10"), ("Kohlenhydrate / 100 g", "20"),
                               ("Fett / 100 g", "5"), ("Gramm", "150")] {
            let field = app.textFields[label]
            XCTAssertTrue(field.waitForExistence(timeout: 5), label)
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
            field.typeText(value)
        }
        app.buttons["Eintragen"].tap()

        // Sofort - nicht erst nach dem Zeitlimit einer Anfrage.
        XCTAssertTrue(app.staticTexts[Self.offlineDish].waitForExistence(timeout: 3), "stand nicht sofort da")
        XCTAssertTrue(app.staticTexts["foodProvisional"].waitForExistence(timeout: 5), "Summen nicht vorläufig")
        XCTAssertTrue(app.images["wartet auf Netz"].waitForExistence(timeout: 20), "keine Uhr am Eintrag")
        shoot(app, "essen-offline")

        // Ein Gewicht von Hand: steht sofort als „… – wartet“ unter den Kacheln.
        app.tabBars.buttons["Gewicht"].tap()
        let plus = app.buttons["Messwert eintragen"]
        XCTAssertTrue(plus.waitForExistence(timeout: 15))
        plus.tap()
        let kg = app.textFields["kg"]
        XCTAssertTrue(kg.waitForExistence(timeout: 5))
        kg.tap()
        kg.typeText("82,4")
        app.buttons["Sichern"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["pendingWeight"].waitForExistence(timeout: 5),
                      "kein wartendes Gewicht")
        shoot(app, "gewicht-offline")

        app.terminate()
        app = launch(tab: "food")
        XCTAssertTrue(app.staticTexts[Self.offlineDish].waitForExistence(timeout: 25), "nach dem Neustart weg")
        XCTAssertTrue(app.staticTexts["foodProvisional"].exists)
        shoot(app, "essen-offline-neustart")
    }

    /// Danach mit laufendem Kalorienzaehler (COCKPIT_OFFLINE_TEST=food-online): der
    /// Eintrag geht raus, die Uhr und „vorläufig“ verschwinden - dann raeumt der
    /// Test ihn wieder weg.
    func testWaitingFoodArrivesWhenTheServiceIsBack() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["COCKPIT_OFFLINE_TEST"] != "food-online",
                      "nur nach dem Offline-Test, Dienst wieder an")
        let app = launch(tab: "food")
        let row = app.staticTexts[Self.offlineDish]
        XCTAssertTrue(row.waitForExistence(timeout: 25), "der offline eingetragene Eintrag fehlt")
        XCTAssertTrue(app.staticTexts["foodConsumed"].waitForExistence(timeout: 30), "„vorläufig“ blieb")
        XCTAssertFalse(app.images["wartet auf Netz"].exists, "die Uhr blieb")
        shoot(app, "essen-wieder-online")
        // Das Gewicht ist auch raus, sofern ein Weight Tracker laeuft.
        if ProcessInfo.processInfo.environment["COCKPIT_URL_WEIGHT"]?.isEmpty == false {
            app.tabBars.buttons["Gewicht"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["pendingWeight"].waitForNonExistence(timeout: 30),
                          "das Gewicht wartet noch")
            shoot(app, "gewicht-wieder-online")
            app.tabBars.buttons["Essen"].tap()
        }
        let entry = app.descendants(matching: .any).matching(identifier: "foodEntry")
            .containing(.staticText, identifier: Self.offlineDish).firstMatch
        entry.swipeLeft()
        let delete = app.buttons["Löschen"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 10))
    }

    /// Unter dem Verlauf: die Schalter brechen um, „Verbrauch ⌀" ist dabei
    /// und vorgewaehlt - unterhalb des ersten Bildschirms, den
    /// `run-simulator.sh` allein zeigt.
    func testFoodHistoryOffersTheExpenditure() {
        let app = launch(tab: "food", extra: demo)
        XCTAssertTrue(app.staticTexts["Frühstück"].waitForExistence(timeout: 20))
        let chip = app.buttons["Verbrauch ⌀"]
        for _ in 0..<12 where !chip.isHittable {
            scrollFoodList(app)
        }
        shoot(app, "essen-verlauf-verbrauch")
        XCTAssertTrue(chip.isHittable, "„Verbrauch ⌀“ steht bei den Schaltern")
        XCTAssertTrue(app.buttons["Gewicht täglich"].isHittable, "kein Schalter hinter dem Rand")
    }

    /// „Defizit Tag" steht hinter „Defizit ⌀" und ist aus; angetippt liegt der
    /// Tageswert blass hinter dem Mittel (Felix, 23.10.). Einen Debug-Schalter
    /// fuer die Kurven im Verlauf gibt es nicht - antippen kann nur der Test.
    func testFoodHistoryOffersTheDailyDeficit() {
        let app = launch(tab: "food", extra: demo)
        XCTAssertTrue(app.staticTexts["Frühstück"].waitForExistence(timeout: 20))
        let chip = app.buttons["Defizit Tag"]
        for _ in 0..<12 where !chip.isHittable {
            scrollFoodList(app)
        }
        XCTAssertTrue(chip.isHittable, "„Defizit Tag“ steht bei den Schaltern")
        shoot(app, "essen-verlauf-defizit-tag-aus")
        chip.tap()
        shoot(app, "essen-verlauf-defizit-tag")
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
        // zeigt der Simulator keine Benachrichtigung. Start im Dashboard: der
        // Tipp muss in den Essen-Tab fuehren, die Meldung hat keine Art.
        let app = launch(tab: "dashboard", extra: ["COCKPIT_ASK_PUSH": "1"])
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
        XCTAssertTrue(app.tabBars.buttons["Essen"].isSelected, "eine Meldung ohne Art fuehrt in den Essen-Tab")
    }

    func testWeightTabShowsStepsCardBelowTheChart() {
        let app = launch(tab: "weight")
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
        let app = launch(tab: "food")
        XCTAssertTrue(app.staticTexts["Frühstück"].waitForExistence(timeout: 20))

        let history = app.staticTexts["Verlauf"]
        for _ in 0..<10 where !history.isHittable {
            scrollFoodList(app)
        }

        _ = history.waitForExistence(timeout: 5)
        shoot(app, "essen-verlauf")
        XCTAssertTrue(app.staticTexts["Verlauf"].exists,
                      "Der Verlauf muss unterhalb der Mahlzeiten erreichbar sein")
    }

    /// Der Verlauf geht bis 180 Tage zurueck: vier Zeitraeume nebeneinander,
    /// und der laengste laesst sich waehlen.
    func testFoodHistoryOffersHalfAYear() {
        let app = launch(tab: "food")
        XCTAssertTrue(app.staticTexts["Frühstück"].waitForExistence(timeout: 20))

        // Am Rand der Liste scrollen (`scrollFoodList`). Die Liste baut den
        // Verlauf erst, wenn er ins Bild kommt - deshalb scrollen, bis der
        // Umschalter da ist.
        let halfYear = app.buttons["180 Tage"]
        for _ in 0..<10 where !halfYear.isHittable {
            scrollFoodList(app)
        }
        XCTAssertTrue(halfYear.waitForExistence(timeout: 5))
        halfYear.tap()
        // Das Diagramm laedt nach - kurz Zeit lassen, sonst zeigt das Bild
        // noch die 30 Tage.
        sleep(3)
        scrollFoodList(app)
        shoot(app, "essen-verlauf-180")
        XCTAssertTrue(halfYear.isSelected)
    }

    /// Wischt einen Eintrag an, ohne zu loeschen: die Muelltonne muss
    /// erscheinen, und zwar ohne das Wort daneben.
    func testSwipeOnAnEntryRevealsTheTrashButton() throws {
        let app = launch(tab: "food")
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
        let app = launch(tab: "food")
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

    /// Weit zurueckgeblaettert: „Heute“ steht sichtbar in der Leiste und
    /// bringt mit einem Tipp zurueck (Felix, 14.10.). Mit Vorfuehrdaten, damit
    /// das Bild keine echten Mahlzeiten zeigt.
    func testTodayButtonJumpsBackFromWeeksAgo() {
        let weeksAgo = CalendarDateForTests.daysAgo(35)
        let app = launch(tab: "food", extra: demo.merging(["COCKPIT_DAY": weeksAgo]) { $1 })
        let today = app.buttons["todayButton"]
        XCTAssertTrue(today.waitForExistence(timeout: 20), "ohne „Heute“ in der Leiste")
        shoot(app, "essen-vor-fuenf-wochen")
        today.tap()
        _ = app.navigationBars["Heute"].waitForExistence(timeout: 10)
        shoot(app, "essen-heute")
        XCTAssertTrue(app.navigationBars["Heute"].exists)
        XCTAssertFalse(app.buttons["todayButton"].exists, "an heute verschwindet der Knopf")
    }

    func testTabsAreReachable() {
        let app = launch(tab: "dashboard")
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 20))
        for tab in ["Essen", "Gewicht", "Dashboard"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10), tab)
            XCTAssertTrue(app.tabBars.buttons[tab].isSelected, tab)
        }
        shoot(app, "tabs")
    }
}

/// Ein Tag als `yyyy-MM-dd` fuer `COCKPIT_DAY` - der Testlaeufer kennt
/// `CalendarDate` nicht (es liegt in der App).
private enum CalendarDateForTests {
    static func daysAgo(_ days: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 2026, parts.month ?? 1, parts.day ?? 1)
    }
}
