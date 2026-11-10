import XCTest
@testable import Healthy

/// Der Wochenrueckblick (Vertrag §5 und §9): sechs Felder mit Pfeil gegen die
/// Vorwoche - eine Richtung, keine Wertung.
final class WeekReviewFormatTests: XCTestCase {

    private let monday = CalendarDate(year: 2026, month: 11, day: 2)

    private func stats(offset: Int = 0, kcal: Double? = 2180, deficit: Double? = 410, tracked: Int = 6,
                       delta: Double? = -0.42, green: Int = 4, yellow: Int = 1, red: Int = 1,
                       steps: Double? = 9120, strain: Double? = 11.8) -> WeekStats {
        let from = monday.adding(days: offset)
        return WeekStats(from: from, to: from.adding(days: 6), kcalAvg: kcal, deficitAvg: deficit,
                         trackedDays: tracked, weightAvg: 91.4, weightDays: 6, weightDeltaKg: delta,
                         proteinGreenDays: green, proteinYellowDays: yellow, proteinRedDays: red,
                         stepsAvg: steps, stepsDays: 7, strainAvg: strain, strainDays: 6)
    }

    /// Die sechs Felder des Vertrags, in ihrer Reihenfolge und Schreibweise.
    func testCellsOfAFullWeek() throws {
        let previous = stats(offset: -7, kcal: 2290, deficit: 320, tracked: 7, delta: -0.2, green: 3, yellow: 3,
                             steps: 9120.4, strain: 10.9)
        let model = try XCTUnwrap(WeekReviewCardModel(WeekReview(week: stats(), previous: previous)))
        XCTAssertEqual(model.range, "02.11.–08.11.")
        XCTAssertEqual(model.cells.map(\.title),
                       ["kcal ⌀", "Defizit ⌀", "Gewicht", "Eiweiß-Tage", "Schritte ⌀", "Strain ⌀"])
        XCTAssertEqual(model.cells.map(\.value), ["2.180 kcal", "410 kcal", "−0,4 kg", "", "9.120", "11,8"])
        XCTAssertEqual(model.cells.map(\.arrow), [.down, .up, .down, .up, .same, .up])
        XCTAssertEqual(model.cells[3].protein, .init(green: 4, yellow: 1))
        XCTAssertNil(model.cells[0].protein)
    }

    /// Verglichen wird, was zu sehen ist: gerundet gleich ist gleich.
    func testArrowComparesWhatIsShown() {
        XCTAssertEqual(WeekReviewCardModel.arrow(2180.4, 2179.6, decimals: 0), .same)
        XCTAssertEqual(WeekReviewCardModel.arrow(11.84, 11.76, decimals: 1), .same)
        XCTAssertEqual(WeekReviewCardModel.arrow(11.9, 11.7, decimals: 1), .up)
        XCTAssertEqual(WeekReviewCardModel.arrow(-120, 40, decimals: 0), .down)
        XCTAssertNil(WeekReviewCardModel.arrow(nil, 40, decimals: 0))
        XCTAssertNil(WeekReviewCardModel.arrow(40, nil, decimals: 0))
    }

    /// Ohne Vorwoche und ohne einzelne Werte: ein Strich, kein Pfeil - beim
    /// Gewicht sagt der Wert selbst die Richtung.
    func testMissingValuesAndNoPreviousWeek() throws {
        let week = stats(kcal: nil, deficit: nil, tracked: 0, delta: 0.31, green: 0, yellow: 0, red: 0, strain: nil)
        let model = try XCTUnwrap(WeekReviewCardModel(WeekReview(week: week, previous: nil)))
        XCTAssertEqual(model.cells.map(\.value), ["–", "–", "+0,3 kg", "–", "9.120", "–"])
        XCTAssertEqual(model.cells.map(\.arrow), [nil, nil, .up, nil, nil, nil])
        XCTAssertNil(model.cells[3].protein, "ohne getrackten Tag keine Punkte")

        let flat = try XCTUnwrap(WeekReviewCardModel(WeekReview(week: stats(delta: 0.04), previous: nil)))
        XCTAssertEqual(flat.cells[2].value, "0,0 kg")
        XCTAssertEqual(flat.cells[2].arrow, .same)
    }

    /// Ein Ueberschuss steht als negatives Defizit da, wie in den Kacheln.
    func testSurplusIsANegativeDeficit() throws {
        let model = try XCTUnwrap(WeekReviewCardModel(WeekReview(week: stats(deficit: -120), previous: nil)))
        XCTAssertEqual(model.cells[1].value, "−120 kcal")
    }

    /// Eine Woche ohne einen einzigen Wert: die Karte fehlt.
    func testAnEmptyWeekHidesTheCard() {
        let empty = stats(kcal: nil, deficit: nil, tracked: 0, delta: nil, green: 0, yellow: 0, red: 0,
                          steps: nil, strain: nil)
        XCTAssertNil(WeekReviewCardModel(WeekReview(week: empty, previous: stats(offset: -7))))
        XCTAssertNil(WeekReviewCardModel(nil))
    }
}
