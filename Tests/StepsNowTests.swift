import XCTest
@testable import Healthy

/// Die Schritte der Sperrbildschirm-Kacheln (14.10.): das Groessere aus dem
/// letzten Health-Stand der App und dem Schrittzaehler des iPhones.
final class StepsNowTests: XCTestCase {

    private let today = CalendarDate(year: 2026, month: 10, day: 14)
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    private func mirror(_ steps: Int, on date: CalendarDate) -> StepsMirror.Snapshot {
        StepsMirror.Snapshot(date: date, steps: steps, updatedAt: Date())
    }

    /// Health hat die Uhr mit drin und liegt meist darueber - dann gilt Health.
    func testHealthWinsWhenItIsAhead() {
        let reading = StepsNow.combine(mirror: mirror(8_000, on: today), pedometer: 5_000, goal: 10_000, today: today)
        XCTAssertEqual(reading.steps, 8_000)
    }

    /// Seit dem letzten Blick der App ist das iPhone weitergelaufen - dann der Zaehler.
    func testThePedometerWinsWhenHealthIsOld() {
        let reading = StepsNow.combine(mirror: mirror(4_000, on: today), pedometer: 6_500, goal: 10_000, today: today)
        XCTAssertEqual(reading.steps, 6_500)
    }

    /// Ein Stand von gestern zaehlt heute nicht - um Mitternacht faengt es bei 0 an.
    func testYesterdaysMirrorIsIgnored() {
        let reading = StepsNow.combine(mirror: mirror(12_000, on: today.adding(days: -1)), pedometer: 300,
                                       goal: 10_000, today: today)
        XCTAssertEqual(reading.steps, 300)
        XCTAssertNil(StepsNow.combine(mirror: mirror(12_000, on: today.adding(days: -1)), pedometer: nil,
                                      goal: 10_000, today: today).steps,
                     "ohne Zaehler und ohne Stand von heute: unbekannt, nicht 0")
    }

    func testRatioStopsAtTheGoal() {
        XCTAssertEqual(StepsReading(steps: 15_000, goal: 10_000).ratio, 1)
        XCTAssertEqual(StepsReading(steps: 2_500, goal: 10_000).ratio, 0.25)
        XCTAssertEqual(StepsReading(steps: nil, goal: 10_000).ratio, 0)
        XCTAssertEqual(StepsReading(steps: 100, goal: 0).ratio, 0)
    }

    /// Alle 20 Minuten, aber um Mitternacht spaetestens eine Minute danach.
    func testRefreshEveryTwentyMinutesAndAfterMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
        XCTAssertEqual(StepsNow.nextRefresh(after: noon, in: berlin), noon.addingTimeInterval(20 * 60))
        let lateEvening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 23, minute: 50))!
        let afterMidnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 0, minute: 1))!
        XCTAssertEqual(StepsNow.nextRefresh(after: lateEvening, in: berlin), afterMidnight)
    }
}
