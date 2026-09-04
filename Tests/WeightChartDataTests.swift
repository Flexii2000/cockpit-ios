import XCTest
@testable import Healthy

/// Das Zerlegen der Mittelwert-Linie ist die einzige Stelle im Diagramm mit
/// echter Logik - und die, an der ein Fehler am schwersten auffaellt: eine
/// falsch gesetzte Grenze sieht aus wie ein Datenproblem.
final class WeightChartDataTests: XCTestCase {

    private func point(_ day: Int, avg7: Double?, complete: Bool) -> WeightPoint {
        let json = """
        {"date":"2026-08-\(String(format: "%02d", day))","measured":null,
         "avg7":\(jsonNumber(avg7)),"avg14":null,"avg30":null,
         "avg7Complete":\(complete),"avg14Complete":false,"avg30Complete":false,
         "target":82.0}
        """
        return try! APIClient.decoder().decode(WeightPoint.self, from: Data(json.utf8))
    }

    func testKeepsOneSegmentWhenNothingChanges() {
        let points = (1...5).map { point($0, avg7: 83.0, complete: true) }
        let segments = WeightChartData.segments(points, series: .avg7,
                                                value: \.avg7, complete: \.avg7Complete)
        XCTAssertEqual(segments.count, 1)
        XCTAssertTrue(segments[0].complete)
        XCTAssertEqual(segments[0].samples.count, 5)
    }

    /// Der Punkt am Umschlag muss in beiden Abschnitten stecken, sonst reisst
    /// die Linie dort sichtbar ab.
    func testSplitsAtCompletenessChangeAndOverlaps() {
        let points = (1...3).map { point($0, avg7: 83.0, complete: true) }
                  + (4...6).map { point($0, avg7: 82.5, complete: false) }
        let segments = WeightChartData.segments(points, series: .avg7,
                                                value: \.avg7, complete: \.avg7Complete)
        XCTAssertEqual(segments.count, 2)
        XCTAssertTrue(segments[0].complete)
        XCTAssertFalse(segments[1].complete)
        XCTAssertEqual(segments[0].samples.last, segments[1].samples.first,
                       "Der Punkt am Umschlag gehoert in beide Abschnitte")
    }

    func testSkipsGapsWithoutValue() {
        let points = [point(1, avg7: 83.0, complete: true),
                      point(2, avg7: nil, complete: true),
                      point(3, avg7: 82.8, complete: true)]
        let segments = WeightChartData.segments(points, series: .avg7,
                                                value: \.avg7, complete: \.avg7Complete)
        XCTAssertEqual(segments.first?.samples.count, 2)
    }

    /// Zwei Punkte, dazwischen der Umschlag: das Stueck dazwischen gehoert
    /// zum frueheren Punkt (durchgezogen), und der einzelne Punkt danach
    /// ergibt keine eigene Linie - daraus darf keine leere Serie entstehen.
    func testSinglePointAfterChangeDoesNotBecomeItsOwnSegment() {
        let points = [point(1, avg7: 83.0, complete: true),
                      point(2, avg7: 82.0, complete: false)]
        let segments = WeightChartData.segments(points, series: .avg7,
                                                value: \.avg7, complete: \.avg7Complete)
        XCTAssertEqual(segments.count, 1)
        XCTAssertTrue(segments[0].complete)
        XCTAssertEqual(segments[0].samples.count, 2)
    }

    func testOnlyVisibleSeriesProduceSegments() {
        let points = (1...4).map { point($0, avg7: 83.0, complete: true) }
        XCTAssertTrue(WeightChartData.averageSegments(points, visible: []).isEmpty)
        XCTAssertEqual(WeightChartData.averageSegments(points, visible: [.avg7]).count, 1)
    }
}
