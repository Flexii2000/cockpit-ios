import XCTest
@testable import Healthy

/// Die Zuordnung von Statistik-Kuebeln zu Kalendertagen. Die Abfrage selbst
/// laesst sich nicht pruefen - ohne echtes Health gibt es nichts zu lesen.
final class HealthStepsTests: XCTestCase {

    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    private func tagesbeginn(_ tag: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: tag))!
    }

    func testMapsBucketsToCalendarDays() {
        let werte = HealthSteps.dailyValues([
            StepBucket(dayStart: tagesbeginn(1), count: 8123),
            StepBucket(dayStart: tagesbeginn(2), count: 4200),
        ], in: berlin)

        XCTAssertEqual(werte.map(\.steps), [8123, 4200])
        XCTAssertEqual(werte.first?.date, CalendarDate(year: 2026, month: 9, day: 1))
    }

    /// Health unterscheidet „nichts gemessen" nicht von „null Schritte". Eine
    /// Null im Bestand waere eine Behauptung ueber einen Tag, ueber den
    /// niemand etwas weiss - deshalb faellt sie raus.
    func testDropsDaysWithoutSteps() {
        let werte = HealthSteps.dailyValues([
            StepBucket(dayStart: tagesbeginn(1), count: 0),
            StepBucket(dayStart: tagesbeginn(2), count: 5),
        ], in: berlin)

        XCTAssertEqual(werte.count, 1)
        XCTAssertEqual(werte.first?.date, CalendarDate(year: 2026, month: 9, day: 2))
    }

    func testRoundsToWholeSteps() {
        let werte = HealthSteps.dailyValues(
            [StepBucket(dayStart: tagesbeginn(1), count: 8123.6)], in: berlin)
        XCTAssertEqual(werte.first?.steps, 8124)
    }

    /// Die Tagesgrenze richtet sich nach der Zeitzone des Geraets - wie beim
    /// Gewicht auch.
    func testDayBoundaryFollowsTheTimeZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        let kurzNachMitternacht = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 2, hour: 0, minute: 30))!
        let werte = HealthSteps.dailyValues(
            [StepBucket(dayStart: kurzNachMitternacht, count: 100)], in: berlin)
        XCTAssertEqual(werte.first?.date, CalendarDate(year: 2026, month: 9, day: 2))
    }

    func testEmptyInputGivesEmptyOutput() {
        XCTAssertTrue(HealthSteps.dailyValues([], in: berlin).isEmpty)
    }
}
