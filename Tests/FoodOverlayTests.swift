import XCTest
@testable import Healthy

/// Essen und Gewicht ohne Netz (Runde 4 vom 12.10.): was der Tag zeigt, solange
/// Eintraege warten - mit vorlaeufigen Summen -, und wie die Warteschlange sie
/// zusammenfasst. Nur Platzhalter („Gericht A“).
@MainActor
final class FoodOverlayTests: XCTestCase {

    private let today = CalendarDate(year: 2026, month: 10, day: 12)
    private let created = Date(timeIntervalSince1970: 1_791_800_000)
    /// 200 kcal, 10 g Eiweiss, 20 g KH, 5 g Fett je 100 g.
    private let per100g = Nutrients(kcal: 200, proteinG: 10, carbsG: 20, fatG: 5)

    private func entry(_ id: String, grams: Double, meal: Meal = .lunch, date: CalendarDate? = nil) -> FoodEntry {
        FoodEntry(id: id, date: date ?? today, dishId: "d-a", name: "Gericht A", grams: grams, per100g: per100g,
                  meal: meal, createdAt: created)
    }

    /// Wie der Dienst: Summe der Eintraege, Rest = Ziel minus Verzehrtes.
    private func day(_ entries: [FoodEntry], date: CalendarDate? = nil) throws -> DaySummary {
        let consumed = entries.reduce(Nutrients.zero) { $0 + $1.total }
        let targets = Nutrients(kcal: 2300, proteinG: 200, carbsG: 235.5, fatG: 62)
        let json: [String: Any] = [
            "date": (date ?? today).iso,
            "targets": ["kcal": targets.kcal, "proteinG": targets.proteinG, "carbsG": targets.carbsG,
                        "fatG": targets.fatG],
            "consumed": ["kcal": consumed.kcal, "proteinG": consumed.proteinG, "carbsG": consumed.carbsG,
                         "fatG": consumed.fatG],
            "remaining": ["kcal": targets.kcal - consumed.kcal, "proteinG": targets.proteinG - consumed.proteinG,
                          "carbsG": targets.carbsG - consumed.carbsG, "fatG": targets.fatG - consumed.fatG],
            "entries": entries.map { e in
                ["id": e.id, "date": e.date.iso, "dishId": e.dishId as Any, "name": e.name, "grams": e.grams,
                 "per100g": ["kcal": per100g.kcal, "proteinG": per100g.proteinG, "carbsG": per100g.carbsG,
                             "fatG": per100g.fatG],
                 "meal": e.meal?.rawValue as Any, "createdAt": "2026-10-12T08:00:00Z"]
            },
            "mealTargets": ["BREAKFAST": 575, "LUNCH": 805, "DINNER": 690, "SNACK": 230],
        ]
        return try APIClient.decoder().decode(DaySummary.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func add(_ id: String, grams: Double, date: CalendarDate? = nil) -> FoodChange {
        .add(id: id, date: date ?? today, meal: .dinner, grams: grams, dishId: "d-a", dish: nil, name: "Gericht A",
             per100g: per100g, at: created)
    }

    // MARK: - Overlay

    func testAWaitingEntryShowsAndTheSumsMoveProvisionally() throws {
        let base = try day([entry("e-1", grams: 100)])
        let shown = FoodOverlay.apply([add("e-2", grams: 50)], to: base)
        XCTAssertEqual(shown.entries.map(\.id), ["e-1", "e-2"], "neu ans Ende, wie beim Dienst")
        XCTAssertEqual(shown.entries.last?.meal, .dinner)
        XCTAssertEqual(shown.consumed.kcal, 300, accuracy: 0.001, "200 + 100 kcal")
        XCTAssertEqual(shown.remaining.kcal, 2000, accuracy: 0.001)
        XCTAssertEqual(shown.consumed.proteinG, 15, accuracy: 0.001)
        XCTAssertTrue(FoodOverlay.isProvisional([add("e-2", grams: 50)], day: base))
    }

    /// Kam die Antwort schon, steht der Eintrag beim Dienst - dann nicht doppelt.
    func testWhatTheServiceAlreadyHasIsNotCountedTwice() throws {
        let base = try day([entry("e-1", grams: 100), entry("e-2", grams: 50)])
        let shown = FoodOverlay.apply([add("e-2", grams: 50)], to: base)
        XCTAssertEqual(shown.entries.count, 2)
        XCTAssertEqual(shown.consumed.kcal, base.consumed.kcal)
        XCTAssertFalse(FoodOverlay.isProvisional([add("e-2", grams: 50)], day: base))
    }

    func testCorrectingAndDeleting() throws {
        let base = try day([entry("e-1", grams: 100), entry("e-2", grams: 50)])
        let corrected = FoodOverlay.apply([.update(id: "e-1", grams: 150, meal: nil, date: nil)], to: base)
        XCTAssertEqual(corrected.entries.map(\.grams), [150, 50], "an Ort und Stelle")
        XCTAssertEqual(corrected.entries.first?.meal, .lunch, "ohne Angabe bleibt die Mahlzeit")
        XCTAssertEqual(corrected.consumed.kcal, 400, accuracy: 0.001)

        let deleted = FoodOverlay.apply([.delete(id: "e-2")], to: base)
        XCTAssertEqual(deleted.entries.map(\.id), ["e-1"])
        XCTAssertEqual(deleted.consumed.kcal, 200, accuracy: 0.001)
    }

    /// Ein Eintrag wandert beim Berichtigen auf gestern: heute weg, gestern da.
    func testAnEntryMovingToAnotherDay() throws {
        let yesterday = today.adding(days: -1)
        let base = try day([entry("e-1", grams: 100)])
        let other = try day([], date: yesterday)
        let move: [FoodChange] = [.update(id: "e-1", grams: 100, meal: nil, date: yesterday)]
        XCTAssertTrue(FoodOverlay.apply(move, to: base).entries.isEmpty)
        let there = FoodOverlay.apply(move, to: other, known: base.entries)
        XCTAssertEqual(there.entries.map(\.id), ["e-1"])
        XCTAssertEqual(there.entries.first?.date, yesterday)
        XCTAssertEqual(there.consumed.kcal, 200, accuracy: 0.001)
    }

    func testNothingWaitingIsTheServiceDay() throws {
        let base = try day([entry("e-1", grams: 100)])
        XCTAssertEqual(FoodOverlay.apply([], to: base).consumed, base.consumed)
        let elsewhere = FoodOverlay.apply([add("e-9", grams: 80, date: today.adding(days: 2))], to: base)
        XCTAssertEqual(elsewhere.entries, base.entries, "ein anderer Tag aendert diesen nicht")
    }

    /// Die Kachel schreibt „vorläufig“, solange etwas mitzaehlt.
    func testTheWidgetValueKnowsItIsProvisional() throws {
        let base = try day([entry("e-1", grams: 100)])
        let shown = FoodOverlay.apply([add("e-2", grams: 50)], to: base)
        let value = RemainingCalories(day: shown, provisional: true)
        XCTAssertTrue(value.isProvisional)
        XCTAssertEqual(value.remaining.kcal, 2000, accuracy: 0.001)
        XCTAssertFalse(RemainingCalories(day: base).isProvisional)
        // Ein gemerkter Stand aus der Fassung davor (ohne das Feld) bleibt lesbar.
        let old = #"{"date":"2026-10-12","consumed":{"kcal":1,"proteinG":0,"carbsG":0,"fatG":0},"targets":{"kcal":2,"proteinG":0,"carbsG":0,"fatG":0},"remaining":{"kcal":1,"proteinG":0,"carbsG":0,"fatG":0},"fetchedAt":"2026-10-12T08:00:00Z"}"#
        let decoded = try APIClient.decoder().decode(RemainingCalories.self, from: Data(old.utf8))
        XCTAssertFalse(decoded.isProvisional)
    }

    // MARK: - Warteschlange

    private func queue() -> PendingChanges {
        let queue = PendingChanges(file: nil, transport: { _, _ in .offline }, sendsImmediately: false)
        queue.isForeground = false
        return queue
    }

    func testTheEntryTakesTheIdOfTheApp() throws {
        let request = add("3f2a8c1e-5b7d-4e9a-8c6f-1d2e3f4a5b6c", grams: 50).request
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/api/food/entries")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(body["id"] as? String, "3f2a8c1e-5b7d-4e9a-8c6f-1d2e3f4a5b6c")
        XCTAssertEqual(body["grams"] as? Double, 50)
        XCTAssertEqual(body["meal"] as? String, "DINNER")
        XCTAssertEqual(body["date"] as? String, "2026-10-12")
        XCTAssertEqual(FoodChange.delete(id: "e-1").request.notFoundMeansDone, true)
    }

    /// Berichtigen faltet sich in ein wartendes Anlegen; Loeschen von nur Lokalem schickt nichts.
    func testCorrectingAWaitingEntryFoldsIntoIt() {
        let queue = queue()
        queue.enqueue(.food(add("e-2", grams: 50)), label: "Gericht A")
        queue.enqueue(.food(.update(id: "e-2", grams: 80, meal: .lunch, date: nil)), label: "Gericht A")
        XCTAssertEqual(queue.count(for: .food), 1)
        guard case .food(.add(_, _, let meal, let grams, _, _, _, _, _)) = queue.changes(for: .food).first else {
            return XCTFail()
        }
        XCTAssertEqual(grams, 80)
        XCTAssertEqual(meal, .lunch)
        queue.enqueue(.food(.delete(id: "e-2")), label: "Gericht A")
        XCTAssertEqual(queue.count(for: .food), 0, "nur lokal - nichts geht raus")
    }

    /// Je Tag gilt das neueste Gewicht; andere Tage bleiben.
    func testTheNewestWeightPerDayWaits() throws {
        let queue = queue()
        queue.enqueue(.weight(.add(date: today, weightKg: 82.4)), label: "Gewicht")
        queue.enqueue(.weight(.add(date: today, weightKg: 82.1)), label: "Gewicht")
        queue.enqueue(.weight(.add(date: today.adding(days: -1), weightKg: 82.9)), label: "Gewicht")
        let waiting = queue.changes(for: .weight).compactMap(\.weightEntry)
        XCTAssertEqual(waiting.map(\.weightKg), [82.1, 82.9])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(waiting[0].request.body)) as? [String: Any])
        XCTAssertEqual(body["weightKg"] as? Double, 82.1)
        XCTAssertNil(body["keepExisting"], "von Hand ersetzt den Wert des Tages")
    }

    /// Was der Kalorienzaehler ablehnen wuerde, geht gar nicht erst in die Warteschlange -
    /// ohne Netz kaeme die Ablehnung erst beim Senden.
    func testOnlyWhatTheServiceTakesIsQueued() {
        func dish(kcal: Double? = 200, protein: Double? = 10, carbs: Double? = 20, fat: Double? = 5,
                  portion: Double? = nil, name: String = "Gericht A") -> DishRequest {
            DishRequest(name: name, kcal: kcal, proteinG: protein, carbsG: carbs, fatG: fat, portionG: portion)
        }
        XCTAssertTrue(FoodEntryRules.dish(dish()))
        XCTAssertFalse(FoodEntryRules.dish(dish(protein: nil)), "der Dienst verlangt Eiweiss")
        XCTAssertFalse(FoodEntryRules.dish(dish(kcal: 1_001)))
        XCTAssertFalse(FoodEntryRules.dish(dish(fat: 101)))
        XCTAssertFalse(FoodEntryRules.dish(dish(portion: 0)))
        XCTAssertFalse(FoodEntryRules.dish(dish(name: " ")))
        XCTAssertFalse(FoodEntryRules.dish(dish(name: String(repeating: "x", count: 81))))
        XCTAssertTrue(FoodEntryRules.dish(dish(kcal: 0, protein: 0, carbs: 0, fat: 0)), "Wasser hat nichts")
        XCTAssertTrue(FoodEntryRules.grams(150))
        XCTAssertFalse(FoodEntryRules.grams(0))
        XCTAssertFalse(FoodEntryRules.grams(20_001))
        XCTAssertFalse(FoodEntryRules.grams(nil))
    }

    /// Eine Ablehnung nennt den Eintrag; ein verschwundener ist ein Hinweis.
    func testNotices() {
        XCTAssertEqual(add("e-2", grams: 50).notice(label: "Gericht A", status: 400, message: "grams must be positive").text,
                       "„Gericht A“ wurde nicht eingetragen: grams must be positive")
        let gone = FoodChange.update(id: "e-1", grams: 1, meal: nil, date: nil)
            .notice(label: "Gericht A", status: 404, message: nil)
        XCTAssertTrue(gone.isInfo)
        XCTAssertEqual(WeightChange.add(date: today, weightKg: 82).notice(label: "Gewicht", status: 400, message: "zu schwer").text,
                       "Das Gewicht vom 12.10. wurde nicht eingetragen: zu schwer")
    }
}
