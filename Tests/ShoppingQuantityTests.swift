import Foundation
import Testing
@testable import Healthy

/// Nur damit sich das Test-Bundle finden laesst - darin liegt `scale-vectors.json`.
private final class FixtureBundle {}

/// Mengen: was Menschen tippen, in Zahl und Einheit - und zurueck.
struct ShoppingQuantityTests {

    // MARK: - Umrechnen auf eine andere Portionenzahl

    /// Die Beispiele, gegen die auch der Dienst rechnet (`QuantityParser.scale`):
    /// eine Kopie von `../shopping/src/test/resources/scale-vectors.json`. Wer die
    /// Rundung aendert, aendert die Datei dort und kopiert sie hierher.
    private struct Vectors: Decodable {
        let vectors: [Vector]

        struct Vector: Decodable {
            let quantity: String?
            let portions: Int
            let base: Int
            let expected: String?
            let scaled: Bool
        }
    }

    @Test func scalesLikeTheService() throws {
        let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: "scale-vectors", withExtension: "json"),
                               "scale-vectors.json fehlt im Test-Bundle")
        let vectors = try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: url)).vectors
        #expect(vectors.count >= 38, "die Datei ist kuerzer als die des Dienstes")
        for vector in vectors {
            let result = ShoppingQuantity.scale(vector.quantity, portions: vector.portions, base: vector.base)
            let label = "\(vector.quantity ?? "nil") × \(vector.portions)/\(vector.base)"
            #expect(result.quantity == vector.expected, "\(label)")
            #expect(result.scaled == vector.scaled, "\(label)")
        }
    }

    @Test func scalingRoundsHalvesUp() {
        // 312,5 ml wird 313 - kaufmaennisch, nicht zur geraden Zahl.
        #expect(ShoppingQuantity.scale("250 ml", portions: 5, base: 4).quantity == "313 ml")
        // 2,25 Stk auf halbe: 2,5, nicht 2.
        #expect(ShoppingQuantity.scale("3 Stk", portions: 3, base: 4).quantity == "2,5 Stk")
    }

    @Test func scalingNeverRoundsToNothing() {
        #expect(ShoppingQuantity.scale("1 g", portions: 1, base: 99).quantity == "0,1 g")
        #expect(ShoppingQuantity.scale("1 Stk", portions: 1, base: 8).quantity == "0,5 Stk")
        #expect(ShoppingQuantity.scale("1 l", portions: 1, base: 500).quantity == "0,01 l")
    }

    @Test func whatCannotBeReadStaysAsItIs() {
        let handful = ShoppingQuantity.scale("eine Handvoll", portions: 4, base: 2)
        #expect(handful == ShoppingQuantity.Scaled(quantity: "eine Handvoll", scaled: false))
        // Ein unlesbarer Teil haelt die ganze Menge fest - lieber unveraendert als halb gerechnet.
        #expect(ShoppingQuantity.scale("500 g + etwas", portions: 4, base: 2).quantity == "500 g + etwas")
        #expect(ShoppingQuantity.scale(nil, portions: 4, base: 2) == ShoppingQuantity.Scaled(quantity: nil, scaled: true))
        #expect(ShoppingQuantity.scale("  ", portions: 4, base: 2).quantity == nil)
    }

    @Test func aRecipeScalesItsIngredients() {
        let dish = ShoppingDish(id: "d", name: "Rezept A", ingredients: [
            ShoppingIngredient(name: "Nudeln", quantity: "250 g"),
            ShoppingIngredient(name: "Öl", quantity: "3 EL", pantry: true),
            ShoppingIngredient(name: "Basilikum", quantity: "1 Handvoll"),
            ShoppingIngredient(name: "Salz", quantity: nil, pantry: true),
        ], createdAt: Date(timeIntervalSince1970: 1_790_000_000), portions: 2)
        let three = dish.ingredients(for: 3)
        #expect(three.map(\.quantity) == ["375 g", "4,5 EL", "1 Handvoll", nil])
        #expect(three.map(\.scaled) == [true, true, false, true])
        #expect(three.map(\.pantry) == [false, true, false, true])
        // Ohne Angabe: die gespeicherten Mengen.
        #expect(dish.ingredients(for: nil).map(\.quantity) == ["250 g", "3 EL", "1 Handvoll", nil])
    }

    @Test func aDishWithoutPortionsDoesNotScale() {
        let dish = ShoppingDish(id: "d", name: "Gericht A", ingredients: [ShoppingIngredient(name: "Nudeln", quantity: "250 g")],
                                createdAt: Date(timeIntervalSince1970: 1_790_000_000))
        #expect(dish.basePortions == nil)
        #expect(dish.isPlain)
        #expect(dish.ingredients(for: 6).map(\.quantity) == ["250 g"])
    }

    // MARK: - Lesen und Schreiben

    @Test func readsNumberAndUnit() {
        #expect(ShoppingQuantity.parse("500 g") == ShoppingQuantity(amount: "500", unit: .gram))
        #expect(ShoppingQuantity.parse("500g") == ShoppingQuantity(amount: "500", unit: .gram))
        #expect(ShoppingQuantity.parse("200 Gramm") == ShoppingQuantity(amount: "200", unit: .gram))
        #expect(ShoppingQuantity.parse("1,5 kg") == ShoppingQuantity(amount: "1,5", unit: .kilogram))
        #expect(ShoppingQuantity.parse("2 Stück") == ShoppingQuantity(amount: "2", unit: .piece))
        #expect(ShoppingQuantity.parse("2 stk") == ShoppingQuantity(amount: "2", unit: .piece))
        #expect(ShoppingQuantity.parse("1 l") == ShoppingQuantity(amount: "1", unit: .liter))
        #expect(ShoppingQuantity.parse("1 Pck.") == ShoppingQuantity(amount: "1", unit: .pack))
        #expect(ShoppingQuantity.parse("3 Dosen") == ShoppingQuantity(amount: "3", unit: .can))
    }

    @Test func readsNumberWords() {
        #expect(ShoppingQuantity.parse("zwei") == ShoppingQuantity(amount: "2", unit: .piece))
        #expect(ShoppingQuantity.parse("zwei Stück") == ShoppingQuantity(amount: "2", unit: .piece))
        #expect(ShoppingQuantity.parse("eine Packung") == ShoppingQuantity(amount: "1", unit: .pack))
        #expect(ShoppingQuantity.parse("ein halbes Kilo") == ShoppingQuantity(amount: "0,5", unit: .kilogram))
        #expect(ShoppingQuantity.parse("anderthalb Liter") == ShoppingQuantity(amount: "1,5", unit: .liter))
        #expect(ShoppingQuantity.parse("ein Dutzend") == nil)
        #expect(ShoppingQuantity.parse("Dutzend") == ShoppingQuantity(amount: "12", unit: .piece))
    }

    @Test func aBareNumberMeansPieces() {
        #expect(ShoppingQuantity.parse("2") == ShoppingQuantity(amount: "2", unit: .piece))
        #expect(ShoppingQuantity.parse("2")?.text == "2 Stk")
    }

    @Test func writesTheRightForm() {
        #expect(ShoppingQuantity(amount: "1", unit: .can).text == "1 Dose")
        #expect(ShoppingQuantity(amount: "3", unit: .can).text == "3 Dosen")
        #expect(ShoppingQuantity(amount: "2", unit: .caseOf).text == "2 Kästen")
        #expect(ShoppingQuantity(amount: "0,5", unit: .kilogram).text == "0,5 kg")
    }

    @Test func freeTextStaysFreeText() {
        #expect(ShoppingQuantity.parse("eine Handvoll") == nil)
        #expect(ShoppingQuantity.compose("eine Handvoll", unit: .gram) == "eine Handvoll")
    }

    @Test func splitsAQuantityOffTheName() {
        #expect(ShoppingQuantity.split("gemischtes Hack 200g").name == "gemischtes Hack")
        #expect(ShoppingQuantity.split("gemischtes Hack 200g").quantity == ShoppingQuantity(amount: "200", unit: .gram))
        #expect(ShoppingQuantity.split("Hack 200 Gramm").quantity?.text == "200 g")
        #expect(ShoppingQuantity.split("2 Zwiebeln").name == "Zwiebeln")
        #expect(ShoppingQuantity.split("zwei Zwiebeln").quantity?.text == "2 Stk")
        #expect(ShoppingQuantity.split("Klopapier 2").quantity?.text == "2 Stk")
        #expect(ShoppingQuantity.split("Klopapier 2 stk").quantity?.text == "2 Stk")
        #expect(ShoppingQuantity.split("Klopapier zwei").name == "Klopapier")
        #expect(ShoppingQuantity.split("Milch 1l").quantity?.text == "1 l")
        #expect(ShoppingQuantity.split("2 Stück Butter").name == "Butter")
        #expect(ShoppingQuantity.split("ein Liter Milch").quantity?.text == "1 l")
        #expect(ShoppingQuantity.split("eine Packung Nudeln").quantity?.text == "1 Pck")
        #expect(ShoppingQuantity.split("ein halbes Kilo Hack").name == "Hack")
        #expect(ShoppingQuantity.split("ein halbes Kilo Hack").quantity?.text == "0,5 kg")
        #expect(ShoppingQuantity.split("Tomaten 3 Dosen").quantity?.text == "3 Dosen")
        #expect(ShoppingQuantity.split("Bier 1 Kasten").quantity?.text == "1 Kasten")
        #expect(ShoppingQuantity.split("2x Toast").name == "Toast")
        #expect(ShoppingQuantity.split("Cola 1,5 l").quantity?.text == "1,5 l")
        #expect(ShoppingQuantity.split("2 gemischte Brote").name == "gemischte Brote")
    }

    @Test func aUnitWordAloneMeansOne() {
        #expect(ShoppingQuantity.split("Liter Cola").name == "Cola")
        #expect(ShoppingQuantity.split("Liter Cola").quantity?.text == "1 l")
        #expect(ShoppingQuantity.split("Packung Nudeln").quantity?.text == "1 Pck")
        #expect(ShoppingQuantity.split("Dose Tomaten").quantity?.text == "1 Dose")
        #expect(ShoppingQuantity.split("Cola Liter").quantity?.text == "1 l")
        #expect(ShoppingQuantity.split("Kasten Bier").quantity?.text == "1 Kasten")
        #expect(ShoppingQuantity.parse("Liter") == ShoppingQuantity(amount: "1", unit: .liter))
        // Abkuerzungen ohne Zahl sind keine Menge, und ein Wort allein bleibt ein Name.
        #expect(ShoppingQuantity.split("g Zucker").quantity == nil)
        #expect(ShoppingQuantity.split("Glas").quantity == nil)
    }

    @Test func leavesNamesWithoutAQuantityAlone() {
        #expect(ShoppingQuantity.split("Mehl Type 405").quantity == nil)
        #expect(ShoppingQuantity.split("Mehl Type 405").name == "Mehl Type 405")
        #expect(ShoppingQuantity.split("H-Milch 3,5%").quantity == nil)
        #expect(ShoppingQuantity.split("Milch 1,5").quantity == nil)
        #expect(ShoppingQuantity.split("Eier 10er").quantity == nil)
        #expect(ShoppingQuantity.split("ein paar Äpfel").quantity == nil)
        #expect(ShoppingQuantity.split("Bananen").quantity == nil)
    }

    @Test func mergesQuantitiesOfTheSameUnit() {
        #expect(ShoppingQuantity.merge("500 g", "500 g") == "1000 g")
        #expect(ShoppingQuantity.merge("2 Stk", "3 Stk") == "5 Stk")
        #expect(ShoppingQuantity.merge("1,5 kg", "1 kg") == "2,5 kg")
        #expect(ShoppingQuantity.merge("1 Dose", "2 Dosen") == "3 Dosen")
        #expect(ShoppingQuantity.merge(nil, "2 Stk") == "2 Stk")
        #expect(ShoppingQuantity.merge("500 g", "  ") == "500 g")
        #expect(ShoppingQuantity.merge("500 g", "1 Pck") == "500 g + 1 Pck")
        #expect(ShoppingQuantity.merge("eine Handvoll", "eine Handvoll") == "eine Handvoll")
        #expect(ShoppingQuantity.merge(nil, nil) == nil)
    }

    @Test func composeUsesTheChosenUnitOnlyForBareNumbers() {
        #expect(ShoppingQuantity.compose("500", unit: .gram) == "500 g")
        #expect(ShoppingQuantity.compose("500g", unit: .piece) == "500 g")
        #expect(ShoppingQuantity.compose("3 Dosen", unit: .gram) == "3 Dosen")
        #expect(ShoppingQuantity.compose("  ", unit: .gram) == nil)
        #expect(ShoppingQuantity.compose("3", unit: .piece) == "3 Stk")
    }
}
