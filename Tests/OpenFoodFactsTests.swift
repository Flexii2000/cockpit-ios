import Foundation
import Testing
@testable import Healthy

/// Die Auszuege stammen aus echten Antworten von
/// `/api/v2/product/<code>.json?fields=…` (2026-09-21), gekuerzt auf die
/// Felder, die die App liest.
struct OpenFoodFactsTests {

    private static let ritterSport = """
    {"code":"4000417025005","status":1,"status_verbose":"product found",
     "product":{"product_name":"Marzipan","brands":"Ritter Sport","quantity":"100g",
      "serving_size":"1 Cube (6.52 g)",
      "nutriments":{"energy":2069,"energy-kcal":496,"energy-kcal_100g":496,"energy-kcal_unit":"kcal",
       "energy_100g":2069,"energy_unit":"kJ","fat_100g":27,"carbohydrates_100g":52,
       "proteins_100g":7,"salt_100g":0.13}}}
    """

    private static let notFound = """
    {"code":"4000417999999","status":0,"status_verbose":"product not found"}
    """

    private func parse(_ json: String) throws -> ScannedProduct? {
        try OpenFoodFactsParser.parse(Data(json.utf8))
    }

    @Test func readsNameBrandAndValuesPer100g() throws {
        let product = try #require(try parse(Self.ritterSport))
        #expect(product.name == "Marzipan")
        #expect(product.brand == "Ritter Sport")
        #expect(product.displayName == "Marzipan (Ritter Sport)")
        #expect(product.kcal == 496)
        #expect(product.proteinG == 7)
        #expect(product.carbsG == 52)
        #expect(product.fatG == 27)
    }

    /// Die Portion steht in `serving_size` - auch mitten im Text.
    @Test func servingSizeBecomesTheDefaultGrams() throws {
        let product = try #require(try parse(Self.ritterSport))
        #expect(product.servingG == 6.52)
    }

    /// Ohne kcal rechnet die App aus den Kilojoule, die immer da sind.
    @Test func fallsBackToKilojoules() throws {
        let json = """
        {"status":1,"product":{"product_name":"Haferdrink","brands":"",
         "nutriments":{"energy_100g":2092,"energy_unit":"kJ","proteins_100g":"1.1"}}}
        """
        let product = try #require(try parse(json))
        #expect(product.kcal != nil)
        #expect(abs((product.kcal ?? 0) - 500) < 0.01)
        // Zahlen als Text kommen vor - je nachdem, wer den Eintrag angelegt hat.
        #expect(product.proteinG == 1.1)
        #expect(product.carbsG == nil)
        #expect(product.brand == nil)
        #expect(product.displayName == "Haferdrink")
    }

    /// Ohne `serving_size` zaehlt die Packungsgroesse - wenn sie in g oder ml
    /// dasteht.
    @Test func quantityIsTheFallbackForGrams() throws {
        let cups = """
        {"status":1,"product":{"product_name":"Joghurt","brands":"Alnatura, Bio",
         "quantity":"6 x 125 g","nutriments":{}}}
        """
        let product = try #require(try parse(cups))
        #expect(product.servingG == 125)
        #expect(product.brand == "Alnatura")

        let bottle = """
        {"status":1,"product":{"product_name":"Wasser","quantity":"1 l","nutriments":{}}}
        """
        #expect(try #require(try parse(bottle)).servingG == nil)
    }

    @Test func notFoundIsNil() throws {
        #expect(try parse(Self.notFound) == nil)
        #expect(try parse("{\"status\":1}") == nil)
    }

    @Test func garbageIsAnError() {
        #expect(throws: OpenFoodFactsError.self) {
            try OpenFoodFactsParser.parse(Data("<html>".utf8))
        }
    }

    @Test func gramsInText() {
        #expect(OpenFoodFactsParser.grams(in: "30 g") == 30)
        #expect(OpenFoodFactsParser.grams(in: "250ml") == 250)
        #expect(OpenFoodFactsParser.grams(in: "1 Riegel (25 g)") == 25)
        #expect(OpenFoodFactsParser.grams(in: "2 Scheiben (50g)") == 50)
        #expect(OpenFoodFactsParser.grams(in: "12,5 g") == 12.5)
        #expect(OpenFoodFactsParser.grams(in: "1,5 kg") == nil)
        #expect(OpenFoodFactsParser.grams(in: "500 gr") == nil)
        #expect(OpenFoodFactsParser.grams(in: "2 Stück") == nil)
        #expect(OpenFoodFactsParser.grams(in: "") == nil)
    }

    @Test func requestUrlCarriesOnlyTheFields() {
        #expect(OpenFoodFactsAPI.url(for: "4000417025005").absoluteString
                == "https://world.openfoodfacts.org/api/v2/product/4000417025005.json"
                + "?fields=product_name,brands,quantity,serving_size,nutriments")
        #expect(OpenFoodFactsAPI.userAgent == "Cockpit-iOS/0.2 (private, non-commercial)")
    }
}

/// Womit das Eintrag-Blatt nach einem Scan aufgeht.
struct EntryPrefillTests {

    private let product = ScannedProduct(name: "Marzipan", brand: "Ritter Sport",
                                         kcal: 496, proteinG: 7, carbsG: 52, fatG: 27,
                                         servingG: 6.52)

    @Test func unknownProductFillsANewDish() {
        let prefill = EntryPrefill(product: product, dishes: [])
        #expect(prefill.creatingNew)
        #expect(prefill.name == "Marzipan (Ritter Sport)")
        #expect(AddEntrySheet.number(prefill.kcal) == 496)
        #expect(AddEntrySheet.number(prefill.protein) == 7)
        #expect(AddEntrySheet.number(prefill.carbs) == 52)
        #expect(AddEntrySheet.number(prefill.fat) == 27)
        #expect(AddEntrySheet.number(prefill.grams) == 6.5)
        #expect(AddEntrySheet.number(prefill.portion) == 6.5)
        #expect(prefill.selected == nil)
    }

    /// Derselbe Name in der Merkliste: das vorhandene Gericht, kein zweites.
    @Test func knownNameSelectsTheExistingDish() {
        let known = Dish(id: "d1", name: "Marzipan (Ritter Sport)",
                         per100g: Nutrients(kcal: 490, proteinG: 7, carbsG: 52, fatG: 27),
                         portionG: 17, lastUsedOn: nil)
        let prefill = EntryPrefill(product: product, dishes: [known])
        #expect(!prefill.creatingNew)
        #expect(prefill.selected?.id == "d1")
        #expect(prefill.search == "Marzipan (Ritter Sport)")
        #expect(AddEntrySheet.number(prefill.grams) == 6.5)
    }

    @Test func missingValuesStayEmpty() {
        let sparse = ScannedProduct(name: "Wasser", brand: nil, kcal: nil, proteinG: nil,
                                    carbsG: nil, fatG: nil, servingG: nil)
        let prefill = EntryPrefill(product: sparse, dishes: [])
        #expect(prefill.kcal == "")
        #expect(prefill.grams == "")
        #expect(prefill.name == "Wasser")
    }

    /// Kein Tausenderpunkt: „1.000" laese `number()` als 1.
    @Test func textKeepsLargeNumbersReadable() {
        #expect(AddEntrySheet.number(EntryPrefill.text(1000)) == 1000)
        #expect(EntryPrefill.text(nil) == "")
    }
}
