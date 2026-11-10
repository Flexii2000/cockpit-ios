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

    // MARK: - Rezepte (nur gegen einen lokalen Dienst mit Agent-Attrappe)

    /// Vom Chat bis zum Kochen: Vorschlag ansehen, speichern, Portionen aendern, auf
    /// die Liste, kochen - mit Bildern hell und dunkel.
    ///
    /// Nur gegen einen lokal gestarteten Dienst (`COCKPIT_URL_SHOPPING` auf
    /// 127.0.0.1) mit `tools/recipe-agent-stub.sh` statt der Claude-Session (der
    /// Kopf des Skripts zeigt den Aufruf): der Test legt ein Rezept und Eintraege
    /// an, und am echten Dienst kostete jede Frage eine Session. `COCKPIT_RECIPE`
    /// nennt das Rezept, das die Attrappe vorschlaegt („Ofenpasta mit Feta und
    /// Tomaten“) - ein gleichnamiges vom letzten Lauf raeumt der Test vorher weg.
    func testRecipeFromChatToCooking() throws {
        let environment = ProcessInfo.processInfo.environment
        let url = environment["COCKPIT_URL_SHOPPING"] ?? ""
        try XCTSkipIf(!url.contains("127.0.0.1") && !url.contains("localhost"), "nur gegen einen lokalen Dienst")
        let recipe = try XCTUnwrap(environment["COCKPIT_RECIPE"].flatMap { $0.isEmpty ? nil : $0 },
                                   "COCKPIT_RECIPE fehlt: der Name des Rezepts, das die Attrappe vorschlaegt")
        let app = start(tab: "shopping", extra: ["COCKPIT_URL_SHOPPING": url])

        let recipes = app.buttons["recipes"]
        XCTAssertTrue(recipes.waitForExistence(timeout: 25), "Liste nicht geladen")
        recipes.tap()
        XCTAssertTrue(app.navigationBars["Rezepte"].waitForExistence(timeout: 10))
        // Vom letzten Lauf: derselbe Name liesse das Speichern scheitern (409).
        let leftover = app.staticTexts[recipe]
        if leftover.waitForExistence(timeout: 3) {
            leftover.swipeLeft()
            app.buttons["Löschen"].firstMatch.tap()
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: leftover)
            XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "altes Rezept blieb stehen")
        }
        shootBoth(app, "rezepte-liste")

        // Chat: fragen, Vorschlag ansehen, speichern.
        let openChat = app.buttons["openChat"]
        XCTAssertTrue(openChat.waitForExistence(timeout: 10), "kein Chat - ist die Person freigeschaltet und der Agent eingerichtet?")
        openChat.tap()
        let fresh = app.buttons["newChat"]
        XCTAssertTrue(fresh.waitForExistence(timeout: 10))
        if fresh.isEnabled { fresh.tap() }
        let field = app.descendants(matching: .any)["chatField"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("Etwas mit Pasta und Feta")
        app.buttons["sendChat"].tap()
        shoot(app, "rezepte-chat-wartet")
        let view = app.buttons["viewDraft"]
        XCTAssertTrue(view.waitForExistence(timeout: 40), "kein Vorschlag vom Agenten")
        XCTAssertTrue(app.staticTexts[recipe].exists, "der Vorschlag heisst anders als COCKPIT_RECIPE")
        shootBoth(app, "rezepte-chat")

        view.tap()
        let save = app.buttons["saveDraftSheet"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "das Blatt mit dem Entwurf ging nicht auf")
        shoot(app, "rezepte-entwurf")
        save.tap()
        let saved = app.buttons["openSavedRecipe"]
        XCTAssertTrue(saved.waitForExistence(timeout: 15), "der Entwurf wurde nicht gespeichert")
        shoot(app, "rezepte-chat-gespeichert")
        saved.tap()

        // Rezept: eine Portion mehr, auf die Liste.
        let stepper = app.steppers["portions"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 10), "das Rezept ging nicht auf")
        shootBoth(app, "rezepte-rezept")
        // Das Blatt zum Bearbeiten - nur ansehen, nichts aendern.
        app.buttons["editRecipe"].tap()
        XCTAssertTrue(app.buttons["saveRecipe"].waitForExistence(timeout: 10), "das Blatt zum Bearbeiten ging nicht auf")
        shoot(app, "rezepte-bearbeiten")
        scrollDown(app, times: 2)
        shoot(app, "rezepte-bearbeiten-unten")
        app.buttons["Abbrechen"].tap()
        XCTAssertTrue(stepper.waitForExistence(timeout: 10))
        let before = app.staticTexts["2 Portionen"].exists
        stepper.buttons.element(boundBy: 1).tap()
        if before {
            XCTAssertTrue(app.staticTexts["3 Portionen"].waitForExistence(timeout: 5), "der Portionswaehler zaehlt nicht")
        }
        shoot(app, "rezepte-rezept-mehr")
        app.buttons["addRecipe"].tap()
        shoot(app, "rezepte-auf-der-liste")

        // Kochen: das Gericht landet bei Healthy (wenn der lokale Dienst einen Kalorienzaehler kennt).
        app.buttons["cook"].tap()
        XCTAssertTrue(app.buttons["cookIngredient-0"].waitForExistence(timeout: 10), "die Kochansicht ging nicht auf")
        _ = app.descendants(matching: .any)["healthyMarks"].firstMatch.waitForExistence(timeout: 10)
        app.buttons["cookIngredient-0"].tap()
        shootBoth(app, "rezepte-kochen")

        // Zurueck auf der Liste stehen die Zutaten - ohne Vorrat.
        for _ in 0..<4 {
            let back = app.navigationBars.buttons.firstMatch
            if app.textFields["newItem"].exists { break }
            if back.exists { back.tap() }
        }
        XCTAssertTrue(app.textFields["newItem"].waitForExistence(timeout: 10), "nicht zurueck auf der Liste")
        shoot(app, "rezepte-liste-danach")
    }

    /// Ein Rezept von Hand: anlegen mit Portionen, die Portionen wieder leeren (der
    /// leere Wert loescht beim Dienst), loeschen. Nur gegen einen lokalen Dienst -
    /// die Rezepte teilen sich zwei Handys.
    func testRecipeCanBeCreatedEditedAndDeleted() throws {
        let environment = ProcessInfo.processInfo.environment
        let url = environment["COCKPIT_URL_SHOPPING"] ?? ""
        try XCTSkipIf(!url.contains("127.0.0.1") && !url.contains("localhost"), "nur gegen einen lokalen Dienst")
        let app = start(tab: "shopping", extra: ["COCKPIT_URL_SHOPPING": url])
        let recipes = app.buttons["recipes"]
        XCTAssertTrue(recipes.waitForExistence(timeout: 25), "Liste nicht geladen")
        recipes.tap()

        let name = "UI-Rezept \(Int(Date().timeIntervalSince1970))"
        app.buttons["newRecipe"].tap()
        let nameField = app.textFields["recipeName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "das Blatt fuer ein neues Rezept ging nicht auf")
        nameField.tap()
        nameField.typeText(name)
        let portions = app.textFields["recipePortions"]
        portions.tap()
        portions.typeText("2")
        let ingredient = app.textFields["newIngredient"]
        ingredient.tap()
        ingredient.typeText("Reis 200g\n")
        shoot(app, "rezept-neu")
        app.buttons["saveRecipe"].tap()

        let row = app.staticTexts[name]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "das Rezept steht nicht in der Liste")
        row.tap()
        XCTAssertTrue(app.steppers["portions"].waitForExistence(timeout: 10), "das Rezept hat keine Portionen")
        XCTAssertTrue(app.staticTexts["200 g"].exists, "die Menge aus dem Namen wurde nicht abgetrennt")
        app.steppers["portions"].buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["300 g"].waitForExistence(timeout: 5), "die Menge rechnet nicht mit")

        // Portionen leeren: beim Dienst loescht nur der leere Wert (0), ein fehlendes Feld bliebe.
        app.buttons["editRecipe"].tap()
        let field = app.textFields["recipePortions"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        // Ganz rechts antippen: die Zahl steht rechtsbuendig, und ein Tipp in die
        // Mitte setzte den Cursor davor - die Loeschtaste taete dann nichts.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.999, dy: 0.5)).tap()
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(field.value as? String, "–", "das Feld ist nicht leer (es zeigt den Platzhalter)")
        app.buttons["saveRecipe"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: app.steppers["portions"])
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "die Portionen blieben stehen")
        XCTAssertTrue(app.staticTexts["200 g"].waitForExistence(timeout: 5), "ohne Portionen gelten die gespeicherten Mengen")
        shoot(app, "rezept-ohne-portionen")

        // Aufraeumen.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.swipeLeft()
        app.buttons["Löschen"].firstMatch.tap()
        let deleted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: row)
        XCTAssertEqual(XCTWaiter().wait(for: [deleted], timeout: 10), .completed, "das Rezept blieb stehen")
    }

    /// Dasselbe Bild hell und dunkel - der Wechsel braucht einen Augenblick zum Neuzeichnen.
    private func shootBoth(_ app: XCUIApplication, _ name: String) {
        shoot(app, name)
        XCUIDevice.shared.appearance = .dark
        Thread.sleep(forTimeInterval: 0.8)
        shoot(app, name + "-dunkel")
        XCUIDevice.shared.appearance = .light
        Thread.sleep(forTimeInterval: 0.8)
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

    /// Ein Rezept fuer drei statt zwei Portionen auf die Liste, waehrend der Dienst
    /// steht (COCKPIT_OFFLINE_TEST=1). Im Offline-Stand muss das Rezept der Attrappe
    /// liegen (`COCKPIT_RECIPE`, zwei Portionen, 250 g Penne - vorher
    /// `testRecipeFromChatToCooking` laufen lassen): die Zutaten stehen sofort da,
    /// mit den Mengen, die die App selbst umgerechnet hat. Nur gegen einen lokalen Dienst.
    func testARecipeGoesOnTheListWithoutNetwork() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipIf(environment["COCKPIT_OFFLINE_TEST"] != "1", "nur mit angehaltenem Dienst")
        let url = environment["COCKPIT_URL_SHOPPING"] ?? ""
        try XCTSkipIf(!url.contains("127.0.0.1") && !url.contains("localhost"), "nur gegen einen lokalen Dienst")
        let recipe = try XCTUnwrap(environment["COCKPIT_RECIPE"].flatMap { $0.isEmpty ? nil : $0 })
        let app = start(tab: "shopping", extra: ["COCKPIT_URL_SHOPPING": url])
        let recipes = app.buttons["recipes"]
        XCTAssertTrue(recipes.waitForExistence(timeout: 25), "kein Offline-Stand der Liste")
        recipes.tap()
        XCTAssertFalse(app.buttons["openChat"].waitForExistence(timeout: 3), "ohne Netz gibt es keinen Chat")
        let row = app.staticTexts[recipe]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "das Rezept fehlt im Offline-Stand")
        row.tap()
        let stepper = app.steppers["portions"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 10))
        stepper.buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["3 Portionen"].waitForExistence(timeout: 5))
        app.buttons["addRecipe"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.textFields["newItem"].waitForExistence(timeout: 10), "nicht zurueck auf der Liste")
        // Sofort - nicht erst nach dem Zeitlimit einer Anfrage.
        XCTAssertTrue(app.staticTexts["Penne"].waitForExistence(timeout: 3), "die Zutaten standen nicht sofort da")
        XCTAssertTrue(app.staticTexts["375 g"].exists, "die Menge ist nicht umgerechnet")
        shoot(app, "einkauf-rezept-offline")
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
