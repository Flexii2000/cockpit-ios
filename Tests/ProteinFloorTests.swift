import XCTest
@testable import Healthy

/// Eiweiss mit Erhalt und Ziel (seit 10.11., Vertrag §11.1): rot unter dem
/// Erhalt, gelb ab dem Erhalt, gruen ab dem Ziel.
final class ProteinFloorTests: XCTestCase {

    private let targets = Nutrients(kcal: 2300, proteinG: 195, carbsG: 236, fatG: 70, proteinMinG: 140)

    private func protein(_ grams: Double) -> Nutrients {
        Nutrients(kcal: 0, proteinG: grams, carbsG: 0, fatG: 0)
    }

    func testBelowTheFloorIsRed() {
        XCTAssertEqual(NutritionTone.tone(for: .protein, consumed: protein(0), targets: targets), .bad)
        XCTAssertEqual(NutritionTone.tone(for: .protein, consumed: protein(139.9), targets: targets), .bad)
    }

    func testFromTheFloorIsYellow() {
        XCTAssertEqual(NutritionTone.tone(for: .protein, consumed: protein(140), targets: targets), .warn)
        XCTAssertEqual(NutritionTone.tone(for: .protein, consumed: protein(194.9), targets: targets), .warn)
    }

    func testFromTheTargetIsGreen() {
        XCTAssertEqual(NutritionTone.tone(for: .protein, consumed: protein(195), targets: targets), .good)
        XCTAssertEqual(NutritionTone.tone(for: .protein, consumed: protein(260), targets: targets), .good)
    }

    /// Ein aelterer Dienst schickt keinen Erhalt - dann gilt die Regel von vorher.
    func testWithoutAFloorTheOldRuleApplies() {
        let old = Nutrients(kcal: 2300, proteinG: 195, carbsG: 236, fatG: 70)
        XCTAssertEqual(NutritionTone.tone(for: .protein, consumed: protein(60), targets: old), .neutral)
        XCTAssertEqual(NutritionTone.tone(for: .protein, consumed: protein(170), targets: old), .near)
        XCTAssertEqual(NutritionTone.tone(for: .protein, consumed: protein(195), targets: old), .good)
        XCTAssertEqual(NutritionTone.proteinTone(consumed: 60, target: 195, minimum: 0), .neutral)
    }

    /// Fett und Kohlenhydrate bleiben, wie sie sind - der Erhalt gehoert nur zum Eiweiss.
    func testFatAndCarbsAreUntouched() {
        let consumed = Nutrients(kcal: 0, proteinG: 0, carbsG: 250, fatG: 60)
        XCTAssertEqual(NutritionTone.tone(for: .fat, consumed: consumed, targets: targets), .neutral)
        XCTAssertEqual(NutritionTone.tone(for: .carbs, consumed: consumed, targets: targets), .warn)
    }

    // MARK: - Vom Dienst und zum Dienst

    /// Die Ziele im Tag, wie der Kalorienzaehler sie seit 10.11. schickt.
    func testDecodesTheFloorWithTheTargets() throws {
        let json = """
        {"date":"2026-11-10",
         "targets":{"kcal":2300.0,"proteinG":195.0,"carbsG":236.0,"fatG":70.0,
                    "proteinMinG":140.0,"proteinMinDefault":false},
         "consumed":{"kcal":1550.0,"proteinG":96.0,"carbsG":180.0,"fatG":41.0},
         "remaining":{"kcal":750.0,"proteinG":99.0,"carbsG":56.0,"fatG":29.0},
         "entries":[],"mealTargets":{"BREAKFAST":575.0}}
        """
        let day = try APIClient.decoder().decode(DaySummary.self, from: Data(json.utf8))
        XCTAssertEqual(day.targets.proteinMinG, 140)
        XCTAssertEqual(day.targets.proteinMinDefault, false)
        XCTAssertNil(day.consumed.proteinMinG)
        XCTAssertEqual(NutritionTone.tone(for: .protein, consumed: day.consumed, targets: day.targets), .bad)
        XCTAssertEqual(FoodHalfCard.proteinText(day), "Eiweiß 96/195 g")
    }

    /// Ein aelterer Dienst: dieselbe Antwort ohne die neuen Felder laedt weiter.
    func testDecodesTargetsWithoutAFloor() throws {
        let json = """
        {"date":"2026-11-10",
         "targets":{"kcal":2300.0,"proteinG":175.0,"carbsG":236.0,"fatG":70.0},
         "consumed":{"kcal":0.0,"proteinG":0.0,"carbsG":0.0,"fatG":0.0},
         "remaining":{"kcal":2300.0,"proteinG":175.0,"carbsG":236.0,"fatG":70.0},
         "entries":[],"mealTargets":{}}
        """
        let day = try APIClient.decoder().decode(DaySummary.self, from: Data(json.utf8))
        XCTAssertNil(day.targets.proteinMinG)
        XCTAssertNil(day.targets.proteinMinDefault)
    }

    /// Der Erhalt haengt nur an Zielen: gerechnete Werte tragen ihn nicht weiter.
    func testArithmeticDropsTheFloor() {
        XCTAssertNil((targets - protein(50)).proteinMinG)
        XCTAssertNil(targets.scaled(gramsOf: 50).proteinMinG)
    }

    /// Fehlend heisst unveraendert - das Feld darf dann gar nicht im JSON stehen.
    func testTheRequestOmitsAnUnchangedFloor() throws {
        let unchanged = TargetsRequest(kcal: 2300, proteinG: 195, carbsG: 236, fatG: 70, mealShares: nil)
        let text = String(data: try JSONEncoder().encode(unchanged), encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("proteinMinG"))

        let changed = TargetsRequest(kcal: nil, proteinG: nil, carbsG: nil, fatG: nil, mealShares: nil,
                                     proteinMinG: 140)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(changed)) as? [String: Any]
        XCTAssertEqual(object?["proteinMinG"] as? Double, 140)
    }

    // MARK: - Ziele-Blatt

    /// Was das Blatt fuer den Erhalt schickt: nur eine Aenderung.
    func testTheSheetSendsOnlyAChange() {
        // Nicht angefasst - eine Vorgabe des Dienstes bleibt eine Vorgabe.
        XCTAssertNil(TargetsSheet.proteinMinChange(entered: "141,8", loaded: "141,8", isServerDefault: true))
        XCTAssertNil(TargetsSheet.proteinMinChange(entered: "140,0", loaded: "140,0", isServerDefault: false))
        // Geaendert.
        XCTAssertEqual(TargetsSheet.proteinMinChange(entered: "150", loaded: "141,8", isServerDefault: true), 150)
        XCTAssertEqual(TargetsSheet.proteinMinChange(entered: "132,5", loaded: "140,0", isServerDefault: false), 132.5)
        // Geleert: zurueck auf die Vorgabe (0) - ausser es war schon die Vorgabe.
        XCTAssertEqual(TargetsSheet.proteinMinChange(entered: "", loaded: "140,0", isServerDefault: false), 0)
        XCTAssertNil(TargetsSheet.proteinMinChange(entered: " ", loaded: "141,8", isServerDefault: true))
        XCTAssertEqual(TargetsSheet.proteinMinChange(entered: "0", loaded: "140,0", isServerDefault: false), 0)
        // Ein aelterer Dienst ohne Erhalt: leer bleibt leer.
        XCTAssertNil(TargetsSheet.proteinMinChange(entered: "", loaded: "", isServerDefault: true))
    }
}
