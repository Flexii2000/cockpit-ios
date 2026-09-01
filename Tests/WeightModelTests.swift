import XCTest
@testable import Cockpit

/// `String.init` ist fuer `Double?` mehrdeutig - in einer Interpolation
/// kapituliert der Typpruefer daran. Deshalb explizit.
func jsonNumber(_ value: Double?) -> String {
    guard let value else { return "null" }
    return String(value)
}

/// Die JSON-Auszuege stammen aus den Java-Records in
/// `../weight-app/src/main/java/…` - nicht aus dem Gedaechtnis, sondern
/// Feld fuer Feld nachgesehen (siehe docs/BACKENDS.md).
final class WeightModelTests: XCTestCase {

    func testDecodesPointWithGaps() throws {
        let json = Data("""
        {"date":"2026-08-30","measured":null,"avg7":83.4,"avg14":null,"avg30":null,
         "avg7Complete":false,"avg14Complete":false,"avg30Complete":false,"target":82.9}
        """.utf8)
        let point = try APIClient.decoder().decode(WeightPoint.self, from: json)
        XCTAssertEqual(point.date, CalendarDate(year: 2026, month: 8, day: 30))
        XCTAssertNil(point.measured)
        XCTAssertEqual(point.avg7, 83.4)
        XCTAssertFalse(point.avg7Complete)
        XCTAssertEqual(point.target, 82.9)
    }

    func testDecodesSummary() throws {
        let json = Data("""
        {"date":"2026-09-01","current":83.2,"avg7":83.5,"avg14":83.8,"avg30":84.4,
         "target":82.7,"targetDate":"2026-12-20","goalWeight":82.0,"startWeight":92.0,
         "recordingStart":"2025-01-05","corridorLower":80.5,"corridorUpper":83.5,
         "corridorReachedOn":"2026-07-14"}
        """.utf8)
        let summary = try APIClient.decoder().decode(WeightSummary.self, from: json)
        XCTAssertEqual(summary.current, 83.2)
        XCTAssertTrue(summary.isInCorridor)
        XCTAssertEqual(summary.activeCorridor?.lower, 80.5)
    }

    /// Solange der Korridor nie erreicht war, ist er kein Massstab - dann
    /// darf er weder gezeichnet noch zur Einfaerbung benutzt werden.
    func testCorridorCountsOnlyOnceReached() throws {
        let json = Data("""
        {"date":"2026-09-01","current":83.2,"avg7":null,"avg14":null,"avg30":null,
         "target":82.7,"targetDate":null,"goalWeight":82.0,"startWeight":92.0,
         "recordingStart":null,"corridorLower":80.5,"corridorUpper":83.5,
         "corridorReachedOn":null}
        """.utf8)
        let summary = try APIClient.decoder().decode(WeightSummary.self, from: json)
        XCTAssertFalse(summary.isInCorridor)
        XCTAssertNil(summary.activeCorridor)
    }

    func testDecodesVacation() throws {
        let json = Data(#"[{"start":"2026-07-01","end":"2026-07-14","label":"Norwegen"}]"#.utf8)
        let vacations = try APIClient.decoder().decode([Vacation].self, from: json)
        XCTAssertEqual(vacations.first?.label, "Norwegen")
        XCTAssertEqual(vacations.first?.end, CalendarDate(year: 2026, month: 7, day: 14))
    }
}

final class WeightWidgetTests: XCTestCase {

    private func summary(current: Double? = 83.2, target: Double? = 82.7,
                         corridorReached: Bool = true) -> WeightSummary {
        let json = """
        {"date":"2026-09-01","current":\(jsonNumber(current)),
         "avg7":83.5,"avg14":null,"avg30":null,
         "target":\(jsonNumber(target)),
         "targetDate":"2026-12-20","goalWeight":82.0,"startWeight":92.0,
         "recordingStart":"2025-01-05","corridorLower":80.5,"corridorUpper":83.5,
         "corridorReachedOn":\(corridorReached ? "\"2026-07-14\"" : "null")}
        """
        return try! APIClient.decoder().decode(WeightSummary.self, from: Data(json.utf8))
    }

    /// Im Korridor ist gruen, auch wenn der Tageswert der Zielkurve knapp
    /// darunter liegt - sonst faerbte sich die Kachel bei jeder normalen
    /// Tagesschwankung um.
    func testDiffIsGoodInsideCorridor() {
        XCTAssertEqual(WeightWidget.diff.tone(summary()), .good)
    }

    func testDiffWarnsSlightlyAboveTargetOutsideCorridor() {
        let s = summary(current: 90.0, target: 89.5, corridorReached: false)
        XCTAssertEqual(WeightWidget.diff.tone(s), .warn)
        XCTAssertEqual(WeightWidget.diff.value(s), "+0.5 kg")
    }

    func testDiffIsBadWellAboveTarget() {
        XCTAssertEqual(WeightWidget.diff.tone(summary(current: 95.0, target: 89.5,
                                                      corridorReached: false)), .bad)
    }

    func testBmiUsesConfiguredHeight() {
        // 83,2 kg bei 1,94 m -> 22,1
        XCTAssertEqual(WeightWidget.bmi.value(summary()), "22.1")
        XCTAssertEqual(WeightWidget.bmi.tone(summary()), .good)
    }

    func testProgressCountsFromStartToGoal() {
        // Start 92, Ziel 82, aktuell 83.2 -> 8.8 von 10 kg -> 88 %
        XCTAssertEqual(WeightWidget.progress.value(summary()), "88 %")
    }

    func testMissingValuesShowDash() {
        let s = summary(current: nil)
        XCTAssertEqual(WeightWidget.current.value(s), "–")
        XCTAssertEqual(WeightWidget.bmi.value(s), "–")
        XCTAssertNil(WeightWidget.diff.tone(s))
    }
}
