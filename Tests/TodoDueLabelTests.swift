import Testing
@testable import Healthy

/// Die Faelligkeit in der Zeile: eine Woche um heute in Tagen, sonst Datum.
struct TodoDueLabelTests {

    private let date = CalendarDate(year: 2026, month: 9, day: 12)

    @Test func aWeekAheadCountsInDays() {
        #expect(TodoItem.dueLabel(for: date, daysFromToday: 0) == "heute")
        #expect(TodoItem.dueLabel(for: date, daysFromToday: 1) == "morgen")
        #expect(TodoItem.dueLabel(for: date, daysFromToday: 2) == "in 2 Tagen")
        #expect(TodoItem.dueLabel(for: date, daysFromToday: 7) == "in 7 Tagen")
    }

    @Test func fartherAwayShowsTheDate() {
        #expect(TodoItem.dueLabel(for: date, daysFromToday: 8) == "bis 12.09.26")
        #expect(TodoItem.dueLabel(for: date, daysFromToday: -8) == "seit 12.09.26")
    }

    @Test func overdueCountsBackwards() {
        #expect(TodoItem.dueLabel(for: date, daysFromToday: -1) == "seit gestern")
        #expect(TodoItem.dueLabel(for: date, daysFromToday: -3) == "seit 3 Tagen")
        #expect(TodoItem.dueLabel(for: date, daysFromToday: -7) == "seit 7 Tagen")
    }
}
