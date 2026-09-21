import CoreGraphics
import Testing
@testable import Healthy

/// Wischen zwischen Tagen: was zaehlt als Wisch, und wohin.
struct DaySwipeTests {

    @Test func leftIsTheNextDayRightThePrevious() {
        #expect(DaySwipe.step(for: CGSize(width: -120, height: 5)) == 1)
        #expect(DaySwipe.step(for: CGSize(width: 90, height: -10)) == -1)
    }

    /// Ein Wackler blaettert nicht.
    @Test func shortDragsAreIgnored() {
        #expect(DaySwipe.step(for: CGSize(width: -60, height: 0)) == nil)
        #expect(DaySwipe.step(for: CGSize(width: 40, height: 0)) == nil)
    }

    /// Scrollen der Liste hat eine senkrechte Komponente - die darf nicht
    /// nebenbei den Tag wechseln.
    @Test func mostlyVerticalDragsAreScrolling() {
        #expect(DaySwipe.step(for: CGSize(width: -80, height: 70)) == nil)
        #expect(DaySwipe.step(for: CGSize(width: 100, height: -200)) == nil)
        #expect(DaySwipe.step(for: CGSize(width: -100, height: 60)) == 1)
    }
}

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
