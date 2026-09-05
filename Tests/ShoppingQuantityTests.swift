import Testing
@testable import Healthy

/// Mengen: was Menschen tippen, in Zahl und Einheit - und zurueck.
struct ShoppingQuantityTests {

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

    @Test func composeUsesTheChosenUnitOnlyForBareNumbers() {
        #expect(ShoppingQuantity.compose("500", unit: .gram) == "500 g")
        #expect(ShoppingQuantity.compose("500g", unit: .piece) == "500 g")
        #expect(ShoppingQuantity.compose("3 Dosen", unit: .gram) == "3 Dosen")
        #expect(ShoppingQuantity.compose("  ", unit: .gram) == nil)
        #expect(ShoppingQuantity.compose("3", unit: .piece) == "3 Stk")
    }
}
