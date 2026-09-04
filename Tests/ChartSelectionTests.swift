import XCTest
@testable import Healthy

/// Welcher Tag beim Ziehen getroffen wird. Die Geste selbst laesst sich im
/// Simulator nicht ausloesen - die Zuordnung dahinter schon.
final class ChartSelectionTests: XCTestCase {

    private let days = [
        CalendarDate(year: 2026, month: 8, day: 1),
        CalendarDate(year: 2026, month: 8, day: 15),
        CalendarDate(year: 2026, month: 9, day: 1),
    ]

    func testPicksTheClosestDay() {
        let mitteAugust = CalendarDate(year: 2026, month: 8, day: 14).startOfDay()
        XCTAssertEqual(ChartSelection.nearestDay(to: mitteAugust, in: days),
                       CalendarDate(year: 2026, month: 8, day: 15))
    }

    /// Zwischen zwei Messungen liegen im Verlauf manchmal Wochen. Getroffen
    /// wird trotzdem einer der beiden - sonst zeigte die Sprechblase in
    /// Luecken gar nichts, obwohl der Finger im Diagramm steht.
    func testPicksAcrossALongGap() {
        let dazwischen = CalendarDate(year: 2026, month: 8, day: 24).startOfDay()
        XCTAssertEqual(ChartSelection.nearestDay(to: dazwischen, in: days),
                       CalendarDate(year: 2026, month: 9, day: 1))
    }

    func testClampsBeyondTheEdges() {
        let vorher = CalendarDate(year: 2020, month: 1, day: 1).startOfDay()
        XCTAssertEqual(ChartSelection.nearestDay(to: vorher, in: days), days.first)

        let danach = CalendarDate(year: 2030, month: 1, day: 1).startOfDay()
        XCTAssertEqual(ChartSelection.nearestDay(to: danach, in: days), days.last)
    }

    func testWithoutDataThereIsNothingToSelect() {
        XCTAssertNil(ChartSelection.nearestDay(to: Date(), in: []))
    }
}
