import XCTest

/// Die Hauptablaeufe von coHabit gegen einen lokal gestarteten Dienst mit
/// Demo-Daten (tools/uitest.sh coHabit, COCKPIT_URL_COHABIT und die Token
/// zweier Personen): anlegen, mit Foto aus der Galerie abhaken, chatten,
/// eine Einladung annehmen.
///
/// Was ein Test braucht, legt er vorher selbst ueber die API an - mit einem
/// Namen, den es nur einmal gibt. So laeuft jeder Test auch ein zweites Mal
/// und unabhaengig von den anderen.
final class CohabitUITests: XCTestCase {

    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var baseURL: String { environment["COCKPIT_URL_COHABIT"] ?? "" }
    private var token: String { environment["COCKPIT_COHABIT_TOKEN"] ?? "" }
    private var otherToken: String { environment["COCKPIT_COHABIT_OTHER_TOKEN"] ?? "" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipIf(baseURL.isEmpty || token.isEmpty,
                      "COCKPIT_URL_COHABIT und COCKPIT_COHABIT_TOKEN fehlen - siehe tools/uitest.sh")
    }

    @MainActor
    private func launch(tab: String = "today", extra: [String: String] = [:]) -> XCUIApplication {
        start(tab: tab, extra: [
            "COCKPIT_URL_COHABIT": baseURL,
            "COCKPIT_COHABIT_TOKEN": token,
            // Der Schalter „Klassische Liste" ueberlebt jeden Lauf - ohne das
            // saehe ein Test nach dem der klassischen Liste kein Dashboard.
            "COCKPIT_CLASSIC": "0",
        ].merging(extra) { _, new in new })
    }

    private func unique(_ prefix: String) -> String {
        "\(prefix) \(Int(Date().timeIntervalSince1970) % 100_000)"
    }

    // MARK: - Anlegen

    @MainActor
    func testCreateAStreakInThreeSteps() {
        let app = launch()
        let plus = app.buttons["tab-new"]
        XCTAssertTrue(plus.waitForExistence(timeout: 20), "keine untere Leiste")
        shoot(app, "heute")
        plus.tap()

        let streak = app.buttons["createType-STREAK"]
        XCTAssertTrue(streak.waitForExistence(timeout: 5), "Schritt 1 fehlt")
        shoot(app, "anlegen-1")
        streak.tap()

        let name = unique("Laufen UI")
        let field = app.textFields["createName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Schritt 2 fehlt")
        field.tap()
        field.typeText(name)
        app.buttons["choice-pro Woche"].tap()
        shoot(app, "anlegen-2")
        app.buttons["createNext"].tap()

        let start = app.buttons["createStart"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Schritt 3 fehlt")
        shoot(app, "anlegen-3")
        start.tap()

        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 15), "Detailseite zeigt das neue Co-Habit nicht")
        shoot(app, "anlegen-fertig")
    }

    // MARK: - Abhaken mit Foto aus der Galerie

    @MainActor
    func testCheckInWithAPhotoFromTheGallery() throws {
        let name = unique("Foto UI")
        let id = try createCohabit(name: name, photoRequired: true, token: token)
        let app = launch()
        let card = app.buttons["card-\(id)"]
        XCTAssertTrue(card.waitForExistence(timeout: 20), "Karte fehlt auf „Heute“")
        card.tap()

        let checkIn = app.buttons["detailCheckIn"]
        XCTAssertTrue(checkIn.waitForExistence(timeout: 10))
        XCTAssertEqual(checkIn.label, "Beweisfoto & abhaken")
        checkIn.tap()

        let gallery = app.buttons["photoGallery"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 5), "Beweisfoto-Blatt fehlt")
        shoot(app, "beweisfoto-blatt")
        XCTAssertFalse(app.buttons["photoPost"].isEnabled, "ohne Foto kein Posten")
        gallery.tap()
        try pickFirstPhoto(in: app)

        XCTAssertTrue(app.images["chosenPhoto"].waitForExistence(timeout: 10), "Foto nicht übernommen")
        let caption = app.textFields["photoCaption"]
        caption.tap()
        caption.typeText("Regenlauf zählt doppelt.")
        shoot(app, "beweisfoto-gewaehlt")
        app.buttons["photoPost"].tap()

        let done = app.buttons["detailCheckIn"]
        XCTAssertTrue(waitFor(done, toReadAgain: "Heute erledigt"), "nach dem Posten steht nicht „Heute erledigt“")
        shoot(app, "beweisfoto-erledigt")

        app.buttons["segment-Chat"].tap()
        XCTAssertTrue(app.staticTexts["Regenlauf zählt doppelt."].waitForExistence(timeout: 10),
                      "der Check-in-Post fehlt im Chat")
        shoot(app, "beweisfoto-im-chat")
    }

    /// Die Mediathek ist ein eigener Prozess; ihre Bilder erreicht XCUITest
    /// trotzdem ueber die App. Sie heissen „Foto, 30. September, 15:34" - ein
    /// blosses `images.firstMatch` traefe ein Symbol der App hinter dem Blatt.
    @MainActor
    private func pickFirstPhoto(in app: XCUIApplication) throws {
        let photo = app.images.matching(NSPredicate(
            format: "identifier == 'PXGGridLayout-Info' OR label BEGINSWITH 'Foto,'")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 15), "keine Bilder in der Mediathek - simctl addmedia?")
        shoot(app, "galerie")
        // Die Auswahl laeuft in einem fremden Prozess: XCUITest sieht das Bild,
        // haelt es aber fuer nicht tippbar - ein Tipp auf die Stelle geht.
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    // MARK: - Chat

    @MainActor
    func testWriteAChatMessage() throws {
        let name = unique("Chat UI")
        let id = try createCohabit(name: name, photoRequired: false, token: token)
        let app = launch()
        let card = app.buttons["card-\(id)"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()
        let chat = app.buttons["segment-Chat"]
        XCTAssertTrue(chat.waitForExistence(timeout: 10))
        chat.tap()

        let field = app.textFields["chatField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "kein Eingabefeld")
        field.tap()
        let text = "Morgen 7 Uhr an der Alster? \(Int.random(in: 100...999))"
        field.typeText(text)
        app.buttons["chatSend"].tap()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 10), "die Nachricht erscheint nicht")
        shoot(app, "chat")
    }

    // MARK: - Einladung annehmen

    @MainActor
    func testAcceptAnInvitation() throws {
        try XCTSkipIf(otherToken.isEmpty, "COCKPIT_COHABIT_OTHER_TOKEN fehlt - niemand, der einladen koennte")
        let meId = try me(token: token)
        let name = unique("Einladung UI")
        _ = try createCohabit(name: name, photoRequired: false, token: otherToken, invite: [meId])

        let app = launch()
        let invitation = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'invitation-'"))
            .containing(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(invitation.waitForExistence(timeout: 20), "keine Einladung auf „Heute“")
        shoot(app, "einladung-karte")
        invitation.tap()

        let accept = app.buttons["inviteAccept"]
        XCTAssertTrue(accept.waitForExistence(timeout: 10), "kein Einladungsdialog")
        shoot(app, "einladung-dialog")
        accept.tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 15), "nach dem Annehmen fehlt die Detailseite")
        shoot(app, "einladung-angenommen")
    }

    // MARK: - Zugang

    /// Start ohne Zugang: ein App-Link mitten in kopiertem Text genuegt.
    @MainActor
    func testSignInWithAnAppLinkInsideText() throws {
        let created = try request("POST", "/me/app-links", body: ["label": "UI-Test"], token: token)
        let setupUrl = try XCTUnwrap(created["setupUrl"] as? String)
        let app = launch(extra: ["COCKPIT_COHABIT_TOKEN": "none"])
        let field = app.textFields["linkField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "kein Start ohne Zugang")
        shoot(app, "start")
        field.tap()
        field.typeText("Hier dein Link: \(setupUrl) Viel Spaß!")
        shoot(app, "start-link")
        app.buttons["welcomeNext"].tap()
        XCTAssertTrue(app.buttons["tab-new"].waitForExistence(timeout: 15), "nach dem Link nicht angemeldet")
        shoot(app, "start-angemeldet")
    }

    /// Einladungslink ohne Zugang = Registrierung (Vertrag §1.2): Anzeigename,
    /// Nutzername, Zustimmung - danach ist die neue Person im Co-Habit.
    @MainActor
    func testJoinWithoutAccessRegisters() throws {
        let name = unique("Beitritt UI")
        let id = try createCohabit(name: name, photoRequired: false, token: token)
        let link = try request("POST", "/cohabits/\(id)/invite-link", body: [:], token: token)
        let url = try XCTUnwrap(link["url"] as? String)
        let app = launch(extra: ["COCKPIT_COHABIT_TOKEN": "none"])
        let field = app.textFields["linkField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "kein Start ohne Zugang")
        field.tap()
        field.typeText(url)
        app.buttons["welcomeNext"].tap()

        let displayName = app.textFields["joinDisplayName"]
        XCTAssertTrue(displayName.waitForExistence(timeout: 10), "keine Anmeldung zur Einladung")
        displayName.tap()
        displayName.typeText("Jonas")
        let username = app.textFields["joinUsername"]
        username.tap()
        username.typeText("jonas\(Int.random(in: 1000...9999))")
        shoot(app, "beitritt-ohne-zugang")
        XCTAssertFalse(app.buttons["inviteAccept"].isEnabled, "ohne Zustimmung kein Beitritt")
        app.buttons["joinTerms"].tap()
        XCTAssertTrue(app.buttons["inviteAccept"].isEnabled)
        app.buttons["inviteAccept"].tap()

        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 15), "nach dem Beitritt fehlt das Co-Habit")
        shoot(app, "beitritt-fertig")
    }

    // MARK: - Ohne Netz

    /// Nur mit angehaltenem Dienst (COCKPIT_OFFLINE_TEST=1): der letzte Stand
    /// steht mit „Offline · Stand", ein Haken wartet mit Uhr im Postausgang.
    /// Ob er nach dem Neustart des Dienstes ankommt, prueft das Skript danach
    /// ueber die API.
    @MainActor
    func testOfflineCheckInWaitsInTheOutbox() throws {
        try XCTSkipIf(environment["COCKPIT_OFFLINE_TEST"] != "1", "nur mit angehaltenem Dienst")
        let app = launch()
        let sync = app.otherElements["syncLine"]
        XCTAssertTrue(sync.waitForExistence(timeout: 20), "keine Offline-Leiste")
        shoot(app, "offline-heute")
        let check = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'check-' AND label == 'Abhaken'")).firstMatch
        XCTAssertTrue(check.waitForExistence(timeout: 5), "kein offener Haken ohne Foto")
        check.tap()
        let waiting = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'wartet'")).firstMatch
        XCTAssertTrue(waiting.waitForExistence(timeout: 10), "der Haken liegt nicht im Postausgang")
        shoot(app, "offline-haken-wartet")
    }

    // MARK: - Klassische Liste

    /// Der Schalter im Profil, dann „Heute" als alte Habit-Liste: eine Zeile
    /// abhaken und wieder loesen. Das Habit legt der Test selbst an und raeumt
    /// es danach weg; der Dienst steht hinterher wie vorher.
    @MainActor
    func testClassicListFromTheProfileSwitch() throws {
        let name = unique("Klassisch UI")
        let created = try request("POST", "/classic/habits", body: ["name": name, "kind": "BUILD"], token: token)
        let id = try XCTUnwrap(created["id"] as? String)
        // Kein `defer`: nach einem Fehlschlag bricht XCTest die Methode ab, ohne
        // es auszufuehren - ein Teardown-Block laeuft trotzdem.
        cleanUp("DELETE", "/classic/habits/\(id)", token: token)

        let app = launch(tab: "profile")
        let toggle = app.switches["classicList"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20), "kein Schalter im Profil")
        reveal(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "0", "der Schalter stand schon")
        // Rechts auf den Schalter - die Beschriftung schaltet nicht.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(waitFor(toggle, toHaveValue: "1"), "der Schalter laesst sich nicht umlegen")
        shoot(app, "klassisch-schalter")

        app.buttons["tab-Heute"].tap()
        XCTAssertTrue(app.navigationBars["Habits"].waitForExistence(timeout: 15),
                      "„Heute“ zeigt nicht die klassische Liste")
        shoot(app, "klassisch-liste")

        let check = app.buttons["toggle-\(id)"]
        reveal(check, in: app)
        XCTAssertTrue(check.exists && check.isHittable, "die Zeile des neuen Habits fehlt")
        let streak = app.staticTexts["streak-\(id)"]
        XCTAssertEqual(streak.label, "0")
        check.tap()
        XCTAssertTrue(waitFor(streak, toReadAgain: "1"), "abgehakt, aber die Flamme zeigt \(streak.label)")
        XCTAssertEqual(check.value as? String, "erledigt")
        shoot(app, "klassisch-abgehakt")
        check.tap()
        XCTAssertTrue(waitFor(streak, toReadAgain: "0"), "geloest, aber die Flamme zeigt \(streak.label)")
        shoot(app, "klassisch-geloest")

        let after = try requestList("GET", "/classic/habits", token: token).first { $0["id"] as? String == id }
        XCTAssertEqual(after?["doneToday"] as? Bool, false, "der Dienst steht nicht wieder wie vorher")

        // Weiter unten die automatischen: Track food, Schritte, Fokus mit Balken.
        scrollDown(app, times: 4)
        shoot(app, "klassisch-unten")
    }

    /// Was nur hinter Gesten liegt: Langdruck (Nachtragen), Tipp auf den Namen
    /// (Editor), „+", und an einem geteilten Habit mit Foto-Pflicht, in dem
    /// die Person nicht Admin ist: Haken (Beweisfoto-Blatt), Wischen (Rueckfrage
    /// „verlassen?") und Tipp auf den Namen (Detailseite statt Editor).
    /// Jedes Blatt wird abgebrochen - geschrieben wird nur das Anlegen vorher.
    @MainActor
    func testClassicListSheetsAndGestures() throws {
        try XCTSkipIf(otherToken.isEmpty, "COCKPIT_COHABIT_OTHER_TOKEN fehlt - niemand, der ein Habit teilt")
        let name = unique("Allein UI")
        let own = try request("POST", "/classic/habits", body: ["name": name, "kind": "BUILD"], token: token)
        let ownId = try XCTUnwrap(own["id"] as? String)
        cleanUp("DELETE", "/classic/habits/\(ownId)", token: token)
        // Geteilt, mit Foto-Pflicht, Admin ist die andere Person.
        let sharedName = unique("Geteilt UI")
        let sharedId = try sharedCohabit(name: sharedName)
        cleanUp("DELETE", "/cohabits/\(sharedId)", confirm: true, token: otherToken)

        let app = launch(extra: ["COCKPIT_CLASSIC": "1"])
        XCTAssertTrue(app.navigationBars["Habits"].waitForExistence(timeout: 20), "keine klassische Liste")
        let ownName = app.staticTexts[name]
        reveal(ownName, in: app)

        ownName.press(forDuration: 0.8)
        let yesterday = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'day-'")).firstMatch
        XCTAssertTrue(yesterday.waitForExistence(timeout: 5), "Langdruck oeffnet das Nachtragen nicht")
        XCTAssertFalse(app.textFields["habitName"].exists, "langes Druecken darf den Editor nicht oeffnen")
        shoot(app, "klassisch-nachtragen")
        app.buttons["Fertig"].tap()
        XCTAssertTrue(yesterday.waitForNonExistence(timeout: 5))

        ownName.tap()
        let field = app.textFields["habitName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "als Admin oeffnet der Name nicht den Editor")
        XCTAssertEqual(field.value as? String, name, "Name nicht vorbelegt")
        XCTAssertTrue(app.navigationBars["Habit bearbeiten"].exists, "falscher Titel")
        shoot(app, "klassisch-bearbeiten")
        app.buttons["Abbrechen"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "Editor blieb offen")

        app.buttons["addHabit"].tap()
        XCTAssertTrue(app.navigationBars["Neues Habit"].waitForExistence(timeout: 5), "„+“ oeffnet nichts")
        shoot(app, "klassisch-neu")
        app.buttons["Abbrechen"].tap()
        XCTAssertTrue(app.navigationBars["Neues Habit"].waitForNonExistence(timeout: 5))

        let shared = app.staticTexts[sharedName]
        reveal(shared, in: app)
        XCTAssertTrue(shared.exists && shared.isHittable, "das geteilte Habit fehlt in der Liste")

        app.buttons["toggle-\(sharedId)"].tap()
        let gallery = app.buttons["photoGallery"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 10), "Foto-Pflicht oeffnet nicht das Beweisfoto-Blatt")
        shoot(app, "klassisch-beweisfoto")
        app.buttons["sheetClose"].tap()
        XCTAssertTrue(gallery.waitForNonExistence(timeout: 5))

        shared.swipeLeft()
        let delete = app.buttons["delete-\(sharedId)"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "Wischen zeigt keinen Papierkorb")
        delete.tap()
        let leave = app.buttons["Verlassen"]
        XCTAssertTrue(leave.waitForExistence(timeout: 5), "geteilt: keine Rueckfrage vor dem Verlassen")
        XCTAssertTrue(app.staticTexts["„\(sharedName)“ verlassen?"].exists, "falscher Titel der Rueckfrage")
        shoot(app, "klassisch-verlassen")
        // Unter iOS 26 ist die Rueckfrage ein Popover ohne „Abbrechen" - ein
        // Tipp daneben (linker Rand, keine Zeile) schliesst es.
        if app.buttons["Abbrechen"].exists {
            app.buttons["Abbrechen"].tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
        }
        XCTAssertTrue(leave.waitForNonExistence(timeout: 5))
        XCTAssertTrue(shared.waitForExistence(timeout: 5), "nach „Abbrechen“ muss das Habit bleiben")

        shared.tap()
        XCTAssertTrue(app.buttons["detailMenu"].waitForExistence(timeout: 10),
                      "ohne Admin oeffnet der Name nicht die Detailseite")
        XCTAssertFalse(app.textFields["habitName"].exists)
        shoot(app, "klassisch-detail")
    }

    /// Ein Co-Habit der anderen Person mit Foto-Pflicht, dem die Person hier
    /// beigetreten ist - so ist es geteilt, und Admin ist die andere.
    private func sharedCohabit(name: String) throws -> String {
        let meId = try me(token: token)
        let id = try createCohabit(name: name, photoRequired: true, token: otherToken, invite: [meId])
        let invitation = try requestList("GET", "/me/invitations", token: token).first { invitation in
            let cohabit = invitation["cohabit"] as? [String: Any]
            return (cohabit?["ref"] as? [String: Any])?["id"] as? String == id
        }
        let invitationId = try XCTUnwrap(invitation?["id"] as? String, "keine Einladung angekommen")
        _ = try request("POST", "/invitations/\(invitationId)/accept", body: [:], token: token)
        return id
    }

    /// Raeumt nach dem Test weg, was er angelegt hat - auch nach einem Fehlschlag.
    private func cleanUp(_ method: String, _ path: String, confirm: Bool = false, token: String) {
        let url = URL(string: baseURL + path)!
        addTeardownBlock {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if confirm {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = Data(#"{"confirm":true}"#.utf8)
            }
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    /// Scrollt, bis ein Element ueber der schwebenden Leiste liegt. `isHittable`
    /// taugt dafuer nicht: ganz unten im Fenster, hinter der Leiste, gilt ein
    /// Element als erreichbar - der Tipp trifft dann die Leiste oder nichts.
    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let bottom = app.frame.maxY - 140
        for _ in 0..<12 {
            if element.exists, element.frame.minY > 100, element.frame.maxY < bottom { return }
            scrollDown(app)
        }
    }

    /// Wartet, bis ein Element einen bestimmten Wert hat (Schalter, Haken).
    @MainActor
    private func waitFor(_ element: XCUIElement, toHaveValue value: String) -> Bool {
        let expectation = expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: element)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }

    // MARK: - Push

    /// Eine Meldung antippen fuehrt dorthin, wohin ihr `link` zeigt - und die
    /// App ueberlebt es (siehe CLAUDE.md: Completion-Handler statt `async`).
    /// Nur mit tools/pushtest.sh coHabit, das die Meldung von aussen zustellt.
    @MainActor
    func testTappingAPushNotificationDoesNotCrashTheApp() throws {
        try XCTSkipIf(environment["COCKPIT_PUSH_TEST"] != "1", "nur mit tools/pushtest.sh")
        let app = launch(extra: ["COCKPIT_ASK_PUSH": "1"])
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"].exists ? springboard.buttons["Allow"]
                                                         : springboard.buttons["Erlauben"]
        if allow.waitForExistence(timeout: 10) { allow.tap() }
        XCTAssertTrue(app.buttons["tab-new"].waitForExistence(timeout: 20))
        app.buttons["tab-Profil"].tap()
        XCUIDevice.shared.press(.home)

        let title = environment["COCKPIT_PUSH_TITLE"] ?? "Lena hat dich angestupst"
        let banner = springboard.staticTexts[title]
        XCTAssertTrue(banner.waitForExistence(timeout: 90), "keine Benachrichtigung angekommen")
        shoot(app, "push-banner")
        banner.tap()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15),
                      "App laeuft nach dem Tipp nicht im Vordergrund (Zustand \(app.state.rawValue))")
        XCTAssertTrue(app.staticTexts["todayHeadline"].waitForExistence(timeout: 10),
                      "der Link cohabit://today fuehrt nicht nach „Heute“")
        shoot(app, "push-getippt")
    }

    // MARK: - API

    /// Legt ein Streak an und liefert seine Kennung.
    private func createCohabit(name: String, photoRequired: Bool, token: String, invite: [String] = []) throws -> String {
        let body: [String: Any] = [
            "type": "STREAK", "name": name, "color": "peach", "timezone": "Europe/Berlin",
            "tracking": ["mode": "CHECK"], "photoRequired": photoRequired, "backfillHours": 48,
            "reminderTime": NSNull(), "membersCanInvite": false,
            "streak": ["rhythm": ["kind": "DAILY"], "groupStreak": false],
            "abstinence": NSNull(), "goal": NSNull(), "challenge": NSNull(), "health": NSNull(), "auto": NSNull(),
            "invitePersonIds": invite,
        ]
        let detail = try request("POST", "/cohabits", body: body, token: token)
        let summary = try XCTUnwrap(detail["summary"] as? [String: Any])
        let ref = try XCTUnwrap(summary["ref"] as? [String: Any])
        return try XCTUnwrap(ref["id"] as? String)
    }

    private func me(token: String) throws -> String {
        let me = try request("GET", "/me", body: nil, token: token)
        let person = try XCTUnwrap(me["person"] as? [String: Any])
        return try XCTUnwrap(person["id"] as? String)
    }

    private func request(_ method: String, _ path: String, body: [String: Any]?, token: String) throws -> [String: Any] {
        let data = try send(method, path, body: body, token: token)
        // 204 ohne Inhalt (Loeschen) ist auch eine Antwort.
        guard !data.isEmpty else { return [:] }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Fuer Antworten, die eine Liste sind (`/classic/habits`, `/me/invitations`).
    private func requestList(_ method: String, _ path: String, token: String) throws -> [[String: Any]] {
        let data = try send(method, path, body: nil, token: token)
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private func send(_ method: String, _ path: String, body: [String: Any]?, token: String) throws -> Data {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let done = expectation(description: path)
        nonisolated(unsafe) var result: Result<Data, Error> = .failure(URLError(.unknown))
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let text = String(decoding: data ?? Data(), as: UTF8.self)
                result = .failure(NSError(domain: "coHabit", code: http.statusCode,
                                          userInfo: [NSLocalizedDescriptionKey: "\(method) \(path): \(http.statusCode) \(text)"]))
            } else {
                result = .success(data ?? Data())
            }
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 20)
        return try result.get()
    }
}
