import XCTest
@testable import Cockpit

/// Die beiden Datumsformate sind der Stolperstein an der Schnittstelle
/// (siehe docs/BACKENDS.md) - deshalb haben sie Tests und nichts anderes
/// aus Phase 0.
final class CalendarDateTests: XCTestCase {

    func testParsesSpringLocalDate() throws {
        let date = try XCTUnwrap(CalendarDate(iso: "2026-09-01"))
        XCTAssertEqual(date.year, 2026)
        XCTAssertEqual(date.month, 9)
        XCTAssertEqual(date.day, 1)
        XCTAssertEqual(date.iso, "2026-09-01")
    }

    func testRejectsNonsense() {
        XCTAssertNil(CalendarDate(iso: "01.09.2026"))
        XCTAssertNil(CalendarDate(iso: "2026-13-01"))
        XCTAssertNil(CalendarDate(iso: ""))
    }

    /// Ein Tag bleibt ein Tag: kein Zeitzonen-Versatz beim Hin- und Zurueck.
    func testRoundTripThroughJSON() throws {
        let original = CalendarDate(year: 2026, month: 1, day: 5)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"2026-01-05\"")
        XCTAssertEqual(try JSONDecoder().decode(CalendarDate.self, from: data), original)
    }

    func testSortsChronologically() {
        XCTAssertTrue(CalendarDate(year: 2025, month: 12, day: 31)
                      < CalendarDate(year: 2026, month: 1, day: 1))
    }
}

final class InstantParsingTests: XCTestCase {

    /// Jackson haengt an `Instant` je nach Wert unterschiedlich viele
    /// Nachkommastellen - bis zu neun. Alle Varianten muessen durchgehen.
    func testParsesInstantWithAnyFractionLength() throws {
        let variants = [
            "2026-09-01T08:15:30Z",
            "2026-09-01T08:15:30.123Z",
            "2026-09-01T08:15:30.123456789Z",
        ]
        for raw in variants {
            XCTAssertNotNil(APIClient.parseInstant(raw), "gescheitert an \(raw)")
        }
    }

    func testDecoderReadsInstantField() throws {
        struct Probe: Decodable { let createdAt: Date }
        let json = Data(#"{"createdAt":"2026-09-01T08:15:30.123456789Z"}"#.utf8)
        let probe = try APIClient.decoder().decode(Probe.self, from: json)
        XCTAssertEqual(probe.createdAt.timeIntervalSince1970, 1_788_250_530, accuracy: 1)
    }
}
