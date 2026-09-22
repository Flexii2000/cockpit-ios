import Testing
@testable import Healthy

/// Die Mahlzeit, die das Blatt vorschlaegt, wenn kein Abschnitt sie vorgibt.
struct MealSuggestionTests {

    @Test func followsTheTimeOfDay() {
        #expect(Meal.suggested(hour: 7) == .breakfast)
        #expect(Meal.suggested(hour: 12) == .lunch)
        #expect(Meal.suggested(hour: 19) == .dinner)
        #expect(Meal.suggested(hour: 16) == .snack)
        #expect(Meal.suggested(hour: 23) == .snack)
        #expect(Meal.suggested(hour: 3) == .snack)
    }
}
