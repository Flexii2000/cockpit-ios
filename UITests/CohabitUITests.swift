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
        cleanUp("DELETE", "/cohabits/\(id)", confirm: true, token: token)
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
        // Seit mehrere Fotos gehen (bis zu vier), will die Mediathek die
        // Auswahl bestaetigt haben.
        for label in ["Hinzufügen", "Add"] where app.buttons[label].waitForExistence(timeout: 3) {
            app.buttons[label].tap()
            break
        }
    }

    // MARK: - Mehrere Beweisfotos

    /// Bis zu vier Fotos je Eintrag (Vertrag §2.3a): drei ueber die Galerie
    /// (`COCKPIT_TEST_PHOTO=1` liefert je Platz ein andersfarbiges Bild), eins
    /// wieder raus und ein neues rein, posten; im Chat und in der Timeline ein
    /// Karussell mit Punkten. Dann den Eintrag bearbeiten: eins entfernen, eins
    /// ergaenzen - der Dienst traegt danach wieder drei.
    ///
    /// Ohne `COCKPIT_PHOTO_COHABIT` legt der Test ein Streak mit Foto-Pflicht
    /// an; mit der Kennung eines bestehenden (Demo-Daten) traegt er dort ein,
    /// neben den Fotos der anderen.
    @MainActor
    func testCheckInWithSeveralPhotos() throws {
        let tag = unique("Drei Fotos")
        let given = environment["COCKPIT_PHOTO_COHABIT"] ?? ""
        let id = given.isEmpty ? try createCohabit(name: unique("Fotos UI"), photoRequired: true, token: token) : given
        if given.isEmpty { cleanUp("DELETE", "/cohabits/\(id)", confirm: true, token: token) }
        let app = launch(extra: ["COCKPIT_TEST_PHOTO": "1", "COCKPIT_TIMELINE_HIDDEN": "none",
                                 "COCKPIT_LINK": "cohabit://cohabit/\(id)/checkin"])

        let gallery = app.buttons["photoGallery"]
        XCTAssertTrue(gallery.waitForExistence(timeout: 20), "Beweisfoto-Blatt fehlt")
        XCTAssertFalse(app.buttons["photoPost"].isEnabled, "ohne Foto kein Posten")
        gallery.tap()
        XCTAssertTrue(app.images["chosenPhoto"].waitForExistence(timeout: 5), "erstes Foto nicht übernommen")
        for _ in 0..<2 {
            app.buttons["addPhoto"].tap()
            XCTAssertTrue(gallery.waitForExistence(timeout: 5), "die „+“-Kachel öffnet keine Kamera")
            gallery.tap()
        }
        XCTAssertTrue(app.buttons["photoThumb-2"].waitForExistence(timeout: 5), "keine drei Vorschaubilder")
        snap(app, "fotos-drei")
        app.buttons["removePhoto-1"].tap()
        XCTAssertFalse(app.buttons["photoThumb-2"].waitForExistence(timeout: 2), "Entfernen wirkt nicht")
        app.buttons["addPhoto"].tap()
        gallery.tap()
        XCTAssertTrue(app.buttons["photoThumb-2"].waitForExistence(timeout: 5))
        let caption = app.textFields["photoCaption"]
        caption.tap()
        caption.typeText(tag)
        shoot(app, "fotos-vor-dem-posten")
        app.buttons["photoPost"].tap()
        XCTAssertTrue(waitUntilGone(app.buttons["photoPost"]), "das Blatt ist nach dem Posten noch offen")

        // Chat: der Post mit Karussell und Punkten.
        app.buttons["segment-Chat"].tap()
        XCTAssertTrue(app.staticTexts[tag].waitForExistence(timeout: 10), "der Check-in-Post fehlt im Chat")
        let carousel = app.descendants(matching: .any).matching(identifier: "photoCarousel").firstMatch
        XCTAssertTrue(carousel.waitForExistence(timeout: 5), "kein Karussell im Chat")
        let dots = app.descendants(matching: .any).matching(identifier: "photoDots").firstMatch
        XCTAssertEqual(dots.label, "Foto 1 von 3")
        snap(app, "fotos-chat")
        carousel.swipeLeft()
        XCTAssertTrue(waitFor(dots, toReadAgain: "Foto 2 von 3"), "Wischen blättert nicht")
        shoot(app, "fotos-chat-gewischt")

        // Timeline: dasselbe Karussell.
        app.buttons["Zurück"].firstMatch.tap()
        app.buttons["tab-Timeline"].tap()
        XCTAssertTrue(app.staticTexts[tag].waitForExistence(timeout: 15), "der Eintrag fehlt in der Timeline")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "photoCarousel").firstMatch
            .waitForExistence(timeout: 5), "kein Karussell in der Timeline")
        snap(app, "fotos-timeline")

        // Bearbeiten: eins raus, eins dazu.
        let link = launch(extra: ["COCKPIT_TEST_PHOTO": "1", "COCKPIT_LINK": "cohabit://cohabit/\(id)"])
        let menu = link.buttons["detailMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 20))
        menu.tap()
        link.buttons["Meine Einträge"].tap()
        let entry = link.buttons["Eintrag bearbeiten"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "kein eigener Eintrag")
        entry.tap()
        link.buttons["Bearbeiten"].tap()
        XCTAssertTrue(link.buttons["photoThumb-2"].waitForExistence(timeout: 10), "die drei Fotos fehlen im Bearbeiten")
        snap(link, "fotos-bearbeiten")
        link.buttons["removePhoto-0"].tap()
        link.buttons["addPhoto"].tap()
        let editGallery = link.buttons["photoGallery"]
        XCTAssertTrue(editGallery.waitForExistence(timeout: 5), "die „+“-Kachel öffnet keine Kamera")
        editGallery.tap()
        XCTAssertTrue(link.buttons["photoThumb-2"].waitForExistence(timeout: 5))
        shoot(link, "fotos-bearbeitet")
        link.buttons["checkinSave"].tap()
        XCTAssertTrue(waitUntilGone(link.buttons["checkinSave"]), "das Bearbeiten-Blatt geht nicht zu")
        shoot(link, "fotos-bearbeitet-gesichert")

        let detail = try request("GET", "/cohabits/\(id)", body: nil, token: token)
        let mine = try XCTUnwrap(detail["myCheckins"] as? [[String: Any]])
        let edited = try XCTUnwrap(mine.first { ($0["caption"] as? String) == tag })
        XCTAssertEqual((edited["photoIds"] as? [String])?.count, 3, "nach dem Bearbeiten nicht drei Fotos")
    }

    /// Wartet, bis ein Element weg ist - ein Blatt, das nach dem Senden zugeht.
    @MainActor
    private func waitUntilGone(_ element: XCUIElement) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
        return XCTWaiter.wait(for: [gone], timeout: 15) == .completed
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

    // MARK: - Emoji-Reaktionen und GIFs (Vertrag §2.7a)

    /// Langer Druck auf eine Nachricht: Leiste mit Schnellauswahl und Aktionen,
    /// ein Emoji setzt die Pille, ein anderes ersetzt es, das Blatt
    /// „Reaktionen" nimmt es mit „Entfernen" zurueck.
    @MainActor
    func testReactWithAnEmojiAndRemoveIt() throws {
        let id = try createCohabit(name: unique("Reaktion UI"), photoRequired: false, token: token)
        let text = "Heute frueher? \(Int.random(in: 100...999))"
        let posted = try request("POST", "/cohabits/\(id)/messages",
                                 body: ["id": UUID().uuidString.lowercased(), "text": text], token: token)
        let messageId = try XCTUnwrap(posted["id"] as? String)
        let app = launch(extra: ["COCKPIT_LINK": "cohabit://cohabit/\(id)/chat"])

        let bubble = app.staticTexts[text]
        XCTAssertTrue(bubble.waitForExistence(timeout: 20), "die Nachricht fehlt")
        bubble.press(forDuration: 0.8)
        let fire = app.buttons["react-🔥"]
        XCTAssertTrue(fire.waitForExistence(timeout: 5), "keine Leiste nach langem Druck")
        XCTAssertTrue(app.buttons["menuDelete"].exists, "die eigene Nachricht laesst sich loeschen")
        XCTAssertTrue(app.textFields["reactOther"].exists, "kein „+“")
        shoot(app, "reaktion-leiste")
        fire.tap()

        let pill = app.buttons["reactionPill"]
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "keine Pille unter der Nachricht")
        shoot(app, "reaktion-pille")
        XCTAssertEqual(try reactions(of: messageId, in: id), ["🔥"])

        // Ein anderes Emoji ersetzt das eigene.
        bubble.press(forDuration: 0.8)
        let laugh = app.buttons["react-😂"]
        XCTAssertTrue(laugh.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["react-🔥"].isSelected, "das eigene ist nicht hervorgehoben")
        laugh.tap()
        XCTAssertTrue(waitFor(pill, toReadAgain: "😂 1"), "das neue Emoji ersetzt das alte nicht")
        XCTAssertEqual(try reactions(of: messageId, in: id), ["😂"])

        pill.tap()
        let remove = app.buttons["reactionRemove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5), "kein Blatt „Reaktionen“")
        XCTAssertTrue(app.staticTexts["Reaktionen"].exists)
        shoot(app, "reaktion-blatt")
        remove.tap()
        XCTAssertTrue(waitUntilGone(pill), "die Pille bleibt nach „Entfernen“")
        XCTAssertEqual(try reactions(of: messageId, in: id), [])

        // „+": jedes andere Emoji ueber die Tastatur.
        bubble.press(forDuration: 0.8)
        let other = app.textFields["reactOther"]
        XCTAssertTrue(other.waitForExistence(timeout: 5))
        other.tap()
        sleep(1)
        shoot(app, "reaktion-tastatur")
        other.typeText("🎉")
        XCTAssertTrue(pill.waitForExistence(timeout: 10), "das Emoji aus der Tastatur kommt nicht an")
        XCTAssertEqual(try reactions(of: messageId, in: id), ["🎉"])
        shoot(app, "reaktion-anderes")
    }

    /// Timeline: der Smiley neben „Antworten" oeffnet dieselbe Leiste, die
    /// Pille steht auf der Karte; hell und dunkel aufgenommen.
    @MainActor
    func testReactInTheTimeline() throws {
        let app = launch(tab: "timeline", extra: ["COCKPIT_TIMELINE_HIDDEN": "none"])
        addTeardownBlock { XCUIDevice.shared.appearance = .light }
        let smiley = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'smiley-'")).firstMatch
        XCTAssertTrue(app.buttons["timelineFilter"].waitForExistence(timeout: 20))
        for _ in 0..<8 where !(smiley.exists && smiley.isHittable) { scrollDown(app) }
        XCTAssertTrue(smiley.isHittable, "keine Foto-Karte mit Smiley in den Demo-Daten")
        let itemId = String(smiley.identifier.dropFirst("smiley-".count))
        shoot(app, "timeline-karte")
        smiley.tap()
        let clap = app.buttons["react-👏"]
        XCTAssertTrue(clap.waitForExistence(timeout: 5), "der Smiley oeffnet keine Leiste")
        XCTAssertFalse(app.buttons["menuDelete"].exists, "in der Timeline gibt es nichts zu loeschen")
        shoot(app, "timeline-leiste")
        XCUIDevice.shared.appearance = .dark
        sleep(1)
        shoot(app, "timeline-leiste-dunkel")
        let selected = clap.isSelected
        clap.tap()
        let card = app.otherElements["event-\(itemId)"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        sleep(1)
        shoot(app, "timeline-pille-dunkel")
        // Zurueck auf den Stand vorher: noch einmal dasselbe nimmt es zurueck.
        smiley.tap()
        XCTAssertTrue(clap.waitForExistence(timeout: 5))
        XCTAssertEqual(clap.isSelected, !selected, "das eigene ist nicht hervorgehoben")
        clap.tap()
    }

    /// Das GIF-Blatt gegen tools/klipy-stub.py: Suchfeld „Search KLIPY",
    /// Raster, Antippen sendet sofort und schliesst das Blatt.
    @MainActor
    func testSendAGifFromTheSearch() throws {
        let klipy = environment["COCKPIT_URL_KLIPY"] ?? ""
        try XCTSkipIf(klipy.isEmpty, "COCKPIT_URL_KLIPY fehlt - python3 tools/klipy-stub.py starten")
        let id = try createCohabit(name: unique("GIF UI"), photoRequired: false, token: token)
        let app = launch(extra: ["COCKPIT_LINK": "cohabit://cohabit/\(id)/chat", "COCKPIT_URL_KLIPY": klipy])

        let button = app.buttons["chatGif"]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "kein GIF-Knopf - liefert /gifs/config enabled?")
        shoot(app, "gif-knopf")
        button.tap()
        let search = app.textFields["gifSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "kein GIF-Blatt")
        XCTAssertEqual(search.placeholderValue, "Search KLIPY")
        XCTAssertTrue(app.buttons["gifTile-0"].waitForExistence(timeout: 10), "kein Trending")
        sleep(2)
        shoot(app, "gif-trending")
        search.tap()
        search.typeText("winken")
        sleep(2)
        shoot(app, "gif-suche")
        app.buttons["gifTile-1"].tap()
        XCTAssertTrue(waitUntilGone(search), "das Blatt bleibt offen")
        let gif = app.otherElements["gif-hello-hi-663"]
        XCTAssertTrue(gif.waitForExistence(timeout: 10), "das GIF steht nicht im Chat")
        sleep(2)
        shoot(app, "gif-chat")

        let messages = try XCTUnwrap(try request("GET", "/cohabits/\(id)/messages", body: nil, token: token)["messages"]
            as? [[String: Any]])
        let last = try XCTUnwrap(messages.last)
        XCTAssertEqual(last["kind"] as? String, "GIF")
        XCTAssertEqual((last["gif"] as? [String: Any])?["slug"] as? String, "hello-hi-663")
    }

    /// Die Emojis einer Nachricht laut Dienst.
    private func reactions(of messageId: String, in cohabitId: String) throws -> [String] {
        let messages = try XCTUnwrap(try request("GET", "/cohabits/\(cohabitId)/messages", body: nil, token: token)["messages"]
            as? [[String: Any]])
        let message = try XCTUnwrap(messages.first { $0["id"] as? String == messageId })
        return ((message["reactions"] as? [[String: Any]]) ?? []).compactMap { $0["reaction"] as? String }
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

    /// Ohne Zugang geoeffnet, meldet ein App-Link sofort an - so oeffnet der
    /// Knopf „In der App öffnen" der Weboberflaeche die App. Bis 2026-09-30 lag
    /// der Link dann nur bereit, und niemand sah hin (auf Felix' iPhone passiert).
    @MainActor
    func testAnAppLinkOpenedWithoutAccessSignsIn() throws {
        let created = try request("POST", "/me/app-links", body: ["label": "UI-Test Link"], token: token)
        let appToken = try XCTUnwrap(created["token"] as? String)
        if let linkId = created["id"] as? String { cleanUp("DELETE", "/me/app-links/\(linkId)", token: token) }
        let app = launch(extra: ["COCKPIT_COHABIT_TOKEN": "none"])
        XCTAssertTrue(app.textFields["linkField"].waitForExistence(timeout: 15), "kein Start ohne Zugang")
        shoot(app, "link-start")
        // Der Weg, den ein Tipp auf den Link nimmt: iOS reicht ihn an onOpenURL.
        app.open(URL(string: "cohabit://setup?token=\(appToken)")!)
        confirmOpenInApp()
        XCTAssertTrue(app.staticTexts["todayHeadline"].waitForExistence(timeout: 20),
                      "der Link hat nicht angemeldet - „Heute“ fehlt")
        shoot(app, "link-angemeldet")
    }

    /// Ein Link mit einem Token, den der Dienst nicht kennt: „Link ungültig"
    /// auf dem Start, statt still nichts zu tun.
    @MainActor
    func testAnInvalidAppLinkWithoutAccessSaysSo() {
        let app = launch(extra: ["COCKPIT_COHABIT_TOKEN": "none",
                                 "COCKPIT_LINK": "cohabit://setup?token=gibtesnicht0000"])
        let error = app.staticTexts["welcomeError"]
        XCTAssertTrue(error.waitForExistence(timeout: 15), "kein Hinweis auf dem Start")
        shoot(app, "link-ungueltig")
        XCTAssertEqual(error.label, "Link ungültig")
        XCTAssertTrue(app.textFields["linkField"].exists, "ohne gueltigen Link bleibt der Start")
    }

    /// Ein Einladungslink ohne Zugang oeffnet gleich die Registrierung.
    @MainActor
    func testAJoinLinkOpenedWithoutAccessShowsTheRegistration() throws {
        let name = unique("Link UI")
        let id = try createCohabit(name: name, photoRequired: false, token: token)
        cleanUp("DELETE", "/cohabits/\(id)", confirm: true, token: token)
        let link = try request("POST", "/cohabits/\(id)/invite-link", body: [:], token: token)
        let code = try XCTUnwrap(link["code"] as? String)
        let app = launch(extra: ["COCKPIT_COHABIT_TOKEN": "none", "COCKPIT_LINK": "cohabit://join/\(code)"])
        let displayName = app.textFields["joinDisplayName"]
        XCTAssertTrue(displayName.waitForExistence(timeout: 15), "keine Registrierung zum Einladungslink")
        shoot(app, "link-einladung")
        // „Felix lädt dich zu „Name“ ein" - der Name steht im Satz.
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch.exists,
                      "die Einladung nennt das Co-Habit nicht")
    }

    /// Ein Link mit eigenem Schema: iOS fragt womoeglich erst, ob er in der App
    /// aufgehen soll.
    @MainActor
    private func confirmOpenInApp() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Öffnen", "Open"] where springboard.buttons[label].waitForExistence(timeout: 2) {
            springboard.buttons[label].tap()
            return
        }
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

    /// Eine Challenge in der klassischen Liste eintragen: „Eintragen" tut, was
    /// der Knopf der neuen Liste tut - hier +1, weil die Challenge Eintraege
    /// zaehlt -, danach steht „heute eingetragen" und der Dienst kennt den Eintrag.
    @MainActor
    func testAChallengeCanBeEnteredInTheClassicList() throws {
        let name = unique("Challenge UI")
        let id = try createChallenge(name: name)
        cleanUp("DELETE", "/cohabits/\(id)", confirm: true, token: token)

        let app = launch(extra: ["COCKPIT_CLASSIC": "1"])
        XCTAssertTrue(app.navigationBars["Habits"].waitForExistence(timeout: 20), "keine klassische Liste")
        let enter = app.buttons["toggle-\(id)"]
        reveal(enter, in: app)
        XCTAssertTrue(enter.exists && enter.isHittable, "kein „Eintragen“ an der Challenge")
        XCTAssertEqual(app.staticTexts["metric-\(id)"].label, "#1", "keine Kennzahl unter dem Pokal")
        shoot(app, "klassisch-challenge")
        XCTAssertEqual(enter.value as? String, "offen")

        enter.tap()
        XCTAssertTrue(waitFor(enter, toHaveValue: "heute eingetragen"),
                      "nach dem Eintragen steht \(enter.value as? String ?? "nichts")")
        shoot(app, "klassisch-challenge-eingetragen")
        let after = try requestList("GET", "/classic/habits", token: token).first { $0["id"] as? String == id }
        XCTAssertEqual(after?["doneToday"] as? Bool, true, "der Dienst kennt den Eintrag nicht")
        XCTAssertEqual(after?["kind"] as? String, "CHALLENGE")
    }

    // MARK: - Fokus-Habits nach Kategorie

    /// Fokus-Habit mit Kategorie anlegen: Streak, Automatisch, Fokus-Zeit, pro
    /// Woche, eine Kategorie aus dem Wald. Beim Dienst kommen Kategorie und
    /// Zeitraum an, die Detailseite zeigt seine Typzeile („… Min. Bachelorarbeit
    /// pro Woche"). Nur als Felix - nur er hat Fokus-Zeit und Baeume.
    @MainActor
    func testCreateAFocusHabitWithACategory() throws {
        let category = try focusCategory()
        let categoryName = try XCTUnwrap(category["name"] as? String)
        let name = unique("Fokus UI")

        let app = launch()
        let plus = app.buttons["tab-new"]
        XCTAssertTrue(plus.waitForExistence(timeout: 20), "keine untere Leiste")
        plus.tap()
        app.buttons["createType-STREAK"].tap()
        let field = app.textFields["createName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Schritt 2 fehlt")
        field.tap()
        // Mit Zeilenschaltung: die Tastatur geht weg und verdeckt die Felder im Bild nicht.
        field.typeText(name + "\n")
        app.buttons["choice-Automatisch"].tap()
        let focus = app.buttons["choice-Fokus-Zeit"]
        XCTAssertTrue(focus.waitForExistence(timeout: 5), "keine Quelle Fokus-Zeit")
        focus.tap()
        let weekly = app.buttons["Pro Woche"]
        reveal(weekly, in: app)
        weekly.tap()
        XCTAssertTrue(app.staticTexts["4:00 h pro Woche"].waitForExistence(timeout: 5),
                      "die Minuten gelten nicht je Woche")
        let chip = app.buttons["choice-\(categoryName)"]
        reveal(chip, in: app)
        XCTAssertTrue(app.buttons["choice-Alle Bäume"].isSelected, "vorbelegt sind nicht alle Baeume")
        chip.tap()
        XCTAssertTrue(chip.isSelected, "die Kategorie ist nicht gewaehlt")
        snap(app, "fokus-habit-anlegen")
        app.buttons["createNext"].tap()
        let start = app.buttons["createStart"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Schritt 3 fehlt")
        start.tap()

        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 15), "Detailseite zeigt das neue Co-Habit nicht")
        let created = try requestList("GET", "/cohabits", token: token).first {
            ($0["ref"] as? [String: Any])?["name"] as? String == name
        }
        let id = try XCTUnwrap((created?["ref"] as? [String: Any])?["id"] as? String, "beim Dienst nicht angelegt")
        cleanUp("DELETE", "/cohabits/\(id)", confirm: true, token: token)
        let detail = try request("GET", "/cohabits/\(id)", body: nil, token: token)
        let auto = (detail["config"] as? [String: Any])?["auto"] as? [String: Any]
        XCTAssertEqual(auto?["source"] as? String, "FOCUS")
        XCTAssertEqual(auto?["focusCategoryId"] as? String, category["id"] as? String)
        XCTAssertEqual(auto?["focusCategoryName"] as? String, categoryName)
        XCTAssertEqual(auto?["focusPeriod"] as? String, "WEEK")
        XCTAssertEqual(auto?["focusMinutesGoal"] as? Int, 240)

        let typeLine = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "\(categoryName) pro Woche"))
            .firstMatch
        XCTAssertTrue(typeLine.waitForExistence(timeout: 5), "die Detailseite nennt Kategorie und Zeitraum nicht")
        snap(app, "fokus-habit-detail")

        // Bearbeiten: nur die Minuten - Kategorie und Zeitraum muessen bleiben
        // (der Dienst liest ein fehlendes Feld als „alle Baeume", „je Tag").
        app.buttons["detailMenu"].tap()
        app.buttons["Bearbeiten"].tap()
        let more = app.buttons["Mehr"].firstMatch
        XCTAssertTrue(app.staticTexts["4:00 h pro Woche"].waitForExistence(timeout: 5), "Minuten je Woche nicht vorbelegt")
        XCTAssertTrue(app.buttons["choice-\(categoryName)"].isSelected, "Kategorie nicht vorbelegt")
        more.tap()
        XCTAssertTrue(app.staticTexts["5:00 h pro Woche"].waitForExistence(timeout: 5))
        snap(app, "fokus-habit-bearbeiten")
        app.buttons["Sichern"].tap()
        XCTAssertTrue(app.buttons["Sichern"].waitForNonExistence(timeout: 10), "das Blatt bleibt offen")
        let edited = (try request("GET", "/cohabits/\(id)", body: nil, token: token)["config"] as? [String: Any])?["auto"]
            as? [String: Any]
        XCTAssertEqual(edited?["focusMinutesGoal"] as? Int, 300)
        XCTAssertEqual(edited?["focusCategoryId"] as? String, category["id"] as? String, "Kategorie beim Bearbeiten verloren")
        XCTAssertEqual(edited?["focusPeriod"] as? String, "WEEK", "Zeitraum beim Bearbeiten verloren")
    }

    /// Die klassische Liste: ein Fokus-Habit nur fuer eine Kategorie, je Woche,
    /// traegt die Kategorie im Untertitel und den Stand der Woche rechts; das
    /// Kalorienziel im Wochenmittel steht als „Track food" in Wochen mit „Ø".
    /// Der Editor ist mit Zeitraum und Kategorie vorbelegt.
    @MainActor
    func testClassicListShowsFocusCategoryAndTheWeeklyMean() throws {
        let category = try focusCategory()
        let categoryName = try XCTUnwrap(category["name"] as? String)
        let focusName = unique("Fokus Woche UI")
        let focus = try request("POST", "/classic/habits", body: [
            "name": focusName, "kind": "FOCUS", "focusMinutesGoal": 600,
            "focusCategoryId": category["id"] as? String ?? "", "focusPeriod": "WEEK",
        ], token: token)
        let focusId = try XCTUnwrap(focus["id"] as? String)
        cleanUp("DELETE", "/classic/habits/\(focusId)", token: token)
        XCTAssertEqual((focus["focus"] as? [String: Any])?["period"] as? String, "WEEK")
        XCTAssertEqual(focus["unit"] as? String, "WEEKS")

        let meanName = unique("Kalorienziel UI")
        let meanId = try createAutoStreak(name: meanName, source: "FOOD_TARGET_WEEKLY")
        cleanUp("DELETE", "/cohabits/\(meanId)", confirm: true, token: token)

        let app = launch(extra: ["COCKPIT_CLASSIC": "1"])
        XCTAssertTrue(app.navigationBars["Habits"].waitForExistence(timeout: 20), "keine klassische Liste")
        let row = app.staticTexts[focusName]
        reveal(row, in: app)
        let subtitle = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "Wochen · \(categoryName)"))
            .firstMatch
        XCTAssertTrue(subtitle.waitForExistence(timeout: 10), "kein Untertitel mit der Kategorie")
        let progress = app.staticTexts["focus-\(focusId)"]
        XCTAssertTrue(progress.label.hasSuffix("/10:00 h"), "kein Wochenstand: \(progress.label)")
        let mean = app.staticTexts["kcal-\(meanId)"]
        reveal(mean, in: app)
        XCTAssertTrue(mean.waitForExistence(timeout: 10), "das Kalorienziel im Wochenmittel fehlt")
        XCTAssertTrue(mean.label.hasPrefix("Ø "), "der Wochenschnitt sieht aus wie heute: \(mean.label)")
        snap(app, "klassisch-fokus-woche")

        reveal(row, in: app)
        row.tap()
        let minutes = app.textFields["focusMinutes"]
        XCTAssertTrue(minutes.waitForExistence(timeout: 5), "als Admin oeffnet der Name nicht den Editor")
        XCTAssertEqual(minutes.value as? String, "600")
        XCTAssertTrue(app.buttons["Pro Woche"].isSelected, "Zeitraum nicht vorbelegt")
        let picker = app.descendants(matching: .any).matching(identifier: "focusCategory").firstMatch
        XCTAssertTrue(picker.exists, "keine Auswahl der Kategorie")
        let shown = picker.label + " " + ((picker.value as? String) ?? "")
        XCTAssertTrue(shown.contains(categoryName), "Kategorie nicht vorbelegt: \(shown)")
        XCTAssertTrue(app.staticTexts["Wochenziel in Minuten"].exists || app.staticTexts["WOCHENZIEL IN MINUTEN"].exists,
                      "Ueberschrift nicht je Woche")
        snap(app, "klassisch-fokus-editor")
        app.buttons["Abbrechen"].tap()
    }

    /// Eine Kategorie aus dem Wald - gibt es noch keine, legt der Test eine an
    /// (beim Habits-Dienst neben coHabit, mit demselben Token) und raeumt sie weg.
    @MainActor
    private func focusCategory() throws -> [String: Any] {
        let sources = (try request("GET", "/me", body: nil, token: token)["sources"] as? [String]) ?? []
        try XCTSkipIf(!sources.contains("FOCUS"), "nur als Felix (COCKPIT_COHABIT_TOKEN=local-private) - nur er hat Baeume")
        if let first = try requestList("GET", "/focus/categories", token: token).first { return first }
        let forest = baseURL.replacingOccurrences(of: "/cohabit/api", with: "/habits/api/focus")
        var request = URLRequest(url: URL(string: forest + "/categories")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"name":"Bachelorarbeit"}"#.utf8)
        let done = expectation(description: "Kategorie")
        nonisolated(unsafe) var created: [String: Any]?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            created = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 20)
        let category = try XCTUnwrap(created, "keine Kategorie im Wald und keine anzulegen")
        let id = try XCTUnwrap(category["id"] as? String)
        let url = URL(string: forest + "/categories/\(id)")!
        let token = token
        addTeardownBlock {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
        return category
    }

    /// Ein automatisches Streak - nur die Person hier.
    private func createAutoStreak(name: String, source: String) throws -> String {
        let body: [String: Any] = [
            "type": "STREAK", "name": name, "color": "aqua", "timezone": "Europe/Berlin",
            "tracking": ["mode": "CHECK"], "photoRequired": false, "backfillHours": 48,
            "reminderTime": NSNull(), "membersCanInvite": false,
            "streak": ["rhythm": ["kind": "TIMES_PER_WEEK", "times": 1], "groupStreak": false],
            "abstinence": NSNull(), "goal": NSNull(), "challenge": NSNull(), "health": NSNull(),
            "auto": ["source": source, "weeklyStepGoal": NSNull(), "focusMinutesGoal": NSNull()],
            "invitePersonIds": [String](),
        ]
        let detail = try request("POST", "/cohabits", body: body, token: token)
        let summary = try XCTUnwrap(detail["summary"] as? [String: Any])
        let ref = try XCTUnwrap(summary["ref"] as? [String: Any])
        return try XCTUnwrap(ref["id"] as? String)
    }

    /// kcal aus Healthy: die Health-Karte ist ein Schalter - einschalten
    /// stimmt beim Dienst zu (ohne Apple-Health-Abfrage), ausschalten widerruft.
    @MainActor
    func testKcalFromHealthyIsASwitch() throws {
        let sources = (try request("GET", "/me", body: nil, token: token)["sources"] as? [String]) ?? []
        try XCTSkipIf(!sources.contains("FOOD"), "die Person hat keinen Healthy-Zugang")
        let id = try createKcalGoal(name: unique("kcal UI"))
        cleanUp("DELETE", "/cohabits/\(id)", confirm: true, token: token)

        let app = launch(extra: ["COCKPIT_LINK": "cohabit://cohabit/\(id)"])
        let toggle = app.switches["healthyConsent"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 20), "keine Karte „kcal aus Healthy“")
        XCTAssertFalse(app.buttons["healthConnect"].exists, "kein „Verbinden“ mit Apple Health")
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        XCTAssertTrue(waitFor(toggle, toHaveValue: "1"), "der Schalter laesst sich nicht einschalten")
        shoot(app, "kcal-zugestimmt")
        XCTAssertEqual(try consent(id), true, "der Dienst kennt die Zustimmung nicht")
        toggle.tap()
        XCTAssertTrue(waitFor(toggle, toHaveValue: "0"))
        XCTAssertEqual(try consent(id), false, "der Dienst kennt den Widerruf nicht")
    }

    private func consent(_ cohabitId: String) throws -> Bool? {
        let detail = try request("GET", "/cohabits/\(cohabitId)", body: nil, token: token)
        return (detail["mySettings"] as? [String: Any])?["healthConsent"] as? Bool
    }

    /// Ein Teamziel in kcal aus Healthy - nur die Person hier.
    private func createKcalGoal(name: String) throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")
        formatter.dateFormat = "yyyy-MM-dd"
        let body: [String: Any] = [
            "type": "GOAL", "name": name, "color": "mint", "timezone": "Europe/Berlin",
            "tracking": ["mode": "VALUE", "unit": "KCAL"], "photoRequired": false, "backfillHours": 48,
            "reminderTime": NSNull(), "membersCanInvite": false,
            "streak": NSNull(), "abstinence": NSNull(), "challenge": NSNull(), "auto": NSNull(),
            "goal": ["target": 60000, "start": formatter.string(from: Date()),
                     "deadline": formatter.string(from: Date().addingTimeInterval(30 * 86_400)),
                     "counting": "AMOUNT", "mode": "TEAM"],
            "health": ["metric": "KCAL"], "invitePersonIds": [String](),
        ]
        let detail = try request("POST", "/cohabits", body: body, token: token)
        let summary = try XCTUnwrap(detail["summary"] as? [String: Any])
        let ref = try XCTUnwrap(summary["ref"] as? [String: Any])
        return try XCTUnwrap(ref["id"] as? String)
    }

    /// Eine Challenge „meiste Eintraege", die heute beginnt - nur die Person hier.
    private func createChallenge(name: String) throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")
        formatter.dateFormat = "yyyy-MM-dd"
        let start = formatter.string(from: Date())
        let end = formatter.string(from: Date().addingTimeInterval(7 * 86_400))
        let body: [String: Any] = [
            "type": "CHALLENGE", "name": name, "color": "butter", "timezone": "Europe/Berlin",
            "tracking": ["mode": "CHECK"], "photoRequired": false, "backfillHours": 48,
            "reminderTime": NSNull(), "membersCanInvite": false,
            "streak": NSNull(), "abstinence": NSNull(), "goal": NSNull(),
            "challenge": ["start": start, "end": end, "scoring": "MOST_ENTRIES", "target": NSNull(),
                          "stake": NSNull(), "recurrence": "NONE"],
            "health": NSNull(), "auto": NSNull(), "invitePersonIds": [String](),
        ]
        let detail = try request("POST", "/cohabits", body: body, token: token)
        let summary = try XCTUnwrap(detail["summary"] as? [String: Any])
        let ref = try XCTUnwrap(summary["ref"] as? [String: Any])
        return try XCTUnwrap(ref["id"] as? String)
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

    // MARK: - Timeline-Filter

    /// Der Filter als Abhak-Liste: ein Habit abwaehlen, seine Eintraege
    /// verschwinden, nach dem Neustart gilt dieselbe Auswahl. Dazwischen alles
    /// aus („0 von … Habits", „Keine Habits ausgewählt"). Knopf und Blatt hell
    /// und dunkel.
    @MainActor
    func testTimelineFilterHidesAHabitAndKeepsTheChoice() throws {
        let name = unique("Filter UI")
        let id = try createCohabit(name: name, photoRequired: false, token: token)
        cleanUp("DELETE", "/cohabits/\(id)", confirm: true, token: token)
        // Ein Eintrag, damit das Co-Habit in der Timeline steht - ganz oben.
        _ = try request("POST", "/cohabits/\(id)/checkins",
                        body: ["id": UUID().uuidString.lowercased(), "kind": "DONE"], token: token)
        let total = try requestList("GET", "/cohabits", token: token).count
        let filtered = "\(total - 1) von \(total) Habits"

        var app = launch(tab: "timeline", extra: ["COCKPIT_TIMELINE_HIDDEN": "none"])
        let button = app.buttons["timelineFilter"]
        XCTAssertTrue(button.waitForExistence(timeout: 20), "kein Filter-Knopf")
        let event = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 10), "der Eintrag des neuen Habits fehlt")
        snap(app, "timeline-filter-knopf")
        XCTAssertEqual(button.label, "Alle Habits")

        button.tap()
        let row = app.buttons["filterRow-\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "das neue Habit fehlt im Blatt")
        XCTAssertEqual(row.value as? String, "an", "ein neues Co-Habit ist von selbst angehakt")
        snap(app, "timeline-filter-blatt")
        row.tap()
        XCTAssertTrue(waitFor(row, toHaveValue: "aus"), "der Haken geht nicht weg")
        app.buttons["sheetClose"].tap()
        XCTAssertTrue(waitFor(button, toReadAgain: filtered), "der Knopf zeigt \(button.label)")
        XCTAssertTrue(event.waitForNonExistence(timeout: 10), "die Eintraege des abgewaehlten Habits stehen noch da")
        snap(app, "timeline-gefiltert")

        // Alles aus - „Alle" schaltet erst alle an, dann alle aus.
        button.tap()
        let all = app.buttons["filterAll"]
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        all.tap()
        XCTAssertTrue(waitFor(all, toHaveValue: "an"), "nicht alle an - „Alle“ schaltet alle an")
        all.tap()
        XCTAssertTrue(waitFor(all, toHaveValue: "aus"), "alle an - „Alle“ schaltet alle aus")
        XCTAssertEqual(row.value as? String, "aus")
        app.buttons["sheetClose"].tap()
        XCTAssertTrue(app.staticTexts["noHabitsSelected"].waitForExistence(timeout: 10),
                      "keine Zeile „Keine Habits ausgewählt“")
        XCTAssertTrue(waitFor(button, toReadAgain: "0 von \(total) Habits"))
        snap(app, "timeline-keine")

        // Wieder alle an, nur das neue aus - dann neu starten.
        button.tap()
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        all.tap()
        XCTAssertTrue(waitFor(all, toHaveValue: "an"))
        row.tap()
        XCTAssertTrue(waitFor(row, toHaveValue: "aus"))
        app.buttons["sheetClose"].tap()
        XCTAssertTrue(waitFor(button, toReadAgain: filtered))

        app.terminate()
        app = launch(tab: "timeline")
        let again = app.buttons["timelineFilter"]
        XCTAssertTrue(again.waitForExistence(timeout: 20))
        XCTAssertTrue(waitFor(again, toReadAgain: filtered), "nach dem Neustart steht \(again.label)")
        // Erst wenn die Timeline steht, sagt das Fehlen des Eintrags etwas.
        let other = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'event-'")).firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 15), "die Timeline laedt nicht")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch.exists,
                       "nach dem Neustart ist das abgewaehlte Habit wieder da")
        shoot(app, "timeline-nach-neustart")
    }

    /// Hell und dunkel - der Wechsel braucht einen Augenblick zum Neuzeichnen.
    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        XCUIDevice.shared.appearance = .light
        Thread.sleep(forTimeInterval: 0.8)
        shoot(app, name + "-hell")
        XCUIDevice.shared.appearance = .dark
        Thread.sleep(forTimeInterval: 0.8)
        shoot(app, name + "-dunkel")
        XCUIDevice.shared.appearance = .light
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
