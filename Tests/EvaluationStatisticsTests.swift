import XCTest
@testable import Healthy

/// Die Sollwerte stammen aus scipy 1.x (`stats.pearsonr`, `stats.spearmanr`,
/// `stats.t.sf`, `special.betainc`) - nachgerechnet, nicht geschaetzt.
final class EvaluationStatisticsTests: XCTestCase {

    typealias S = EvaluationStatistics

    private let monday = CalendarDate(year: 2026, month: 9, day: 28)

    func testIncompleteBetaMatchesScipy() {
        XCTAssertEqual(S.regularizedIncompleteBeta(0.5, 2, 3), 0.6875, accuracy: 1e-12)
        XCTAssertEqual(S.regularizedIncompleteBeta(0.2, 0.5, 7.5), 0.9281204024988001, accuracy: 1e-10)
    }

    func testPearsonAndItsPValue() throws {
        let r = try XCTUnwrap(S.pearson([1, 2, 3, 4, 5], [2, 4, 5, 4, 5]))
        XCTAssertEqual(r, 0.7745966692414834, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(S.pValue(r, effectiveN: 5)), 0.12402706265755456, accuracy: 1e-9)
    }

    func testSpearmanWithTiesIsPearsonOnMidRanks() throws {
        XCTAssertEqual(S.ranks([1, 2, 2, 3]), [1, 2.5, 2.5, 4])
        let xs: [Double] = [1, 2, 2, 3, 5, 4], ys: [Double] = [2, 1, 4, 3, 6, 5]
        let rho = try XCTUnwrap(S.pearson(S.ranks(xs), S.ranks(ys)))
        XCTAssertEqual(rho, 0.8116794499134278, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(S.pValue(rho, effectiveN: 6)), 0.049857585101340404, accuracy: 1e-9)
    }

    func testPValueWithFractionalEffectiveN() throws {
        XCTAssertEqual(try XCTUnwrap(S.pValue(0.5, effectiveN: 20)), 0.024769558804109703, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(S.pValue(0.6, effectiveN: 13.7)), 0.025177842960682907, accuracy: 1e-9)
        XCTAssertEqual(S.pValue(1, effectiveN: 10), 0)
        XCTAssertNil(S.pValue(0.9, effectiveN: 3.9), "unter vier gibt es keinen p-Wert")
    }

    func testNoCoefficientWithoutVariation() {
        XCTAssertNil(S.pearson([5, 5, 5, 5, 5], [1, 2, 3, 4, 5]))
    }

    func testEffectiveNShrinksWithSharedAutocorrelation() {
        XCTAssertEqual(S.effectiveN(100, 0.5, 0.5), 60, accuracy: 1e-12)
        XCTAssertEqual(S.effectiveN(100, 0.5, -0.5), 100, "gegenlaeufig: nie mehr als n")
        XCTAssertEqual(S.effectiveN(100, 0, 0.9), 100)
    }

    func testHolm() throws {
        let adjusted = S.holm([0.01, nil, 0.04, 0.03])
        XCTAssertEqual(try XCTUnwrap(adjusted[0]), 0.03, accuracy: 1e-12)
        XCTAssertNil(adjusted[1])
        XCTAssertEqual(try XCTUnwrap(adjusted[2]), 0.06, accuracy: 1e-12, "nie kleiner als der davor")
        XCTAssertEqual(try XCTUnwrap(adjusted[3]), 0.06, accuracy: 1e-12)
        XCTAssertEqual(S.holm([0.6, 0.7]).compactMap { $0 }, [1, 1], "nie ueber 1")
    }

    func testStars() {
        XCTAssertEqual(S.stars(0.0004), "***")
        XCTAssertEqual(S.stars(0.004), "**")
        XCTAssertEqual(S.stars(0.04), "*")
        XCTAssertEqual(S.stars(0.05), "")
    }

    func testLagOneAutocorrelationSkipsGaps() throws {
        // 1, 2, 3, Luecke, 7, 8: Paare (1,2), (2,3), (7,8) - nicht (3,7).
        let values: [(Int, Double)] = [(0, 1), (1, 2), (2, 3), (4, 7), (5, 8)]
        let samples = values.map { S.Sample(date: monday.adding(days: $0.0), x: $0.1, y: 0) }
        let expected = try XCTUnwrap(S.pearson([1, 2, 7], [2, 3, 8]))
        XCTAssertEqual(try XCTUnwrap(S.lag1(samples, \.x)), expected, accuracy: 1e-12)
    }

    // MARK: - Paare aus den Antworten

    private let a = EvaluationQuestion(text: "Frage A")
    private let b = EvaluationQuestion(text: "Frage B")
    private let c = EvaluationQuestion(text: "Frage C")

    func testNextDayPairsTodayWithTomorrow() {
        var data = EvaluationData(questions: [a, b])
        data.set(4, for: a.id, on: monday)
        data.set(9, for: b.id, on: monday.adding(days: 1))
        data.set(6, for: a.id, on: monday.adding(days: 1))  // ohne B am Tag danach
        let samples = S.samples(data, first: a.id, second: b.id, kind: .nextDay,
                                from: monday, to: monday.adding(days: 2))
        XCTAssertEqual(samples, [S.Sample(date: monday, x: 4, y: 9)])
        XCTAssertEqual(S.samples(data, first: a.id, second: b.id, kind: .sameDay,
                                 from: monday, to: monday.adding(days: 2)),
                       [S.Sample(date: monday.adding(days: 1), x: 6, y: 9)])
    }

    func testThreeQuestionsGiveThreeSameDayAndSixNextDayResults() throws {
        var data = EvaluationData(questions: [a, b, c])
        for offset in 0..<40 {
            let day = monday.adding(days: offset)
            data.set(1 + offset % 10, for: a.id, on: day)
            data.set(1 + (offset * 3) % 10, for: b.id, on: day)
            data.set(10 - offset % 10, for: c.id, on: day)
        }
        let results = S.results(data, from: monday, to: monday.adding(days: 39))
        XCTAssertEqual(results.filter { $0.kind == .sameDay }.count, 3)
        XCTAssertEqual(results.filter { $0.kind == .nextDay }.count, 6)

        let ac = try XCTUnwrap(results.first { $0.kind == .sameDay && $0.first == a.id && $0.second == c.id })
        let rho = try XCTUnwrap(ac.estimates[.spearman])
        XCTAssertEqual(rho.coefficient, -1, accuracy: 1e-12, "C ist A gespiegelt")
        XCTAssertEqual(ac.n, 40)
        XCTAssertLessThan(rho.effectiveN, 40, "beide Reihen steigen von Tag zu Tag - n_eff schrumpft")
        XCTAssertEqual(try XCTUnwrap(rho.adjustedP), 0, accuracy: 1e-12)
    }

    func testTooFewPairsGiveNoEstimate() {
        var data = EvaluationData(questions: [a, b])
        for offset in 0..<4 {
            data.set(offset + 1, for: a.id, on: monday.adding(days: offset))
            data.set(offset + 2, for: b.id, on: monday.adding(days: offset))
        }
        let result = S.results(data, from: monday, to: monday.adding(days: 3))[0]
        XCTAssertEqual(result.n, 4)
        XCTAssertTrue(result.estimates.isEmpty)
    }
}
