import XCTest
@testable import Healthy

/// „Distanz z. Target" im Gewicht-Diagramm (Vertrag §5): Mittel minus
/// Zielkurve auf eigener Skala, und wem die rechte Seite gehoert - ablesen
/// kann der Simulator nichts davon, die Ziehgeste fehlt ihm.
final class TargetDistanceChartTests: XCTestCase {

    private func point(_ day: Int, avg7: Double?, avg30: Double? = nil, target: Double?,
                       complete7: Bool = true, complete30: Bool = true) -> WeightPoint {
        let json = """
        {"date":"2026-08-\(String(format: "%02d", day))","measured":null,
         "avg7":\(jsonNumber(avg7)),"avg14":null,"avg30":\(jsonNumber(avg30)),
         "avg7Complete":\(complete7),"avg14Complete":false,"avg30Complete":\(complete30),
         "target":\(jsonNumber(target))}
        """
        return try! APIClient.decoder().decode(WeightPoint.self, from: Data(json.utf8))
    }

    // MARK: - Werte

    /// Je Tag Mittel minus Zielkurve; ohne Zielkurve (vor dem
    /// Aufzeichnungsbeginn) oder ohne Mittel kein Wert.
    func testDistanceIsTheAverageMinusTheTarget() {
        let points = [point(1, avg7: 84.0, target: nil),
                      point(2, avg7: 83.5, target: 83.0),
                      point(3, avg7: nil, target: 82.9),
                      point(4, avg7: 82.4, target: 82.8)]
        let values = WeightChartData.targetDistances(points, average: .avg7)
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(values[0], 0.5, accuracy: 1e-9)
        XCTAssertEqual(values[1], -0.4, accuracy: 1e-9, "unter der Zielkurve negativ")
        XCTAssertNil(WeightChartData.targetDistance(of: points[0], average: .avg7))
        XCTAssertEqual(WeightChartData.targetDistance(of: points[1], average: .avg7)!, 0.5, accuracy: 1e-9)
    }

    /// In „Alles" misst sie am 30er, wie das Gewicht dort gezeigt wird.
    func testAllTimeMeasuresAgainstTheThirtyDayAverage() {
        let only = point(1, avg7: 84.0, avg30: 83.2, target: 83.0)
        XCTAssertEqual(WeightRange.allTime.distanceAverage, .avg30)
        XCTAssertEqual(WeightRange.threeYears.distanceAverage, .avg7)
        XCTAssertEqual(WeightRange.month.distanceAverage, .avg7)
        XCTAssertEqual(WeightChartData.targetDistance(of: only, average: .avg30)!, 0.2, accuracy: 1e-9)
        XCTAssertEqual(WeightChartData.targetDistance(of: only, average: .avg7)!, 1.0, accuracy: 1e-9)
    }

    /// Gepunktet, wo das Mittel dahinter noch offen ist - am 30er gemessen
    /// zaehlt dessen Flagge, nicht die des 7ers.
    func testSegmentsFollowTheCompletenessOfTheirAverage() {
        let points = (1...3).map { point($0, avg7: 83.5, avg30: 83.4, target: 83.0) }
                   + (4...5).map { point($0, avg7: 83.2, avg30: 83.3, target: 82.9,
                                         complete7: false, complete30: true) }
        let seven = WeightChartData.targetDistanceSegments(points, average: .avg7)
        XCTAssertEqual(seven.map(\.complete), [true, false])
        XCTAssertEqual(seven.map(\.series), [.targetDistance, .targetDistance])
        XCTAssertEqual(seven[0].samples.last, seven[1].samples.first, "der Umschlag gehoert in beide")
        XCTAssertEqual(seven[0].samples[0].value, 0.5, accuracy: 1e-9, "die Werte in kg")

        let thirty = WeightChartData.targetDistanceSegments(points, average: .avg30)
        XCTAssertEqual(thirty.map(\.complete), [true])
        XCTAssertEqual(thirty[0].samples.count, 5)
    }

    func testMappedSegmentKeepsDaysAndFlags() {
        let points = (1...3).map { point($0, avg7: 83.5, target: 83.0) }
        let segment = WeightChartData.targetDistanceSegments(points, average: .avg7)[0]
        let mapped = segment.mapped { $0 * 10 }
        XCTAssertEqual(mapped.id, segment.id)
        XCTAssertEqual(mapped.complete, segment.complete)
        XCTAssertEqual(mapped.samples.map(\.date), segment.samples.map(\.date))
        XCTAssertEqual(mapped.samples[0].value, 5, accuracy: 1e-9)
    }

    // MARK: - Skala

    /// 0,5 kg je Schritt, die 0 immer dabei - wie im Web.
    func testScaleInHalfKilograms() {
        let scale = ZeroLineScale.targetDistance([-0.4, 1.2])
        XCTAssertEqual(scale.step, 0.5)
        XCTAssertEqual(scale.domain, -0.5...1.5)
        XCTAssertEqual(scale.ticks, [-0.5, 0, 0.5, 1, 1.5])
        XCTAssertEqual(scale.insideTicks, [-0.5, 0, 1.5])
    }

    /// Ueber 3 kg Spanne ganze Kilogramm, ueber 8 kg zwei; genau 3 bleibt
    /// bei 0,5. Ohne Werte trotzdem zwei Schritte.
    func testScaleStepsGrowWithTheSpan() {
        XCTAssertEqual(ZeroLineScale.targetDistance([0, 3]).step, 0.5)
        XCTAssertEqual(ZeroLineScale.targetDistance([-0.5, 2.6]).step, 1)
        XCTAssertEqual(ZeroLineScale.targetDistance([-0.5, 2.6]).domain, -1...3)
        XCTAssertEqual(ZeroLineScale.targetDistance([-1, 7.5]).step, 2)
        XCTAssertEqual(ZeroLineScale.targetDistance([-1, 7.5]).domain, -2...8)
        XCTAssertEqual(ZeroLineScale.targetDistance([]).domain, 0...1)
        XCTAssertEqual(ZeroLineScale.targetDistance([0.1]).domain, 0...1, "mindestens zwei Schritte")
    }

    /// Das Defizit rechnet nach dem Verallgemeinern wie vorher.
    func testDeficitScaleIsUnchanged() {
        XCTAssertEqual(ZeroLineScale.deficit([300, 620]).domain, 0...750)
        XCTAssertEqual(ZeroLineScale.deficit([-900, 1200]).step, 500)
    }

    /// „+1", „+0,5", „0", „−0,5" - mit echtem Minus.
    func testTickLabels() {
        XCTAssertEqual(WeightChartData.distanceTick(1), "+1")
        XCTAssertEqual(WeightChartData.distanceTick(0.5), "+0,5")
        XCTAssertEqual(WeightChartData.distanceTick(0), "0")
        XCTAssertEqual(WeightChartData.distanceTick(-0.5), "\u{2212}0,5")
        XCTAssertEqual(WeightChartData.distanceTick(-2), "\u{2212}2")
    }

    // MARK: - Rechte Seite

    /// Erst kcal, dann Defizit, dann Distanz - und eine Reihe ohne Werte
    /// belegt nichts.
    func testTrailingScaleOrder() {
        func owner(_ visible: Set<WeightSeries>, deficit: Bool = true, distance: Bool = true)
            -> WeightChartData.TrailingScale {
            WeightChartData.trailingScale(visible: visible, hasDeficit: deficit, hasDistance: distance)
        }
        XCTAssertEqual(owner([.avg7, .targetDistance]), .targetDistance)
        XCTAssertEqual(owner([.avg7, .deficit, .targetDistance]), .deficit)
        XCTAssertEqual(owner([.kcal, .deficit, .targetDistance]), .kcal)
        XCTAssertEqual(owner([.expenditure, .targetDistance]), .kcal)
        XCTAssertEqual(owner([.deficit, .targetDistance], deficit: false), .targetDistance,
                       "ohne Uhr gibt es kein Defizit, das den Platz braucht")
        XCTAssertEqual(owner([.targetDistance], distance: false), WeightChartData.TrailingScale.none)
        XCTAssertEqual(owner([.avg7, .target]), WeightChartData.TrailingScale.none)
    }

    // MARK: - Angebot

    /// Direkt hinter der Zielkurve, in jedem Zeitraum, nie vorgewaehlt
    /// (Felix, 19.10.).
    func testOfferedRightAfterTheTargetButNotPreselected() {
        for range in WeightRange.allCases {
            let offered = range.offeredSeries
            let target = offered.firstIndex(of: .target)
            XCTAssertEqual(offered.firstIndex(of: .targetDistance), target.map { $0 + 1 }, range.title)
            XCTAssertTrue(range.availableSeries.contains(.targetDistance), range.title)
            XCTAssertFalse(range.defaultVisible.contains(.targetDistance), range.title)
        }
        XCTAssertEqual(WeightSeries.targetDistance.title, "Distanz z. Target")
    }
}
