import XCTest
@testable import Healthy

/// Die Fokus-Sessions des Waldes, so wie der Habits-Dienst sie liefert und
/// annimmt. Die Habits selbst sind nach coHabit umgezogen - ihre Tests
/// liegen bei coHabit (CohabitTests).
final class FocusModelTests: XCTestCase {

    /// Eine Session, wie `/api/focus/sessions` sie liefert - Zeitpunkte mit
    /// Nachkommastellen, der Tag als yyyy-MM-dd.
    func testDecodesFocusSession() throws {
        let session = try APIClient.decoder().decode([FocusSession].self, from: """
        [{"id":"a1","start":"2026-09-20T12:00:00.123456Z","end":"2026-09-20T13:30:00Z",
          "minutes":90,"day":"2026-09-20"}]
        """.data(using: .utf8)!)[0]
        XCTAssertEqual(session.minutes, 90)
        XCTAssertEqual(session.day, CalendarDate(year: 2026, month: 9, day: 20))
        XCTAssertEqual(session.end.timeIntervalSince(session.start), 5_400, accuracy: 1)
    }

    /// Was die App meldet, muss Jacksons `Instant` lesen koennen: ISO mit `Z`,
    /// keine Sekunden-seit-2001.
    func testFocusSessionDraftSendsInstants() throws {
        let start = Date(timeIntervalSince1970: 1_789_000_000)
        let draft = FocusSessionDraft(id: "b2", start: start, end: start.addingTimeInterval(1_800))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: APIClient.encoder().encode(draft)) as? [String: Any])
        XCTAssertEqual(object["id"] as? String, "b2")
        XCTAssertEqual(object["start"] as? String, "2026-09-10T00:26:40Z")
        XCTAssertEqual(object["end"] as? String, "2026-09-10T00:56:40Z")
        // Und zurueck: derselbe Zeitpunkt, wie ihn der Dienst spaeter liefert.
        XCTAssertEqual(APIClient.parseInstant("2026-09-10T00:26:40Z"), start)
    }

    /// „2:15/4:00 h" - der Stand von heute gegen das Tagesziel.
    func testFormatsMinutesAsHours() {
        XCTAssertEqual(FocusMinutes.hours(0), "0:00")
        XCTAssertEqual(FocusMinutes.hours(605), "10:05")
        XCTAssertEqual(FocusMinutes.progress(135, goal: 240), "2:15/4:00 h")
    }

    /// Die Habits-Kachel ist weg; die Kennung darf nicht mehr auftauchen,
    /// sonst laedt die App eine Kachel neu, die es nicht gibt.
    func testWidgetKindsWithoutHabits() {
        XCTAssertEqual(WidgetKind.focus, "FocusCountdown")
        XCTAssertEqual(WidgetKind.calories, "CaloriesRemaining")
    }
}
