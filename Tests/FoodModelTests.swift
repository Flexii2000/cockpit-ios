import XCTest
@testable import Cockpit

/// Die Auszuege stammen aus den Java-Records in `../food/src/main/java/…`.
final class FoodModelTests: XCTestCase {

    func testDecodesDaySummaryWithMealTargets() throws {
        let json = Data("""
        {"date":"2026-09-01",
         "targets":{"kcal":2400,"proteinG":170,"carbsG":250,"fatG":80},
         "consumed":{"kcal":1850,"proteinG":120,"carbsG":190,"fatG":62},
         "remaining":{"kcal":550,"proteinG":50,"carbsG":60,"fatG":18},
         "entries":[],
         "mealTargets":{"BREAKFAST":600,"LUNCH":840,"DINNER":720,"SNACK":240}}
        """.utf8)
        let day = try APIClient.decoder().decode(DaySummary.self, from: json)
        XCTAssertEqual(day.consumed.kcal, 1850)
        XCTAssertEqual(day.targetsByMeal[.lunch], 840)
        XCTAssertEqual(day.targetsByMeal.count, 4)
    }

    /// Eintraege aus der Zeit vor der Mahlzeiten-Aufteilung haben `meal: null`.
    /// Die duerfen nicht durchs Raster fallen - sie landen im Abschnitt
    /// „Ohne Zuordnung".
    func testDecodesEntryWithoutMeal() throws {
        let json = Data("""
        {"id":"e1","date":"2026-09-01","dishId":"d1","name":"Skyr","grams":200,
         "per100g":{"kcal":63,"proteinG":11,"carbsG":4,"fatG":0.2},
         "meal":null,"createdAt":"2026-09-01T07:12:03.123456789Z"}
        """.utf8)
        let entry = try APIClient.decoder().decode(FoodEntry.self, from: json)
        XCTAssertNil(entry.meal)
        XCTAssertEqual(entry.total.kcal, 126, accuracy: 0.001)
        XCTAssertEqual(entry.total.proteinG, 22, accuracy: 0.001)
    }

    func testDecodesQuickCaptureJobWhileRunning() throws {
        let json = Data("""
        {"id":"job-1","status":"running","preview":null,"error":null,"elapsedSeconds":12}
        """.utf8)
        let job = try APIClient.decoder().decode(QuickCaptureJob.self, from: json)
        XCTAssertTrue(job.isRunning)
        XCTAssertNil(job.preview)
    }

    func testDecodesQuickCapturePreviewWithSources() throws {
        let json = Data("""
        {"id":"job-1","status":"done","error":null,"elapsedSeconds":41,
         "preview":{"known":false,"dishId":null,"name":"Spaghetti Bolognese",
          "per100g":{"kcal":142,"proteinG":7.2,"carbsG":16.1,"fatG":5.1},
          "portionG":450,"grams":450,"meal":"DINNER",
          "valueSources":{"kcal":"geschätzt","proteinG":"nachgeschlagen"},
          "note":"Portionsgröße geschätzt"}}
        """.utf8)
        let job = try APIClient.decoder().decode(QuickCaptureJob.self, from: json)
        XCTAssertFalse(job.isRunning)
        XCTAssertEqual(job.preview?.meal, .dinner)
        XCTAssertEqual(job.preview?.valueSources["kcal"], "geschätzt")
    }

    func testScalesPer100gToPortion() {
        let per100 = Nutrients(kcal: 200, proteinG: 10, carbsG: 20, fatG: 5)
        let scaled = per100.scaled(gramsOf: 250)
        XCTAssertEqual(scaled.kcal, 500, accuracy: 0.001)
        XCTAssertEqual(scaled.fatG, 12.5, accuracy: 0.001)
    }
}

final class NutritionToneTests: XCTestCase {

    private let targets = Nutrients(kcal: 2400, proteinG: 170, carbsG: 250, fatG: 80)

    /// Eiweiss ist ein Mindestwert: darueber ist das Ziel erreicht, knapp
    /// darunter ist noch kein Fehler.
    func testProteinIsAFloor() {
        let plenty = Nutrients(kcal: 0, proteinG: 175, carbsG: 0, fatG: 0)
        XCTAssertEqual(NutritionTone.tone(for: .protein, consumed: plenty, targets: targets), .good)

        let almost = Nutrients(kcal: 0, proteinG: 140, carbsG: 0, fatG: 0)   // 82 %
        XCTAssertEqual(NutritionTone.tone(for: .protein, consumed: almost, targets: targets), .near)

        let far = Nutrients(kcal: 0, proteinG: 60, carbsG: 0, fatG: 0)
        XCTAssertEqual(NutritionTone.tone(for: .protein, consumed: far, targets: targets), .neutral)
    }

    /// Fett und Kohlenhydrate sind Obergrenzen - dieselbe Zahl muss dort
    /// andersherum bewertet werden als beim Eiweiss.
    func testFatIsACeilingWithTolerance() {
        let under = Nutrients(kcal: 0, proteinG: 0, carbsG: 0, fatG: 70)
        XCTAssertEqual(NutritionTone.tone(for: .fat, consumed: under, targets: targets), .neutral)

        let slightlyOver = Nutrients(kcal: 0, proteinG: 0, carbsG: 0, fatG: 88)  // +8 g
        XCTAssertEqual(NutritionTone.tone(for: .fat, consumed: slightlyOver, targets: targets), .warn)

        let wellOver = Nutrients(kcal: 0, proteinG: 0, carbsG: 0, fatG: 100)     // +20 g
        XCTAssertEqual(NutritionTone.tone(for: .fat, consumed: wellOver, targets: targets), .bad)
    }

    func testKcalToleranceIs100() {
        let justOver = Nutrients(kcal: 2480, proteinG: 0, carbsG: 0, fatG: 0)
        XCTAssertEqual(NutritionTone.kcalTone(consumed: justOver, targets: targets), .warn)

        let farOver = Nutrients(kcal: 2600, proteinG: 0, carbsG: 0, fatG: 0)
        XCTAssertEqual(NutritionTone.kcalTone(consumed: farOver, targets: targets), .bad)
    }

    /// Ohne Ziel darf nichts eingefaerbt werden - sonst stuende jede Zahl
    /// sofort im Warnbereich.
    func testNoTargetMeansNeutral() {
        let none = Nutrients(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0)
        let consumed = Nutrients(kcal: 1000, proteinG: 50, carbsG: 100, fatG: 30)
        XCTAssertEqual(NutritionTone.kcalTone(consumed: consumed, targets: none), .bad)
        XCTAssertEqual(NutritionTone.tone(for: .protein, consumed: consumed, targets: none), .good)
    }
}
