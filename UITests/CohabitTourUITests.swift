import XCTest

/// Ein Rundgang durch jeden Bildschirm von coHabit, hell und dunkel - gegen
/// den lokalen Dienst mit Demo-Daten (tools/uitest.sh coHabit testTourOfAllScreens).
///
/// Der Simulator allein kommt an Menues, Blaetter und Dialoge nicht heran;
/// der Rundgang tippt sich hin und nimmt jeden Zustand zweimal auf. Er
/// veraendert nichts, ausser: ein offener Abschlussdialog wird mit
/// „Gratulieren" beantwortet, und eine Einladung, die er selbst anlegt, lehnt
/// er wieder ab.
final class CohabitTourUITests: XCTestCase {

    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var baseURL: String { environment["COCKPIT_URL_COHABIT"] ?? "" }
    private var token: String { environment["COCKPIT_COHABIT_TOKEN"] ?? "" }
    private var otherToken: String { environment["COCKPIT_COHABIT_OTHER_TOKEN"] ?? "" }

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipIf(environment["COCKPIT_TOUR"] != "1",
                      "nur für Bildschirmfotos: COCKPIT_TOUR=1 tools/uitest.sh coHabit CohabitTourUITests/testTourOfAllScreens")
        try XCTSkipIf(baseURL.isEmpty || token.isEmpty, "COCKPIT_URL_COHABIT und COCKPIT_COHABIT_TOKEN fehlen")
    }

    @MainActor
    private func launch(tab: String = "today", link: String? = nil, extra: [String: String] = [:]) -> XCUIApplication {
        // Mit Dashboard, auch wenn ein Lauf davor die klassische Liste eingeschaltet hat.
        var env = ["COCKPIT_URL_COHABIT": baseURL, "COCKPIT_COHABIT_TOKEN": token, "COCKPIT_CLASSIC": "0"]
        if let link { env["COCKPIT_LINK"] = link }
        return start(tab: tab, extra: env.merging(extra) { _, new in new })
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

    @MainActor
    private func closeSheet(_ app: XCUIApplication) {
        let close = app.buttons["sheetClose"]
        if close.waitForExistence(timeout: 3) { close.tap() }
        _ = close.waitForNonExistence(timeout: 3)
    }

    /// Oeffnet das Menue der Detailseite und tippt einen Eintrag. Ein Tipp
    /// „irgendwohin" zum Schliessen traefe in der Bildmitte womoeglich selbst
    /// einen Eintrag - deshalb nur an den linken Rand.
    @MainActor
    private func openMenu(_ app: XCUIApplication, _ item: String, snapMenu: String? = nil) -> Bool {
        let menu = app.buttons["detailMenu"]
        guard menu.waitForExistence(timeout: 5), menu.isHittable else { return false }
        menu.tap()
        let entry = app.buttons[item]
        guard entry.waitForExistence(timeout: 3) else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.5)).tap()
            return false
        }
        if let snapMenu {
            Thread.sleep(forTimeInterval: 0.5)
            snap(app, snapMenu)
        }
        entry.tap()
        return true
    }

    @MainActor
    func testTourOfAllScreens() throws {
        let ids = try cohabitIds()
        defer { XCUIDevice.shared.appearance = .light }

        // Heute: Dashboard, Liste - jeweils oben und weiter unten.
        var app = launch()
        XCTAssertTrue(app.buttons["tab-new"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 1.5)
        snap(app, "heute-dashboard")
        scrollDown(app, times: 2)
        snap(app, "heute-dashboard-unten")
        app.terminate()
        app = launch(extra: ["COCKPIT_TODAY_MODE": "list"])
        XCTAssertTrue(app.buttons["tab-new"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 1.5)
        snap(app, "heute-liste")
        scrollDown(app, times: 2)
        snap(app, "heute-liste-unten")

        // Streak mit Menue und allen Blaettern dahinter.
        if let laufen = ids["Laufen"] {
            app.terminate()
            app = launch(link: "cohabit://cohabit/\(laufen)")
            XCTAssertTrue(app.buttons["detailMenu"].waitForExistence(timeout: 15))
            Thread.sleep(forTimeInterval: 1)
            snap(app, "detail-streak")
            for (item, name) in [("Mitglieder", "blatt-mitglieder"), ("Pausen", "blatt-pausen"),
                                 ("Einladen", "blatt-einladen"), ("Benachrichtigungen", "blatt-benachrichtigungen"),
                                 ("Meine Einträge", "blatt-eintraege"), ("Bearbeiten", "blatt-bearbeiten")] {
                if openMenu(app, item, snapMenu: item == "Mitglieder" ? "detail-menue" : nil) {
                    Thread.sleep(forTimeInterval: 1.2)
                    snap(app, name)
                    closeSheet(app)
                }
            }
            let checkIn = app.buttons["detailCheckIn"]
            if checkIn.waitForExistence(timeout: 5), checkIn.isEnabled {
                checkIn.tap()
                if app.buttons["photoGallery"].waitForExistence(timeout: 5) {
                    Thread.sleep(forTimeInterval: 0.8)
                    snap(app, "beweisfoto-blatt")
                    closeSheet(app)
                }
            }
            app.buttons["segment-Chat"].tap()
            Thread.sleep(forTimeInterval: 1.5)
            snap(app, "chat")
        }

        // Abstinenz mit Rueckfrage vor der Unterbrechung.
        if let zucker = ids["Ohne Zucker"] {
            app.terminate()
            app = launch(link: "cohabit://cohabit/\(zucker)")
            XCTAssertTrue(app.buttons["detailCheckIn"].waitForExistence(timeout: 15))
            Thread.sleep(forTimeInterval: 1)
            snap(app, "detail-abstinenz")
            app.buttons["detailCheckIn"].tap()
            Thread.sleep(forTimeInterval: 0.8)
            snap(app, "unterbrechung-rueckfrage")
            let cancel = app.buttons["Abbrechen"]
            if cancel.exists { cancel.tap() }
        }

        // Ziel mit Wert-Blatt.
        if let schritte = ids["1 Mio. Schritte"] {
            app.terminate()
            app = launch(link: "cohabit://cohabit/\(schritte)")
            XCTAssertTrue(app.buttons["detailCheckIn"].waitForExistence(timeout: 15))
            Thread.sleep(forTimeInterval: 1)
            snap(app, "detail-ziel")
            app.buttons["detailCheckIn"].tap()
            if app.textFields["checkinValue"].waitForExistence(timeout: 5) {
                snap(app, "wert-blatt")
                closeSheet(app)
            }
        }

        // Challenge.
        if let kochen = ids["Wer kocht öfter?"] {
            app.terminate()
            app = launch(link: "cohabit://cohabit/\(kochen)")
            XCTAssertTrue(app.buttons["detailMenu"].waitForExistence(timeout: 15))
            Thread.sleep(forTimeInterval: 1)
            snap(app, "detail-challenge")
            scrollDown(app)
            snap(app, "detail-challenge-unten")
        }

        // Beendete Challenge: der Abschlussdialog, dann „Gratulieren".
        if let first = ids["Erster bei 42 km"] {
            app.terminate()
            app = launch(link: "cohabit://cohabit/\(first)")
            let congratulate = app.buttons["dialogCongratulate"]
            if congratulate.waitForExistence(timeout: 10) {
                Thread.sleep(forTimeInterval: 0.8)
                snap(app, "challenge-beendet")
                congratulate.tap()
                Thread.sleep(forTimeInterval: 2)
                snap(app, "gratulieren-chat")
            } else {
                snap(app, "detail-challenge-beendet")
            }
        }

        // Timeline, mit und ohne Filter.
        app.terminate()
        app = launch(tab: "timeline")
        XCTAssertTrue(app.buttons["filter-all"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1.5)
        snap(app, "timeline")
        if let laufen = ids["Laufen"], app.buttons["filter-\(laufen)"].exists {
            // Die Chips liegen in einer waagrechten Liste; mit den Co-Habits
            // frueherer Testlaeufe steht „Laufen" rechts ausserhalb des Bildes.
            let chip = app.buttons["filter-\(laufen)"]
            let row = app.buttons["filter-all"].frame.midY
            let origin = app.coordinate(withNormalizedOffset: .zero)
            var drags = 0
            // Nach dem Rahmen, nicht isHittable - das bricht ausserhalb des Bildes ab.
            while !app.frame.contains(chip.frame) && drags < 12 {
                origin.withOffset(CGVector(dx: app.frame.width * 0.85, dy: row))
                    .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: app.frame.width * 0.25, dy: row)))
                drags += 1
            }
            chip.tap()
            Thread.sleep(forTimeInterval: 1.5)
            snap(app, "timeline-filter")
        }

        // Statistik: Woche, Monat, Jahr.
        app.terminate()
        app = launch(tab: "stats")
        XCTAssertTrue(app.buttons["segment-Woche"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1.5)
        snap(app, "statistik-monat")
        app.buttons["segment-Woche"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        snap(app, "statistik-woche")
        app.buttons["segment-Jahr"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        snap(app, "statistik-jahr")

        // Profil und seine Seiten.
        app.terminate()
        app = launch(tab: "profile")
        XCTAssertTrue(app.buttons["editProfile"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1)
        snap(app, "profil")
        for (label, name) in [("Benachrichtigungen", "profil-benachrichtigungen"),
                              ("Health-Verbindung", "profil-health"),
                              ("Freunde & Einladungen", "profil-freunde"),
                              ("Archivierte Co-Habits", "profil-archiv"),
                              ("Daten exportieren", "profil-export"),
                              ("App verbinden", "profil-app-verbinden")] {
            let row = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
            if !row.isHittable { scrollDown(app) }
            guard row.waitForExistence(timeout: 5) else { continue }
            row.tap()
            Thread.sleep(forTimeInterval: 1.5)
            snap(app, name)
            let back = app.buttons["Zurück"]
            if back.exists { back.tap() }
            Thread.sleep(forTimeInterval: 0.6)
        }
        scrollUp(app, times: 2)
        if app.buttons["editProfile"].waitForExistence(timeout: 5) {
            app.buttons["editProfile"].tap()
            Thread.sleep(forTimeInterval: 1)
            snap(app, "profil-bearbeiten")
            let back = app.buttons["Zurück"]
            if back.exists { back.tap() }
        }
        scrollDown(app, times: 2)
        let delete = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Account löschen'")).firstMatch
        if delete.waitForExistence(timeout: 5) {
            delete.tap()
            Thread.sleep(forTimeInterval: 0.8)
            snap(app, "account-loeschen-rueckfrage")
            let cancel = app.buttons["Abbrechen"]
            if cancel.exists { cancel.tap() }
        }

        // Anlegen: die vier Typen in Schritt 2, dann Schritt 3 - ohne zu starten.
        app.terminate()
        app = launch(tab: "new")
        XCTAssertTrue(app.buttons["createType-STREAK"].waitForExistence(timeout: 15))
        snap(app, "anlegen-1")
        for type in ["GOAL", "CHALLENGE", "ABSTINENCE", "STREAK"] {
            app.buttons["createType-\(type)"].tap()
            let field = app.textFields["createName"]
            guard field.waitForExistence(timeout: 5) else { continue }
            snap(app, "anlegen-2-\(type.lowercased())")
            if type == "STREAK" {
                field.tap()
                field.typeText("Laufen")
                app.buttons["choice-pro Woche"].tap()
                snap(app, "anlegen-2-streak-name")
                scrollDown(app, times: 2)
                snap(app, "anlegen-2-streak-unten")
                app.buttons["createNext"].tap()
                if app.buttons["createStart"].waitForExistence(timeout: 5) {
                    Thread.sleep(forTimeInterval: 1)
                    snap(app, "anlegen-3")
                }
            } else {
                app.buttons["createBack"].tap()
            }
        }

        // Einladung: als zweite Person anlegen, Dialog zeigen, ablehnen.
        if !otherToken.isEmpty {
            let me = try request("GET", "/me", body: nil, token: token)
            let meId = (me["person"] as? [String: Any])?["id"] as? String ?? "felix"
            let name = "Rundgang \(Int(Date().timeIntervalSince1970) % 100_000)"
            _ = try request("POST", "/cohabits", body: [
                "type": "STREAK", "name": name, "color": "rose", "timezone": "Europe/Berlin",
                "tracking": ["mode": "CHECK"], "photoRequired": true, "backfillHours": 48,
                "reminderTime": NSNull(), "membersCanInvite": false,
                "streak": ["rhythm": ["kind": "TIMES_PER_WEEK", "times": 3], "groupStreak": false],
                "abstinence": NSNull(), "goal": NSNull(), "challenge": NSNull(), "health": NSNull(), "auto": NSNull(),
                "invitePersonIds": [meId],
            ], token: otherToken)
            app.terminate()
            app = launch()
            let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'invitation-'"))
                .containing(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
            if card.waitForExistence(timeout: 15) {
                snap(app, "heute-mit-einladung")
                card.tap()
                if app.buttons["inviteDecline"].waitForExistence(timeout: 5) {
                    Thread.sleep(forTimeInterval: 0.8)
                    snap(app, "einladung-dialog")
                    app.buttons["inviteDecline"].tap()
                }
            }
        }

        // Kacheln mit echten Daten.
        app.terminate()
        app = launch(tab: "widget")
        Thread.sleep(forTimeInterval: 3)
        snap(app, "kacheln")
        scrollDown(app, times: 2)
        snap(app, "kacheln-unten")
    }

    // MARK: - API

    private func cohabitIds() throws -> [String: String] {
        let list = try requestArray("/cohabits", token: token)
        var ids: [String: String] = [:]
        for summary in list {
            if let ref = summary["ref"] as? [String: Any], let name = ref["name"] as? String, let id = ref["id"] as? String {
                ids[name] = id
            }
        }
        return ids
    }

    private func requestArray(_ path: String, token: String) throws -> [[String: Any]] {
        let data = try raw("GET", path, body: nil, token: token)
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private func request(_ method: String, _ path: String, body: [String: Any]?, token: String) throws -> [String: Any] {
        let data = try raw(method, path, body: body, token: token)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func raw(_ method: String, _ path: String, body: [String: Any]?, token: String) throws -> Data {
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
                result = .failure(NSError(domain: "coHabit", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "\(method) \(path): \(http.statusCode) \(String(decoding: data ?? Data(), as: UTF8.self))"]))
            } else {
                result = .success(data ?? Data())
            }
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 20)
        return try result.get()
    }
}
