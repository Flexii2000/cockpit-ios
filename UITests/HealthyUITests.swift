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

    /// Wechselt hell/dunkel und wartet den Uebergang ab - ein Bild direkt
    /// danach zeigte sonst ein Zwischending (helle Flaeche, weisse Uhrzeit).
    private func appearance(_ style: XCUIDevice.Appearance) {
        XCUIDevice.shared.appearance = style
        Thread.sleep(forTimeInterval: 1.2)
    }

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

    /// Das Dashboard seit 10.11. (Vertrag §5): oben das Morgen-Briefing, unter
    /// Gewicht und Essen die Kacheln „Serien“ und „Eichung“, ganz unten der
    /// Wochenrueckblick - und in der Leiste der Chat. Hell und dunkel, mit den
    /// erfundenen Werten der Vorfuehrung.
    func testDashboardShowsBriefingTilesAndWeekReview() {
        XCUIDevice.shared.appearance = .light
        addTeardownBlock { XCUIDevice.shared.appearance = .light }
        let app = launch(tab: "dashboard", extra: demo)
        let briefing = app.descendants(matching: .any).matching(identifier: "briefingCard").firstMatch
        XCTAssertTrue(briefing.waitForExistence(timeout: 20))
        shoot(app, "dashboard-oben-hell")
        XCTAssertTrue(briefing.label.contains("Recovery 72 %"), briefing.label)
        XCTAssertTrue(app.buttons["chatButton"].exists, "der Chat ist in der Vorfuehrung freigeschaltet")
        appearance(.dark)
        shoot(app, "dashboard-oben-dunkel")
        appearance(.light)

        let streaks = app.buttons["streaksCard"]
        for _ in 0..<8 where !streaks.isHittable { scrollDown(app) }
        // Noch ein Stueck: die Kacheln sollen ueber der Tab-Leiste stehen.
        scrollDown(app)
        shoot(app, "dashboard-serien-eichung-hell")
        XCTAssertTrue(streaks.label.contains("23 Tage"), streaks.label)
        XCTAssertTrue(streaks.label.contains("12 Tage · Person A"), streaks.label)
        let calibration = app.descendants(matching: .any).matching(identifier: "calibrationCard").firstMatch
        XCTAssertTrue(calibration.label.contains("rollend 0,92"), calibration.label)
        XCTAssertTrue(calibration.label.contains("gemessen 0,96 ± 0,03"), calibration.label)
        appearance(.dark)
        shoot(app, "dashboard-serien-eichung-dunkel")
        appearance(.light)

        // Der Rueckblick steht ganz unten, unter Logbook und Effekten.
        let title = app.staticTexts["Wochenrückblick"]
        for _ in 0..<30 where !title.isHittable { scrollDown(app) }
        scrollDown(app, times: 2)
        shoot(app, "dashboard-wochenrueckblick-hell")
        XCTAssertTrue(title.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "weekReviewCard").firstMatch.exists)
        XCTAssertTrue(app.staticTexts["02.11.–08.11."].exists || app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "\\d{2}\\.\\d{2}\\.–\\d{2}\\.\\d{2}\\.")).firstMatch.exists)
        appearance(.dark)
        shoot(app, "dashboard-wochenrueckblick-dunkel")
    }

    /// Die Serien-Kachel fuehrt in den Freunde-Tab: je Freund eine Karte, mit
    /// „+“ ein Code. Entfernen ueber langes Druecken - ohne Freunde stehen nur
    /// die beiden Knoepfe da (Vertrag §10.4).
    func testStreaksCardOpensFriends() {
        XCUIDevice.shared.appearance = .light
        addTeardownBlock { XCUIDevice.shared.appearance = .light }
        let app = launch(tab: "dashboard", extra: demo)
        let streaks = app.buttons["streaksCard"]
        XCTAssertTrue(streaks.waitForExistence(timeout: 20))
        for _ in 0..<8 where !streaks.isHittable { scrollDown(app) }
        streaks.tap()
        XCTAssertTrue(app.navigationBars["Freunde"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Freunde"].isSelected)
        XCTAssertTrue(app.staticTexts["Person A"].waitForExistence(timeout: 10))
        shoot(app, "freunde-hell")
        XCTAssertTrue(app.staticTexts["Person B"].exists)
        XCTAssertTrue(app.staticTexts["Tracking"].firstMatch.exists)
        appearance(.dark)
        shoot(app, "freunde-dunkel")
        appearance(.light)

        // Der Stupser: danach ist er fuer heute vergeben.
        let nudge = app.buttons["nudge-f-demo-a"]
        XCTAssertTrue(nudge.isEnabled)
        nudge.tap()
        let spent = expectation(for: NSPredicate(format: "isEnabled == false"), evaluatedWith: nudge)
        XCTAssertEqual(XCTWaiter.wait(for: [spent], timeout: 10), .completed)

        // „+“ → Code erstellen: der Code gross, darunter Teilen.
        app.buttons["friendsAdd"].tap()
        app.buttons["Code erstellen"].tap()
        let code = app.staticTexts["inviteCode"]
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        shoot(app, "freunde-code-erstellen")
        XCTAssertEqual(code.label, "K7Q4-M2XD")
        app.buttons["Fertig"].tap()

        // „+“ → Code eingeben: erst mit einem ganzen Code geht der Knopf an.
        app.buttons["friendsAdd"].tap()
        app.buttons["Code eingeben"].tap()
        let field = app.textFields["friendCode"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Hinzufügen"].isEnabled)
        field.tap()
        field.typeText("k7q4m2xd")
        shoot(app, "freunde-code-eingeben")
        XCTAssertTrue(app.buttons["Hinzufügen"].isEnabled)
        app.buttons["Abbrechen"].tap()

        // Entfernen ueber langes Druecken, mit Rueckfrage - bis keiner mehr da ist.
        for name in ["Person A", "Person B"] {
            let title = app.staticTexts[name]
            XCTAssertTrue(title.waitForExistence(timeout: 10))
            title.press(forDuration: 1.2)
            let remove = app.buttons["Entfernen"]
            XCTAssertTrue(remove.waitForExistence(timeout: 10), name)
            remove.tap()
            // Erst die Rueckfrage abwarten - ihr Knopf heisst wie der im Menue.
            XCTAssertTrue(app.staticTexts["\(name) entfernen?"].waitForExistence(timeout: 10), name)
            let confirm = app.buttons["Entfernen"].firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 10), name)
            shoot(app, "freunde-entfernen-\(name.suffix(1))")
            confirm.tap()
            let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: title)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, name)
        }
        XCTAssertTrue(app.buttons["friendsCreate"].waitForExistence(timeout: 10))
        shoot(app, "freunde-leer-hell")
        XCTAssertTrue(app.buttons["friendsEnter"].exists)
        appearance(.dark)
        shoot(app, "freunde-leer-dunkel")
    }

    /// Der Knopf in der Leiste oeffnet den Chat (Vertrag §8.2): eigene Fragen
    /// rechts, Antworten links, eine laeuft noch - solange ist das Senden aus.
    /// „Neuer Chat“ leert ihn nach Rueckfrage.
    func testChatButtonOpensTheChat() {
        XCUIDevice.shared.appearance = .light
        addTeardownBlock { XCUIDevice.shared.appearance = .light }
        let app = launch(tab: "dashboard", extra: demo)
        let button = app.buttons["chatButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        button.tap()
        XCTAssertTrue(app.navigationBars["Chat"].waitForExistence(timeout: 10))
        let answer = app.staticTexts.matching(identifier: "chatAnswer").firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 10))
        shoot(app, "chat-hell")
        XCTAssertEqual(app.staticTexts.matching(identifier: "chatQuestion").count, 3)
        XCTAssertEqual(app.staticTexts.matching(identifier: "chatAnswer").count, 2)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "chatProgress").firstMatch.exists)
        XCTAssertFalse(app.buttons["chatSend"].isEnabled, "solange eine Antwort laeuft")
        appearance(.dark)
        shoot(app, "chat-dunkel")
        appearance(.light)

        app.buttons["chatNew"].tap()
        let confirm = app.buttons["Chat leeren"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        shoot(app, "chat-neu-rueckfrage")
        confirm.tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: answer)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
        shoot(app, "chat-leer")
        XCTAssertFalse(app.buttons["chatNew"].isEnabled, "ein leerer Chat ist schon neu")

        // Eine Frage tippen: der Knopf geht an, die Frage steht sofort da.
        let input = app.textFields["chatInput"].exists ? app.textFields["chatInput"] : app.textViews["chatInput"]
        input.tap()
        input.typeText("Wie viel Eiweiß fehlt mir noch?")
        XCTAssertTrue(app.buttons["chatSend"].isEnabled)
        app.buttons["chatSend"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier: "chatQuestion").firstMatch.waitForExistence(timeout: 10))
        shoot(app, "chat-frage-gestellt")
        app.buttons["Fertig"].tap()
        XCTAssertTrue(button.waitForExistence(timeout: 10))
    }

    /// `COCKPIT_TAB=chat` stellt die Bitte um den Chat, bevor es das Dashboard
    /// gibt - derselbe Weg wie der Tipp auf „Deine Antwort ist da.“ beim
    /// Kaltstart (`Router.takeChatRequest`). Das Blatt geht mit dem Dashboard auf.
    func testChatRequestBeforeTheDashboardOpensTheChat() {
        let app = launch(tab: "chat", extra: demo)
        XCTAssertTrue(app.navigationBars["Chat"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts.matching(identifier: "chatAnswer").firstMatch.waitForExistence(timeout: 10))
        shoot(app, "chat-bitte-vor-dem-dashboard")
        app.buttons["Fertig"].tap()
        XCTAssertTrue(app.buttons["chatButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].isSelected)
        // Bedient ist bedient: der Chat geht nicht von selbst wieder auf.
        app.tabBars.buttons["Essen"].tap()
        app.tabBars.buttons["Dashboard"].tap()
        XCTAssertTrue(app.buttons["chatButton"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Chat"].exists)
    }

    /// Briefing, Chat und Freunde gegen **lokal gestartete Dienste mit einer
    /// Agent-Attrappe** (`COCKPIT_URL_WEIGHT`, `COCKPIT_URL_FOOD`,
    /// `COCKPIT_CHAT_TEST=1`). Nie gegen den echten Server: dort startete jede
    /// Frage eine Claude-Sitzung auf Felix' Kontingent - deshalb ueberspringt
    /// sich der Test ohne den Schalter und ohne eine Schleifenadresse.
    func testBriefingChatAndFriendsAgainstLocalServices() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["COCKPIT_CHAT_TEST"] == "1",
              let weight = environment["COCKPIT_URL_WEIGHT"],
              weight.contains("127.0.0.1") || weight.contains("localhost") else {
            throw XCTSkip("Braucht einen lokal gestarteten Weight Tracker mit Agent-Attrappe und COCKPIT_CHAT_TEST=1.")
        }
        let app = launch(tab: "dashboard")
        // Das Briefing wird nach dem Abgleich angefordert und erscheint, sobald
        // die Sitzung fertig ist (nachgefragt wird alle fuenf Sekunden).
        let briefing = app.descendants(matching: .any).matching(identifier: "briefingCard").firstMatch
        XCTAssertTrue(briefing.waitForExistence(timeout: 60))
        shoot(app, "lokal-dashboard-oben")

        let button = app.buttons["chatButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        button.tap()
        XCTAssertTrue(app.navigationBars["Chat"].waitForExistence(timeout: 10))
        // Was von frueheren Laeufen dasteht, weg - der Test beginnt leer.
        let new = app.buttons["chatNew"]
        if new.waitForExistence(timeout: 5), new.isEnabled {
            new.tap()
            XCTAssertTrue(app.buttons["Chat leeren"].waitForExistence(timeout: 10))
            app.buttons["Chat leeren"].tap()
            let emptied = expectation(for: NSPredicate(format: "isEnabled == false"), evaluatedWith: new)
            XCTAssertEqual(XCTWaiter.wait(for: [emptied], timeout: 15), .completed)
        }
        let input = app.textFields["chatInput"].exists ? app.textFields["chatInput"] : app.textViews["chatInput"]
        input.tap()
        input.typeText("Was sollte ich heute noch essen?")
        app.buttons["chatSend"].tap()
        let progress = app.descendants(matching: .any).matching(identifier: "chatProgress").firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 10), "die Frage steht da, die Antwort laeuft")
        shoot(app, "lokal-chat-laeuft")
        XCTAssertFalse(app.buttons["chatSend"].isEnabled)
        let answer = app.staticTexts.matching(identifier: "chatAnswer").firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 60), "die Antwort kommt ueber die Abfrage")
        shoot(app, "lokal-chat-antwort")
        XCTAssertFalse(progress.exists)
        app.buttons["Fertig"].tap()

        // Die Kacheln unten und der Rueckblick aus echten Antworten.
        let streaks = app.buttons["streaksCard"]
        XCTAssertTrue(streaks.waitForExistence(timeout: 20))
        for _ in 0..<8 where !streaks.isHittable { scrollDown(app) }
        scrollDown(app)
        shoot(app, "lokal-dashboard-serien-eichung")
        for _ in 0..<30 where !app.staticTexts["Wochenrückblick"].isHittable { scrollDown(app) }
        scrollDown(app, times: 2)
        shoot(app, "lokal-dashboard-wochenrueckblick")
        XCTAssertTrue(app.staticTexts["Wochenrückblick"].exists)

        app.tabBars.buttons["Freunde"].tap()
        XCTAssertTrue(app.navigationBars["Freunde"].waitForExistence(timeout: 10))
        // Entweder Karten oder - ohne Freunde - die beiden Knoepfe.
        let anyFriend = app.staticTexts["Tracking"].firstMatch
        let empty = app.buttons["friendsCreate"]
        var shown = false
        for _ in 0..<40 where !shown {
            shown = anyFriend.exists || empty.exists
            if !shown { Thread.sleep(forTimeInterval: 0.5) }
        }
        XCTAssertTrue(shown)
        shoot(app, "lokal-freunde")
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
        // Wohin der Tipp fuehrt, sagt die Art der Meldung (`HealthyRoute.notification`);
        // tools/pushtest.sh liest sie aus der Nutzlast.
        switch ProcessInfo.processInfo.environment["COCKPIT_PUSH_KIND"] ?? "" {
        case "chat-answer":
            XCTAssertTrue(app.navigationBars["Chat"].waitForExistence(timeout: 10),
                          "„Deine Antwort ist da.“ oeffnet den Chat")
            XCTAssertTrue(app.tabBars.buttons["Dashboard"].isSelected)
        case "friend-nudge", "streak-warning":
            XCTAssertTrue(app.navigationBars["Freunde"].waitForExistence(timeout: 10),
                          "Stupser und Serien-Warnung fuehren zu den Freunden")
            XCTAssertTrue(app.tabBars.buttons["Freunde"].isSelected)
        default:
            XCTAssertTrue(app.tabBars.buttons["Essen"].isSelected, "eine Meldung ohne Art fuehrt in den Essen-Tab")
        }
    }

    /// „Deine Antwort ist da.“ erscheint nicht als Banner, solange der Chat
    /// offen ist - die Antwort steht dann schon da (Vertrag §8.2). Jede andere
    /// Meldung erscheint, und ihr Tipp fuehrt weg vom Chat: das Blatt macht Platz.
    ///
    /// Die Meldungen kommen von aussen (`tools/pushtest.sh Healthy --chat-open`):
    /// erst `chat-answer`, zehn Sekunden spaeter ein Stupser als Gegenprobe. Der
    /// Test wartet auf die zweite und darf die erste bis dahin nie gesehen haben
    /// - ohne die Gegenprobe bewiese ein leerer Bildschirm nichts.
    func testChatAnswerShowsNoBannerWhileTheChatIsOpen() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipIf(environment["COCKPIT_PUSH_TEST"] != "chat-open",
                      "nur mit tools/pushtest.sh Healthy --chat-open")
        // `chat` oeffnet den Chat ueber den Weg des Kaltstarts: die Bitte steht
        // da, bevor es das Dashboard gibt.
        let app = launch(tab: "chat", extra: demo.merging(["COCKPIT_ASK_PUSH": "1"]) { _, neu in neu })
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"].exists ? springboard.buttons["Allow"]
                                                         : springboard.buttons["Erlauben"]
        if allow.waitForExistence(timeout: 10) { allow.tap() }
        XCTAssertTrue(app.navigationBars["Chat"].waitForExistence(timeout: 20))

        let answer = springboard.staticTexts["Deine Antwort ist da."]
        let control = springboard.staticTexts[environment["COCKPIT_PUSH_TITLE"] ?? "Person A"]
        var sawAnswer = false
        let deadline = Date().addingTimeInterval(150)
        while Date() < deadline, !control.exists {
            if answer.exists { sawAnswer = true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertTrue(control.exists, "die Gegenprobe kam nicht an - ohne sie beweist der Lauf nichts")
        shoot(app, "push-chat-offen-gegenprobe")
        XCTAssertFalse(sawAnswer || answer.exists, "bei offenem Chat darf „Deine Antwort ist da.“ kein Banner sein")
        XCTAssertTrue(app.navigationBars["Chat"].exists, "der Chat steht noch offen")

        control.tap()
        XCTAssertTrue(app.navigationBars["Freunde"].waitForExistence(timeout: 10),
                      "der Tipp auf den Stupser fuehrt zu den Freunden")
        XCTAssertTrue(app.tabBars.buttons["Freunde"].isSelected)
        let chatGone = expectation(for: NSPredicate(format: "exists == false"),
                                   evaluatedWith: app.navigationBars["Chat"])
        XCTAssertEqual(XCTWaiter.wait(for: [chatGone], timeout: 10), .completed, "der Chat macht Platz")
        shoot(app, "push-chat-offen-freunde")
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
        // Seit 10.11. vier Tabs: die Freunde als letzter.
        for tab in ["Essen", "Gewicht", "Freunde", "Dashboard"] {
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
