import XCTest

/// Fokus nach dem Umzug der Habits nach coHabit: To-Do vorn, der Wald
/// daneben, kein Habits-Tab mehr. Seit 14.10. dazu Einkauf und Evaluation
/// (aus Healthy).
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

    /// Gegen einen lokalen To-Do-Dienst (COCKPIT_URL_TODO=http://127.0.0.1:…): eine neue
    /// Aufgabe steht sofort da und laesst sich gleich abhaken - die Kennung vergibt
    /// die App. Was beim Dienst ankam, prueft der Aufrufer danach per curl.
    func testANewTaskShowsAtOnceAndCanBeCheckedRightAway() throws {
        let url = ProcessInfo.processInfo.environment["COCKPIT_URL_TODO"] ?? ""
        try XCTSkipIf(!url.hasPrefix("http://127.0.0.1"), "nur gegen einen lokalen To-Do-Dienst")
        let app = start(tab: "todo", extra: ["COCKPIT_URL_TODO": url])
        let field = app.textFields["newTodo"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 20), "kein Brett")
        field.tap()
        field.typeText("Aufgabe aus dem UI-Test\n")
        let row = app.staticTexts["Aufgabe aus dem UI-Test"]
        XCTAssertTrue(row.waitForExistence(timeout: 3), "die Aufgabe stand nicht sofort da")
        let cell = app.cells.containing(.staticText, identifier: "Aufgabe aus dem UI-Test").firstMatch
        cell.buttons.firstMatch.tap()
        sleep(2)
        shoot(app, "todo-sofort")
    }

    /// „Heute" gegen einen lokalen To-Do-Dienst: in „Privat" holt die Sonne in der
    /// Zeile eine Aufgabe, in „Heute" steht sie dann unten, „Ordnen" zeigt die
    /// Griffe, Wischen nach links nimmt sie wieder raus; eine Aufgabe ohne Bereich
    /// steht sofort da.
    /// Erwartet in „Privat" eine offene Aufgabe „Fahrrad reparieren", die noch nicht
    /// geholt ist, und in „Heute" schon mindestens eine andere.
    ///
    /// Wischen auf einer Zeile in den Bereichen prueft er nicht: das blaetternde
    /// TabView nimmt sich die Geste und zeigt den naechsten Bereich (26.10.).
    @MainActor
    func testPickIntoTodayOrderAndTakeOut() throws {
        let url = ProcessInfo.processInfo.environment["COCKPIT_URL_TODO"] ?? ""
        try XCTSkipIf(!url.hasPrefix("http://127.0.0.1"), "nur gegen einen lokalen To-Do-Dienst")
        let app = start(tab: "todo", extra: ["COCKPIT_URL_TODO": url, "COCKPIT_TODO_MODE": "lists",
                                             "COCKPIT_TODO_AREA": "Privat"])
        let cell = app.cells.containing(.staticText, identifier: "Fahrrad reparieren").firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 20), "keine Aufgabe zum Holen")
        cell.buttons["Nach Heute holen"].tap()
        XCTAssertTrue(cell.buttons["Aus Heute nehmen"].waitForExistence(timeout: 3), "die Sonne wurde nicht orange")
        shoot(app, "heute-geholt")

        app.segmentedControls["todoMode"].buttons["Heute"].tap()
        let picked = app.cells.containing(.staticText, identifier: "Fahrrad reparieren").firstMatch
        XCTAssertTrue(picked.waitForExistence(timeout: 3), "nicht in Heute")
        XCTAssertFalse(app.cells.firstMatch.staticTexts["Fahrrad reparieren"].exists, "sollte hinten stehen")
        shoot(app, "heute-unten")
        // Ordnen: die Griffe von iOS erscheinen. Ziehen kann XCUITest sie in dieser
        // Liste nicht - weder per Element noch per Koordinate kam ein `onMove` an
        // (26.10.); das prueft Felix auf dem Geraet, die Reihenfolge selbst die
        // Unit-Tests (`TodoTodayOverlayTests`, `TodoTodayTest` im Dienst).
        app.buttons["orderToday"].tap()
        let handle = picked.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'reorder'")).firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 3), "kein Griff zum Ordnen")
        shoot(app, "heute-ordnen")
        app.buttons["orderToday"].tap()
        XCTAssertTrue(handle.waitForNonExistence(timeout: 3), "„Fertig“ beendet das Ordnen nicht")

        // Wischen nach links: hier blaettert nichts.
        picked.swipeLeft()
        let out = app.buttons["Raus"].firstMatch
        _ = out.waitForExistence(timeout: 3)
        shoot(app, "heute-raus")
        XCTAssertTrue(out.exists, "kein „Raus“ beim Wischen")
        out.tap()
        XCTAssertTrue(picked.waitForNonExistence(timeout: 3), "noch in Heute")

        let field = app.textFields["newTodayTodo"].firstMatch
        field.tap()
        field.typeText("Ohne Bereich aus dem UI-Test\n")
        XCTAssertTrue(app.staticTexts["Ohne Bereich aus dem UI-Test"].waitForExistence(timeout: 3))
        shoot(app, "heute-ohne-bereich")
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

        // Die Tageszeile ist ein Knopf (sie oeffnet die Baeume des Tages) -
        // ihre Texte stehen in seinem Label.
        let day = app.buttons.matching(identifier: "forestDay").firstMatch
        for _ in 0..<4 where !(day.exists && day.isHittable) { scrollDown(app) }
        XCTAssertTrue(day.waitForExistence(timeout: 10), "keine Tageszeile")
        XCTAssertTrue(day.label.contains("\(name) 0:01"), day.label)
        snap(app, "wald-tag")
    }

    /// Kategorie vergessen, Baum waechst schon: die Kategorie in der Karte
    /// antippen und waehlen - der fertige Baum steht mit ihr beim Dienst.
    /// Pflanzt wirklich und wartet die Minute ab, nur gegen einen lokalen Dienst.
    @MainActor
    func testChangeTheCategoryWhileTheTreeGrows() throws {
        try XCTSkipIf(!habitsURL.hasPrefix("http://127.0.0.1") && !habitsURL.hasPrefix("http://localhost"),
                      "COCKPIT_URL_HABITS muss auf einen lokalen Dienst zeigen - siehe tools/uitest.sh")
        let name = "Thesis \(Int(Date().timeIntervalSince1970) % 100_000)"
        let category = try XCTUnwrap(try send("POST", "/api/focus/categories", body: #"{"name":"\#(name)"}"#)["id"]
                                     as? String)
        cleanUp("DELETE", "/api/focus/categories/\(category)")
        let app = start(tab: "forest", extra: [
            "COCKPIT_URL_HABITS": habitsURL,
            "COCKPIT_URL_COHABIT": environment["COCKPIT_URL_COHABIT"] ?? "",
            "COCKPIT_NO_SCREENTIME": "1",
            "COCKPIT_NO_SHORTCUTS": "1",
            "COCKPIT_FOREST_RANGE": "today",
        ])

        let menu = app.buttons["forestMenu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 25))
        menu.tap()
        app.buttons["Eigene Dauer …"].tap()
        let minutes = app.alerts.textFields.firstMatch
        XCTAssertTrue(minutes.waitForExistence(timeout: 5))
        minutes.tap()
        minutes.typeText("1")
        app.alerts.buttons["Pflanzen"].tap()

        let running = app.buttons["sessionCategory"]
        XCTAssertTrue(running.waitForExistence(timeout: 10), "die laufende Session hat keinen Knopf fuer die Kategorie")
        running.tap()
        let row = app.buttons[name]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "die Kategorie steht nicht im Blatt")
        row.tap()
        let chosen = NSPredicate(format: "label CONTAINS %@", name)
        XCTAssertTrue(XCTWaiter.wait(for: [expectation(for: chosen, evaluatedWith: running)], timeout: 10) == .completed,
                      "die Karte zeigt die neue Kategorie nicht: \(running.label)")
        snap(app, "wald-laeuft-umkategorisiert")

        XCTAssertTrue(app.buttons["plantTree"].waitForExistence(timeout: 100), "die Session ist nicht zu Ende gegangen")
        let planted = try sessionsOfToday().first { $0["categoryId"] as? String == category }
        let tree = try XCTUnwrap(planted?["id"] as? String, "der Baum steht nicht mit der neuen Kategorie beim Dienst")
        cleanUp("DELETE", "/api/focus/sessions/\(tree)")
    }

    /// Ein fertiger Baum ohne Kategorie: Tag antippen, Baum antippen,
    /// Kategorie waehlen - der Dienst kennt sie danach, das Blatt zeigt sie.
    @MainActor
    func testChangeTheCategoryOfAFinishedTree() throws {
        try XCTSkipIf(!habitsURL.hasPrefix("http://127.0.0.1") && !habitsURL.hasPrefix("http://localhost"),
                      "COCKPIT_URL_HABITS muss auf einen lokalen Dienst zeigen - siehe tools/uitest.sh")
        let suffix = Int(Date().timeIntervalSince1970) % 100_000
        let name = "Bachelorarbeit \(suffix)"
        let category = try XCTUnwrap(try send("POST", "/api/focus/categories", body: #"{"name":"\#(name)"}"#)["id"]
                                     as? String)
        cleanUp("DELETE", "/api/focus/categories/\(category)")
        // Vor fuenf Minuten zu Ende, eine Minute lang - heute, ohne Kategorie.
        let end = Date().addingTimeInterval(-300)
        let iso = ISO8601DateFormatter()
        let id = "uitest-\(suffix)-tree"
        _ = try send("POST", "/api/focus/sessions", body: #"{"id":"\#(id)","start":"\#(iso.string(from: end.addingTimeInterval(-60)))","end":"\#(iso.string(from: end))"}"#)
        cleanUp("DELETE", "/api/focus/sessions/\(id)")

        let app = start(tab: "forest", extra: [
            "COCKPIT_URL_HABITS": habitsURL,
            "COCKPIT_URL_COHABIT": environment["COCKPIT_URL_COHABIT"] ?? "",
            "COCKPIT_NO_SCREENTIME": "1",
            "COCKPIT_NO_SHORTCUTS": "1",
            "COCKPIT_FOREST_RANGE": "today",
        ])
        let day = app.buttons.matching(identifier: "forestDay").firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 25), "keine Tageszeile")
        for _ in 0..<4 where !day.isHittable { scrollDown(app) }
        day.tap()

        let clock = DateFormatter()
        clock.locale = Locale(identifier: "de_DE")
        clock.dateFormat = "HH:mm"
        let times = "\(clock.string(from: end.addingTimeInterval(-60)))–\(clock.string(from: end))"
        let tree = app.buttons.matching(identifier: "forestTree")
            .matching(NSPredicate(format: "label CONTAINS %@", times)).firstMatch
        XCTAssertTrue(tree.waitForExistence(timeout: 10), "der Baum \(times) steht nicht im Blatt des Tages")
        XCTAssertTrue(tree.label.contains("Ohne Kategorie"), tree.label)
        snap(app, "wald-tag-baeume")
        tree.tap()

        let row = app.buttons[name]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "die Kategorie steht nicht im Blatt")
        row.tap()
        let changed = NSPredicate(format: "label CONTAINS %@", name)
        XCTAssertTrue(XCTWaiter.wait(for: [expectation(for: changed, evaluatedWith: tree)], timeout: 10) == .completed,
                      "das Blatt des Tages zeigt die neue Kategorie nicht: \(tree.label)")
        snap(app, "wald-tag-umkategorisiert")
        let stored = try sessionsOfToday().first { $0["id"] as? String == id }
        XCTAssertEqual(stored?["categoryId"] as? String, category)
        XCTAssertEqual(stored?["categoryName"] as? String, name)
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

    // MARK: - Evaluation

    /// Ein Jahr erfundener Antworten (nur im Speicher): Antworten oben, darunter
    /// Linien, je Frage eine Heatmap und die Zusammenhaenge - unterhalb des
    /// ersten Bildschirms, den `run-simulator.sh` allein zeigt.
    func testEvaluationShowsAnswersChartAndHeatmaps() {
        let app = start(tab: "evaluation", extra: ["COCKPIT_EVALUATION_DEMO": "1"])
        XCTAssertTrue(app.staticTexts["Frage A"].firstMatch.waitForExistence(timeout: 15))
        shoot(app, "evaluation-top")

        let three = app.buttons.matching(identifier: "3").firstMatch
        three.tap()
        XCTAssertTrue(three.isSelected, "die getippte Zahl ist gesetzt")
        three.tap()
        XCTAssertFalse(three.isSelected, "noch einmal nimmt sie zurueck")

        app.buttons["14 Tage"].tap()
        scrollDown(app, times: 2)
        shoot(app, "evaluation-fortnight")
        scrollUp(app, times: 3)

        app.buttons["1 Jahr"].tap()
        scrollDown(app, times: 2)
        shoot(app, "evaluation-year-heatmaps")
        scrollDown(app, times: 3)
        XCTAssertTrue(app.staticTexts["Zusammenhänge"].waitForExistence(timeout: 5))
        shoot(app, "evaluation-correlations")
        scrollDown(app, times: 4)
        shoot(app, "evaluation-bottom")
    }

    /// Ohne Fragen: festlegen, eine beantworten - mit einer frischen Datei je
    /// Lauf (`COCKPIT_EVALUATION_SCRATCH`), damit nichts liegen bleibt.
    func testEvaluationQuestionsCanBeSetUp() {
        let app = start(tab: "evaluation", extra: ["COCKPIT_EVALUATION_SCRATCH": "1"])
        let setUp = app.buttons["Fragen festlegen"]
        XCTAssertTrue(setUp.waitForExistence(timeout: 15))
        shoot(app, "evaluation-empty")
        setUp.tap()

        let field = app.textFields["Frage"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Frage X")
        let shortLabel = app.textFields["Kurzname"].firstMatch
        shortLabel.tap()
        shortLabel.typeText("Kurz X")
        shoot(app, "evaluation-questions-sheet")
        app.buttons["Fertig"].tap()

        XCTAssertTrue(app.staticTexts["Frage X"].firstMatch.waitForExistence(timeout: 5))
        let seven = app.buttons.matching(identifier: "7").firstMatch
        seven.tap()
        XCTAssertTrue(seven.isSelected)
        shoot(app, "evaluation-answered")
    }

    /// Die Evaluation steht in der Leiste - Einkauf nur mit Einkaufs-Token, wie
    /// vorher in Healthy.
    func testEvaluationTabIsInTheBar() {
        let app = start(tab: "", extra: ["COCKPIT_EVALUATION_SCRATCH": "1"])
        let evaluation = app.tabBars.buttons["Evaluation"]
        XCTAssertTrue(evaluation.waitForExistence(timeout: 20), "keine Evaluation in der Leiste")
        evaluation.tap()
        XCTAssertTrue(app.navigationBars["Evaluation"].waitForExistence(timeout: 10))
        shoot(app, "fokus-evaluation")
    }
}
