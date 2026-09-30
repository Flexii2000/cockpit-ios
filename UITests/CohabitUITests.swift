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

        app.buttons["Chat"].tap()
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
        photo.tap()
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
        let chat = app.buttons["Chat"]
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
        let data = try result.get()
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
