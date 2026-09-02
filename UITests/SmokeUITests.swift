import XCTest

/// Schritt 0: nur starten. Der Sinn ist nicht der Test, sondern der Nachweis,
/// dass das UI-Test-Target gebaut, signiert und ausgefuehrt wird.
final class SmokeUITests: XCTestCase {

    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }
}
