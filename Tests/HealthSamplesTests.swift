import XCTest
@testable import Healthy

/// Health kennt beliebig viele Messungen pro Tag, der Weight Tracker genau
/// eine. Welche gewinnt, ist die einzige Entscheidung in diesem Teil - und
/// sie faellt hier.
final class HealthSamplesTests: XCTestCase {

    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    private func sample(_ day: Int, hour: Int, kg: Double) -> WeightSample {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: day,
                                                      hour: hour, minute: 0))!
        return WeightSample(takenAt: date, kilograms: kg)
    }

    /// Morgens nuechtern ist der vergleichbare Wert - eine Abendmessung liegt
    /// regelmaessig ein bis zwei Kilo darueber.
    func testTakesTheEarliestSampleOfADay() {
        let values = HealthSamples.dailyValues([
            sample(1, hour: 20, kg: 91.8),
            sample(1, hour: 7, kg: 90.1),
            sample(1, hour: 13, kg: 91.0),
        ], in: berlin)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.value, 90.1)
    }

    func testKeepsOneValuePerDayAndSortsThem() {
        let values = HealthSamples.dailyValues([
            sample(3, hour: 7, kg: 89.9),
            sample(1, hour: 7, kg: 90.1),
            sample(2, hour: 7, kg: 90.0),
        ], in: berlin)
        XCTAssertEqual(values.map(\.value), [90.1, 90.0, 89.9])
        XCTAssertEqual(values.map(\.date.day), [1, 2, 3])
    }

    /// Die Tagesgrenze richtet sich nach der Zeitzone des Geraets. Eine
    /// Messung um 00:30 Uhr Berliner Zeit gehoert zum neuen Tag - in UTC
    /// gerechnet waere sie noch der alte.
    func testDayBoundaryFollowsTheTimeZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        let justAfterMidnight = calendar.date(from: DateComponents(
            year: 2026, month: 9, day: 2, hour: 0, minute: 30))!
        let values = HealthSamples.dailyValues(
            [WeightSample(takenAt: justAfterMidnight, kilograms: 90.5)], in: berlin)
        XCTAssertEqual(values.first?.date, CalendarDate(year: 2026, month: 9, day: 2))
    }

    func testEmptyInputGivesEmptyOutput() {
        XCTAssertTrue(HealthSamples.dailyValues([], in: berlin).isEmpty)
    }
}
