import XCTest

/// Fokus nach dem Umzug der Habits nach coHabit: To-Do vorn, der Wald
/// daneben, kein Habits-Tab mehr.
final class FokusUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    /// Die Leiste hat zwei Eintraege, der erste ist To-Do.
    func testOpensOnTodoWithoutHabitsTab() {
        let app = start(tab: "", extra: [
            "COCKPIT_URL_TODO": ProcessInfo.processInfo.environment["COCKPIT_URL_TODO"] ?? "",
        ])
        let todo = app.tabBars.buttons["To-Do"]
        XCTAssertTrue(todo.waitForExistence(timeout: 20), "keine Leiste mit To-Do")
        shoot(app, "fokus-start")
        XCTAssertTrue(todo.isSelected, "To-Do muss vorn stehen")
        XCTAssertTrue(app.tabBars.buttons["Wald"].exists)
        XCTAssertFalse(app.tabBars.buttons["Habits"].exists, "der Habits-Tab ist nach coHabit umgezogen")
    }

    /// Der Wald laedt seine Baeume weiter vom Habits-Dienst und zeigt die Summe.
    func testForestShowsTheSummary() {
        let environment = ProcessInfo.processInfo.environment
        let app = start(tab: "forest", extra: [
            "COCKPIT_URL_HABITS": environment["COCKPIT_URL_HABITS"] ?? "",
            "COCKPIT_URL_COHABIT": environment["COCKPIT_URL_COHABIT"] ?? "",
            "COCKPIT_NO_SCREENTIME": "1",
            "COCKPIT_FOREST_RANGE": "week",
        ])
        let summary = app.staticTexts["forestSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 25), "Wald ohne Summe")
        shoot(app, "wald-woche")
        XCTAssertTrue(summary.label.contains("Baum") || summary.label.contains("Bäume"), summary.label)
    }

    // MARK: - Kategorien

    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var habitsURL: String { environment["COCKPIT_URL_HABITS"] ?? "" }
    private var token: String { environment["COCKPIT_FH_PRIVATE_TOKEN"] ?? "" }

    /// Baum mit Kategorie pflanzen: im Auswahlblatt eine neue Kategorie
    /// anlegen (sie ist dann gewaehlt), einen Baum von einer Minute pflanzen -
    /// die laufende Session zeigt die Kategorie, der fertige Baum steht mit ihr
    /// beim Dienst und in der Zeile des Tages. Nur gegen einen lokalen Dienst:
    /// der Test pflanzt wirklich und wartet die Minute ab.
    @MainActor
    func testPlantATreeWithACategory() throws {
        try XCTSkipIf(!habitsURL.hasPrefix("http://127.0.0.1") && !habitsURL.hasPrefix("http://localhost"),
                      "COCKPIT_URL_HABITS muss auf einen lokalen Dienst zeigen - siehe tools/uitest.sh")
        let name = "Lernen \(Int(Date().timeIntervalSince1970) % 100_000)"
        let app = start(tab: "forest", extra: [
            "COCKPIT_URL_HABITS": habitsURL,
            "COCKPIT_URL_COHABIT": environment["COCKPIT_URL_COHABIT"] ?? "",
            "COCKPIT_NO_SCREENTIME": "1",
            "COCKPIT_NO_SHORTCUTS": "1",
            "COCKPIT_FOREST_RANGE": "today",
        ])

        let choose = app.buttons["forestCategory"]
        XCTAssertTrue(choose.waitForExistence(timeout: 25), "kein Knopf fuer die Kategorie")
        snap(app, "wald-pflanzen")
        choose.tap()
        let field = app.textFields["newCategoryName"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Auswahlblatt ohne Feld fuer eine neue Kategorie")
        XCTAssertTrue(app.buttons["Ohne Kategorie"].exists)
        snap(app, "wald-kategorien")
        field.tap()
        field.typeText(name)
        app.buttons["createCategory"].tap()

        // Angelegt heisst gewaehlt: das Blatt geht zu, der Knopf traegt den Namen.
        let chosen = NSPredicate(format: "label CONTAINS %@", name)
        XCTAssertTrue(XCTWaiter.wait(for: [expectation(for: chosen, evaluatedWith: choose)], timeout: 10) == .completed,
                      "die neue Kategorie ist nicht gewaehlt: \(choose.label)")
        let category = try XCTUnwrap(try categories().first { $0["name"] as? String == name }?["id"] as? String,
                                     "die Kategorie ist beim Dienst nicht angekommen")
        cleanUp("DELETE", "/api/focus/categories/\(category)")

        app.buttons["forestMenu"].tap()
        app.buttons["Eigene Dauer …"].tap()
        let minutes = app.alerts.textFields.firstMatch
        XCTAssertTrue(minutes.waitForExistence(timeout: 5))
        minutes.tap()
        minutes.typeText("1")
        app.alerts.buttons["Pflanzen"].tap()

        let running = app.descendants(matching: .any).matching(identifier: "sessionCategory").firstMatch
        XCTAssertTrue(running.waitForExistence(timeout: 10), "die laufende Session zeigt keine Kategorie")
        XCTAssertTrue(running.label.contains(name), running.label)
        snap(app, "wald-laeuft")

        // Eine Minute, dann steht der Baum - und der Knopf zum Pflanzen ist zurueck.
        XCTAssertTrue(app.buttons["plantTree"].waitForExistence(timeout: 100), "die Session ist nicht zu Ende gegangen")
        let planted = try sessionsOfToday().first { $0["categoryId"] as? String == category }
        let tree = try XCTUnwrap(planted?["id"] as? String, "kein Baum mit der Kategorie beim Dienst")
        cleanUp("DELETE", "/api/focus/sessions/\(tree)")
        XCTAssertEqual(planted?["categoryName"] as? String, name)

        let day = app.staticTexts.matching(identifier: "dayCategories").firstMatch
        for _ in 0..<4 where !(day.exists && day.isHittable) { scrollDown(app) }
        XCTAssertTrue(day.waitForExistence(timeout: 10), "die Tageszeile zeigt keine Kategorien")
        XCTAssertTrue(day.label.contains("\(name) 0:01"), day.label)
        snap(app, "wald-tag")
    }

    /// Umbenennen per Langdruck, Loeschen per Wischen - im Auswahlblatt, ohne
    /// zu pflanzen. Der Dienst kennt danach den neuen Namen bzw. die Kategorie
    /// nicht mehr zur Auswahl.
    @MainActor
    func testRenameAndDeleteACategory() throws {
        try XCTSkipIf(!habitsURL.hasPrefix("http://127.0.0.1") && !habitsURL.hasPrefix("http://localhost"),
                      "COCKPIT_URL_HABITS muss auf einen lokalen Dienst zeigen - siehe tools/uitest.sh")
        let suffix = Int(Date().timeIntervalSince1970) % 100_000
        let name = "Seminar \(suffix)"
        let renamed = "Kolloquium \(suffix)"
        let created = try send("POST", "/api/focus/categories", body: #"{"name":"\#(name)"}"#)
        let id = try XCTUnwrap(created["id"] as? String)
        cleanUp("DELETE", "/api/focus/categories/\(id)")

        let app = start(tab: "forest", extra: [
            "COCKPIT_URL_HABITS": habitsURL,
            "COCKPIT_URL_COHABIT": environment["COCKPIT_URL_COHABIT"] ?? "",
            "COCKPIT_NO_SCREENTIME": "1",
            "COCKPIT_NO_SHORTCUTS": "1",
        ])
        let choose = app.buttons["forestCategory"]
        XCTAssertTrue(choose.waitForExistence(timeout: 25), "kein Knopf fuer die Kategorie")
        choose.tap()
        let row = app.buttons[name]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "die Kategorie steht nicht im Blatt")

        row.press(forDuration: 1.0)
        let rename = app.buttons["Umbenennen"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5), "Langdruck zeigt kein Umbenennen")
        snap(app, "wald-kategorie-menue")
        rename.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: name.count + 2) + renamed)
        app.alerts.buttons["Sichern"].tap()
        let renamedRow = app.buttons[renamed]
        XCTAssertTrue(renamedRow.waitForExistence(timeout: 10), "der neue Name steht nicht im Blatt")
        XCTAssertEqual(try categories().first { $0["id"] as? String == id }?["name"] as? String, renamed)

        renamedRow.swipeLeft()
        let delete = app.buttons["Löschen"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "Wischen zeigt kein Loeschen")
        snap(app, "wald-kategorie-wischen")
        delete.tap()
        XCTAssertTrue(renamedRow.waitForNonExistence(timeout: 10), "die Kategorie bleibt im Blatt")
        XCTAssertFalse(try categories().contains { $0["id"] as? String == id }, "der Dienst bietet sie weiter an")
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

    // MARK: - Dienst

    private func categories() throws -> [[String: Any]] {
        try list("/api/focus/categories")
    }

    private func sessionsOfToday() throws -> [[String: Any]] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        return try list("/api/focus/sessions?from=\(today)&to=\(today)")
    }

    private func list(_ path: String) throws -> [[String: Any]] {
        (try JSONSerialization.jsonObject(with: data("GET", path)) as? [[String: Any]]) ?? []
    }

    private func send(_ method: String, _ path: String, body: String) throws -> [String: Any] {
        (try JSONSerialization.jsonObject(with: data(method, path, body: body)) as? [String: Any]) ?? [:]
    }

    private func data(_ method: String, _ path: String, body: String? = nil) throws -> Data {
        var request = URLRequest(url: URL(string: habitsURL + path)!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(body.utf8)
        }
        let done = expectation(description: path)
        nonisolated(unsafe) var result: Result<Data, Error> = .failure(URLError(.unknown))
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                result = .failure(NSError(domain: "habits", code: http.statusCode,
                                          userInfo: [NSLocalizedDescriptionKey: "\(method) \(path): \(http.statusCode)"]))
            } else {
                result = .success(data ?? Data())
            }
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 20)
        return try result.get()
    }

    /// Raeumt nach dem Test weg, was er angelegt hat - auch nach einem Fehlschlag.
    private func cleanUp(_ method: String, _ path: String) {
        let url = URL(string: habitsURL + path)!
        let token = token
        addTeardownBlock {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
    }
}
