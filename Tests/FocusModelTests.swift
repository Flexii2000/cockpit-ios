import XCTest
@testable import Healthy

/// Die Fokus-Sessions des Waldes, so wie der Habits-Dienst sie liefert und
/// annimmt. Die Habits selbst sind nach coHabit umgezogen - ihre Tests
/// liegen bei coHabit (CohabitTests).
final class FocusModelTests: XCTestCase {

    /// Eine Session, wie `/api/focus/sessions` sie liefert - Zeitpunkte mit
    /// Nachkommastellen, der Tag als yyyy-MM-dd.
    func testDecodesFocusSession() throws {
        let session = try APIClient.decoder().decode([FocusSession].self, from: """
        [{"id":"a1","start":"2026-09-20T12:00:00.123456Z","end":"2026-09-20T13:30:00Z",
          "minutes":90,"day":"2026-09-20"}]
        """.data(using: .utf8)!)[0]
        XCTAssertEqual(session.minutes, 90)
        XCTAssertEqual(session.day, CalendarDate(year: 2026, month: 9, day: 20))
        XCTAssertEqual(session.end.timeIntervalSince(session.start), 5_400, accuracy: 1)
    }

    /// Was die App meldet, muss Jacksons `Instant` lesen koennen: ISO mit `Z`,
    /// keine Sekunden-seit-2001.
    func testFocusSessionDraftSendsInstants() throws {
        let start = Date(timeIntervalSince1970: 1_789_000_000)
        let draft = FocusSessionDraft(id: "b2", start: start, end: start.addingTimeInterval(1_800))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: APIClient.encoder().encode(draft)) as? [String: Any])
        XCTAssertEqual(object["id"] as? String, "b2")
        XCTAssertEqual(object["start"] as? String, "2026-09-10T00:26:40Z")
        XCTAssertEqual(object["end"] as? String, "2026-09-10T00:56:40Z")
        // Und zurueck: derselbe Zeitpunkt, wie ihn der Dienst spaeter liefert.
        XCTAssertEqual(APIClient.parseInstant("2026-09-10T00:26:40Z"), start)
    }

    // MARK: - Kategorien (seit 2026-10-01)

    /// Ein Baum mit Kategorie traegt Kennung und Namen; einer von frueher hat
    /// beides nicht - und darf deshalb nicht scheitern.
    func testDecodesSessionCategory() throws {
        let sessions = try APIClient.decoder().decode([FocusSession].self, from: """
        [{"id":"a1","start":"2026-10-01T08:00:00Z","end":"2026-10-01T09:00:00Z","minutes":60,
          "day":"2026-10-01","categoryId":"ed49-2245","categoryName":"Bachelorarbeit"},
         {"id":"a2","start":"2026-09-30T08:00:00Z","end":"2026-09-30T09:00:00Z","minutes":60,
          "day":"2026-09-30","categoryId":null,"categoryName":null},
         {"id":"a3","start":"2026-09-29T08:00:00Z","end":"2026-09-29T09:00:00Z","minutes":60,
          "day":"2026-09-29"}]
        """.data(using: .utf8)!)
        XCTAssertEqual(sessions[0].categoryId, "ed49-2245")
        XCTAssertEqual(sessions[0].categoryName, "Bachelorarbeit")
        XCTAssertNil(sessions[1].categoryId)
        XCTAssertNil(sessions[2].categoryName)
    }

    /// Ohne Kategorie fehlt der Schluessel ganz - der Rumpf sieht aus wie vor
    /// den Kategorien; mit geht ihre Kennung mit.
    func testDraftSendsCategoryOnlyWhenChosen() throws {
        let start = Date(timeIntervalSince1970: 1_789_000_000)
        let plain = try object(FocusSessionDraft(id: "b2", start: start, end: start.addingTimeInterval(60)))
        XCTAssertFalse(plain.keys.contains("categoryId"))
        let tagged = try object(FocusSessionDraft(id: "b3", start: start, end: start.addingTimeInterval(60),
                                                  categoryId: "ed49-2245"))
        XCTAssertEqual(tagged["categoryId"] as? String, "ed49-2245")
        let create = try object(FocusCategoryDraft(name: "Uni"))
        XCTAssertEqual(create as NSDictionary, ["name": "Uni"])
    }

    /// Die zuletzt benutzte Kategorie bleibt je Geraet: vor dem ersten Laden
    /// steht sie so da, wie sie gemerkt ist; nach dem Laden mit dem Namen aus
    /// der Liste (umbenannt) oder gar nicht mehr (geloescht).
    func testCategoryMemoryPreselectsTheLastUsed() throws {
        let suite = "FocusModelTests.memory"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let memory = FocusCategoryMemory(defaults: defaults)
        XCTAssertNil(memory.lastUsed)
        XCTAssertNil(memory.preselection(from: nil))

        let thesis = FocusCategory(id: "c-1", name: "Bachelorarbeit")
        memory.lastUsed = thesis
        XCTAssertEqual(FocusCategoryMemory(defaults: defaults).lastUsed, thesis, "nach dem Neustart vergessen")
        XCTAssertEqual(memory.preselection(from: nil), thesis)
        XCTAssertEqual(memory.preselection(from: [FocusCategory(id: "c-2", name: "Uni"),
                                                  FocusCategory(id: "c-1", name: "BA")]),
                       FocusCategory(id: "c-1", name: "BA"))
        XCTAssertNil(memory.preselection(from: [FocusCategory(id: "c-2", name: "Uni")]))
        XCTAssertNil(memory.preselection(from: []))

        memory.lastUsed = nil
        XCTAssertNil(defaults.data(forKey: FocusCategoryMemory.key))
    }

    /// Die Zeile eines Tages: die meisten Minuten zuerst, Gleichstand in der
    /// Reihenfolge des Pflanzens, Baeume ohne Kategorie als „Ohne Kategorie" -
    /// und ganz ohne Kategorien keine Zeile.
    func testCategoryBreakdownOfADay() {
        func tree(_ minutes: Int, _ category: String?, at hour: Int) -> FocusSession {
            let start = Date(timeIntervalSince1970: 1_790_000_000 + Double(hour) * 3_600)
            return FocusSession(id: UUID().uuidString, start: start, end: start.addingTimeInterval(Double(minutes) * 60),
                                minutes: minutes, day: CalendarDate(year: 2026, month: 10, day: 1),
                                categoryId: category.map { "id-\($0)" }, categoryName: category)
        }
        XCTAssertNil(FocusCategoryBreakdown.text([tree(60, nil, at: 1), tree(30, nil, at: 2)]))
        XCTAssertEqual(FocusCategoryBreakdown.text([tree(30, "Uni", at: 1), tree(60, "Bachelorarbeit", at: 2),
                                                     tree(30, "Bachelorarbeit", at: 3)]),
                       "Bachelorarbeit 1:30 · Uni 0:30")
        XCTAssertEqual(FocusCategoryBreakdown.text([tree(20, nil, at: 1), tree(20, "Uni", at: 2)]),
                       "Ohne Kategorie 0:20 · Uni 0:20")
    }

    private func object(_ value: some Encodable) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: APIClient.encoder().encode(value)) as? [String: Any])
    }

    /// „2:15/4:00 h" - der Stand von heute gegen das Tagesziel.
    func testFormatsMinutesAsHours() {
        XCTAssertEqual(FocusMinutes.hours(0), "0:00")
        XCTAssertEqual(FocusMinutes.hours(605), "10:05")
        XCTAssertEqual(FocusMinutes.progress(135, goal: 240), "2:15/4:00 h")
    }

    /// Die Habits-Kachel ist weg; die Kennung darf nicht mehr auftauchen,
    /// sonst laedt die App eine Kachel neu, die es nicht gibt.
    func testWidgetKindsWithoutHabits() {
        XCTAssertEqual(WidgetKind.focus, "FocusCountdown")
        XCTAssertEqual(WidgetKind.calories, "CaloriesRemaining")
    }
}
