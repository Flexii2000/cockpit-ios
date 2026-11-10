import XCTest
@testable import Healthy

/// Der Satz aus einer Fehlerantwort. Der Kalorienzaehler schreibt ihn als
/// Klartext, der Weight Tracker im Fehler-Rumpf von Spring - gezeigt wird in
/// beiden Faellen nur der Satz.
final class APIErrorMessageTests: XCTestCase {

    private func message(_ body: String) -> String? {
        APIClient.shortMessage(from: Data(body.utf8))
    }

    func testPlainTextStaysAsItIs() {
        XCTAssertEqual(message("Die Anteile müssen zusammen 100 % ergeben.\n"),
                       "Die Anteile müssen zusammen 100 % ergeben.")
    }

    /// `ResponseStatusException` beim Weight Tracker - nur `message` zaehlt.
    func testSpringErrorBodyYieldsItsMessage() {
        XCTAssertEqual(message("""
        {"timestamp":"2026-11-10T12:39:55.700+00:00","status":409,"error":"Conflict",
         "message":"Eine Antwort läuft noch.","path":"/api/chat/messages"}
        """), "Eine Antwort läuft noch.")
    }

    /// Kein Satz darin: lieber keiner als das rohe JSON oder eine HTML-Seite.
    func testWhatIsNotASentenceIsDropped() {
        XCTAssertNil(message(#"{"status":500,"error":"Internal Server Error"}"#))
        XCTAssertNil(message(#"{"message":""}"#))
        XCTAssertNil(message("{kaputt"))
        XCTAssertNil(message("<html><body>403</body></html>"))
        XCTAssertNil(message("   "))
        XCTAssertNil(message(String(repeating: "x", count: 301)))
        XCTAssertNil(message(#"{"message":"\#(String(repeating: "x", count: 301))"}"#))
    }
}
