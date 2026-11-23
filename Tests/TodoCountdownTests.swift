import Foundation
import Testing
@testable import Healthy

/// Der Countdown der Fokus-Kachel (17.11.): Tage bis zur Faelligkeit einer
/// gewaehlten Aufgabe, gezaehlt in Kalendertagen.
struct TodoCountdownTests {

    private let today = CalendarDate(year: 2026, month: 11, day: 17)

    private func countdown(_ id: String = "a", title: String = "Klausur", due: CalendarDate?,
                           done: Bool = false) -> TodoCountdown {
        TodoCountdown(id: id, title: title, area: "Uni", dueAt: due, isDone: done)
    }

    private func item(_ id: String, _ title: String, due: String? = nil, done: Bool = false,
                      children: [TodoItem] = []) -> TodoItem {
        TodoItem(id: id, title: title, link: nil, createdAt: Date(timeIntervalSince1970: 1_790_000_000),
                 doneAt: done ? Date(timeIntervalSince1970: 1_790_100_000) : nil, visibleUntil: nil,
                 dueAt: due.flatMap(CalendarDate.init(iso:)), reminders: [], children: children)
    }

    private func area(_ name: String, _ todos: [TodoItem]) -> TodoArea {
        TodoArea(id: name.lowercased(), name: name, position: 0, openCount: todos.count, hiddenDoneCount: 0,
                 todos: todos)
    }

    @Test func countsCalendarDaysAcrossMonthsAndYears() {
        #expect(today.days(until: CalendarDate(year: 2027, month: 1, day: 16)) == 60)
        #expect(today.days(until: today) == 0)
        #expect(today.days(until: CalendarDate(year: 2026, month: 11, day: 14)) == -3)
        // Ueber die Zeitumstellung am 25.10. hinweg bleibt ein Tag ein Tag.
        #expect(CalendarDate(year: 2026, month: 10, day: 24).days(until: CalendarDate(year: 2026, month: 10, day: 26)) == 2)
    }

    @Test func phaseAroundTheDueDate() {
        #expect(countdown(due: today.adding(days: 60)).phase(on: today) == .ahead(60))
        #expect(countdown(due: today.adding(days: 1)).phase(on: today) == .ahead(1))
        #expect(countdown(due: today).phase(on: today) == .today)
        #expect(countdown(due: today.adding(days: -3)).phase(on: today) == .overdue(3))
        // Erledigt zaehlt nicht mehr, auch nicht vor der Faelligkeit.
        #expect(countdown(due: today.adding(days: 5), done: true).phase(on: today) == .done)
        #expect(countdown(due: nil).phase(on: today) == .undated)
        // Am naechsten Tag (der Eintrag um Mitternacht) einer weniger.
        #expect(countdown(due: today.adding(days: 60)).phase(on: today.adding(days: 1)) == .ahead(59))
    }

    @Test func textsOfTheSmallWidget() {
        #expect(TodoCountdown.Phase.ahead(60).figure == "60")
        #expect(TodoCountdown.Phase.ahead(60).caption == "Tage")
        #expect(TodoCountdown.Phase.ahead(1).caption == "Tag")
        #expect(TodoCountdown.Phase.today.figure == "Heute")
        #expect(TodoCountdown.Phase.today.caption == nil)
        #expect(TodoCountdown.Phase.overdue(3).caption == "Tage überfällig")
        #expect(TodoCountdown.Phase.overdue(1).caption == "Tag überfällig")
        #expect(TodoCountdown.Phase.done.figure == nil)
        #expect(TodoCountdown.Phase.done.caption == "erledigt")
        #expect(TodoCountdown.Phase.undated.caption == "ohne Fälligkeit")
    }

    @Test func textsOfTheLockScreen() {
        #expect(TodoCountdown.Phase.ahead(60).line == "60 Tage")
        #expect(TodoCountdown.Phase.overdue(1).line == "1 Tag überfällig")
        #expect(TodoCountdown.Phase.ahead(60).compact.figure == "60")
        #expect(TodoCountdown.Phase.overdue(3).compact.figure == "−3")
        #expect(TodoCountdown.Phase.ahead(60).sentence("Klausur") == "Klausur in 60 Tagen")
        #expect(TodoCountdown.Phase.ahead(1).sentence("Klausur") == "Klausur morgen")
        #expect(TodoCountdown.Phase.today.sentence("Klausur") == "Klausur heute")
        #expect(TodoCountdown.Phase.overdue(1).sentence("Klausur") == "Klausur seit gestern fällig")
        #expect(TodoCountdown.Phase.overdue(4).sentence("Klausur") == "Klausur seit 4 Tagen fällig")
    }

    @Test func dateCarriesTheYearOnlyOutsideThisYear() {
        #expect(countdown(due: CalendarDate(year: 2026, month: 12, day: 4)).dateText(today: today) == "Fr 04.12.")
        #expect(countdown(due: CalendarDate(year: 2027, month: 1, day: 16)).dateText(today: today) == "Sa 16.01.27")
        #expect(countdown(due: nil).dateText(today: today) == nil)
    }

    @Test func collectsEveryTodoOnceWithSubtasksAndTodayOnly() {
        let thesis = item("t1", "Hausarbeit", due: "2026-12-01",
                          children: [item("c1", "Gliederung", due: "2026-11-20")])
        let board = TodoBoard(
            areas: [area("Uni", [thesis, item("t2", "Klausur", due: "2027-01-16")])],
            includesHidden: false, hiddenDoneCount: 0, now: Date(),
            today: TodoToday(openCount: 2, items: [
                // Aus einem Bereich geholt - steht schon oben, mit Bereich.
                TodoTodayItem(areaId: "uni", areaName: "Uni", parentId: nil, parentTitle: nil, todo: thesis),
                TodoTodayItem(areaId: nil, areaName: nil, parentId: nil, parentTitle: nil,
                              todo: item("h1", "Zahnarzt", due: "2026-11-18")),
            ]))

        let todos = TodoCountdown.all(in: board)

        #expect(todos.map(\.id) == ["t1", "c1", "t2", "h1"])
        #expect(todos[1].title == "Hausarbeit › Gliederung")
        #expect(todos[1].area == "Uni")
        #expect(todos[3].area == nil)
    }

    @Test func choicesAreOpenTodosWithADueDateSoonestFirst() {
        let todos = [countdown("late", due: CalendarDate(year: 2027, month: 1, day: 16)),
                     countdown("none", due: nil),
                     countdown("done", due: today.adding(days: 2), done: true),
                     countdown("b", title: "B", due: today.adding(days: 3)),
                     countdown("a", title: "A", due: today.adding(days: 3)),
                     countdown("past", due: today.adding(days: -2))]

        #expect(TodoCountdown.choices(in: todos).map(\.id) == ["past", "a", "b", "late"])
    }

    @Test func pickKeepsTheChosenTodoAndOtherwiseTakesTheNextDue() {
        let todos = [countdown("past", due: today.adding(days: -2)),
                     countdown("done", due: today.adding(days: 1), done: true),
                     countdown("next", due: today.adding(days: 4)),
                     countdown("later", due: today.adding(days: 40))]

        #expect(TodoCountdown.pick("later", in: todos, today: today)?.id == "later")
        // Erledigt bleibt gewaehlt - die Kachel zeigt dann den Haken.
        #expect(TodoCountdown.pick("done", in: todos, today: today)?.id == "done")
        // Ohne Wahl oder geloescht: die naechste ab heute, nicht die ueberfaellige.
        #expect(TodoCountdown.pick(nil, in: todos, today: today)?.id == "next")
        #expect(TodoCountdown.pick("deleted", in: todos, today: today)?.id == "next")
        #expect(TodoCountdown.pick(nil, in: [todos[0]], today: today) == nil)
    }

    @Test func midnightsFollowTheClockAcrossDaylightSaving() throws {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let noon = try #require(berlin.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12)))

        let midnights = TodoCountdown.midnights(after: noon, count: 3, calendar: berlin)

        let iso = ISO8601DateFormatter()
        #expect(midnights.map(iso.string(from:)) == ["2026-10-24T22:00:00Z",   // noch Sommerzeit
                                                     "2026-10-25T23:00:00Z",   // ab hier Winterzeit
                                                     "2026-10-26T23:00:00Z"])
    }
}
