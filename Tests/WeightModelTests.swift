import XCTest
@testable import Healthy

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

    func testDecodesHighlight() throws {
        let json = Data(#"""
        [{"id":"a1b2c3d4","kind":"line","start":"2026-07-27","end":"2026-07-27",
          "label":"Beginn Uniblock","color":"#7c9cfa"},
         {"id":"k1","kind":"band","start":"2026-09-06","end":"2026-09-13",
          "label":null,"color":"#ef5350"}]
        """#.utf8)
        let highlights = try APIClient.decoder().decode([Highlight].self, from: json)
        XCTAssertEqual(highlights.count, 2)
        XCTAssertEqual(highlights[0].kind, .line)
        XCTAssertEqual(highlights[0].label, "Beginn Uniblock")
        XCTAssertEqual(highlights[0].colorValue, 0x7C9CFA)
        XCTAssertEqual(highlights[1].kind, .band)
        XCTAssertNil(highlights[1].label)
        XCTAssertEqual(highlights[1].end, CalendarDate(year: 2026, month: 9, day: 13))
    }

    /// Eine Farbe, die nicht wie #rrggbb aussieht, darf die Anzeige nicht
    /// kippen - dann gilt das alte Urlaubsblau.
    func testOddHighlightColorHasNoValue() throws {
        let json = Data(#"[{"id":"x","kind":"band","start":"2026-07-01","end":"2026-07-14","color":"red"}]"#.utf8)
        let highlights = try APIClient.decoder().decode([Highlight].self, from: json)
        XCTAssertNil(highlights.first?.colorValue)
    }

    /// Was der Dienst erwartet: `kind` klein, Daten als yyyy-MM-dd, `end`
    /// bei einer Linie weggelassen.
    func testEncodesNewHighlight() throws {
        let band = NewHighlightRequest(kind: .band,
                                       start: CalendarDate(year: 2026, month: 9, day: 6),
                                       end: CalendarDate(year: 2026, month: 9, day: 13),
                                       label: "krank", color: "#ef5350")
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(band)) as? [String: Any])
        XCTAssertEqual(object["kind"] as? String, "band")
        XCTAssertEqual(object["start"] as? String, "2026-09-06")
        XCTAssertEqual(object["end"] as? String, "2026-09-13")
        XCTAssertEqual(object["color"] as? String, "#ef5350")

        let line = NewHighlightRequest(kind: .line,
                                       start: CalendarDate(year: 2026, month: 7, day: 27),
                                       end: nil, label: nil, color: "#7c9cfa")
        let lineObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(line)) as? [String: Any])
        XCTAssertEqual(lineObject["kind"] as? String, "line")
        XCTAssertNil(lineObject["end"])
    }

    /// Farbwaehler -> Dienst -> Farbwaehler muss dieselbe Farbe ergeben,
    /// sonst springt die Auswahl der Vorgabe-Kreise beim Antippen weg.
    func testHexColorRoundTrips() {
        for preset in HighlightPalette.presets {
            XCTAssertEqual(preset.color.hexString, preset.hex, preset.name)
        }
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
