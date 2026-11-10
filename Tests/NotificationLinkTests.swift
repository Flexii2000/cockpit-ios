import XCTest
@testable import Healthy

/// Der Link in einer Push-Nutzlast - bei Fokus der Weg vom Feature Request
/// zur Karte. Was kein http(s) ist, wird nicht geoeffnet.
final class NotificationLinkTests: XCTestCase {

    func testReadsTheLinkNextToKind() {
        let userInfo: [AnyHashable: Any] = [
            "kind": "todo", "link": "https://fherrmann.com/feature-requests/42"
        ]
        XCTAssertEqual(NotificationDelegate.link(in: userInfo)?.absoluteString,
                       "https://fherrmann.com/feature-requests/42")
    }

    /// `kind`, ersatzweise `tab` - daran entscheidet die App, wohin ein Tipp
    /// fuehrt und ob eine Meldung bei offener App als Banner erscheint.
    func testKindFallsBackToTab() {
        XCTAssertEqual(NotificationDelegate.kind(in: ["kind": "chat-answer", "tab": "cloud"]), "chat-answer")
        XCTAssertEqual(NotificationDelegate.kind(in: ["tab": "cloud"]), "cloud")
        XCTAssertNil(NotificationDelegate.kind(in: ["aps": ["alert": "x"]]))
        XCTAssertNil(NotificationDelegate.kind(in: ["kind": 7]))
    }

    func testWithoutLinkThereIsNone() {
        XCTAssertNil(NotificationDelegate.link(in: ["kind": "todo"]))
        XCTAssertNil(NotificationDelegate.link(in: ["kind": "todo", "link": ""]))
        XCTAssertNil(NotificationDelegate.link(in: ["kind": "todo", "link": 42]))
    }

    func testOnlyWebAddressesAreOpened() {
        XCTAssertNil(NotificationDelegate.link(in: ["link": "javascript:alert(1)"]))
        XCTAssertNil(NotificationDelegate.link(in: ["link": "cohabit://today"]))
        XCTAssertNil(NotificationDelegate.link(in: ["link": "fherrmann.com/feature-requests/42"]))
        XCTAssertNotNil(NotificationDelegate.link(in: ["link": "HTTP://Example.org/A"]))
    }
}
