import Testing
@testable import Healthy

/// Mengen: Zahl und Einheit auseinanderlesen und wieder zusammensetzen.
struct ShoppingQuantityTests {

    @Test func readsNumberAndUnit() {
        #expect(ShoppingQuantity.parse("500 g") == ShoppingQuantity(amount: "500", unit: .gram))
        #expect(ShoppingQuantity.parse("500g") == ShoppingQuantity(amount: "500", unit: .gram))
        #expect(ShoppingQuantity.parse("1,5 kg") == ShoppingQuantity(amount: "1,5", unit: .kilogram))
        #expect(ShoppingQuantity.parse("2 Stück") == ShoppingQuantity(amount: "2", unit: .piece))
        #expect(ShoppingQuantity.parse("1 l") == ShoppingQuantity(amount: "1", unit: .liter))
        #expect(ShoppingQuantity.parse("1 Pck.") == ShoppingQuantity(amount: "1", unit: .pack))
    }

    @Test func aBareNumberMeansPieces() {
        #expect(ShoppingQuantity.parse("2") == ShoppingQuantity(amount: "2", unit: .piece))
        #expect(ShoppingQuantity.parse("2")?.text == "2 Stk")
    }

    @Test func freeTextStaysFreeText() {
        #expect(ShoppingQuantity.parse("eine Handvoll") == nil)
        #expect(ShoppingQuantity.parse("2 Bund") == nil)
        #expect(ShoppingQuantity.compose("eine Handvoll", unit: .gram) == "eine Handvoll")
    }

    @Test func composeUsesTheChosenUnitOnlyForBareNumbers() {
        #expect(ShoppingQuantity.compose("500", unit: .gram) == "500 g")
        #expect(ShoppingQuantity.compose("500g", unit: .piece) == "500 g")
        #expect(ShoppingQuantity.compose("  ", unit: .gram) == nil)
        #expect(ShoppingQuantity.compose("3", unit: .piece) == "3 Stk")
    }
}
