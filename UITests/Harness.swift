import XCTest

/// Was der Simulator allein nicht kann: tippen, wischen, scrollen.
///
/// Gemeinsam fuer die drei UI-Test-Bundles (Healthy, Vault, Fokus) - die Datei
/// ist in allen dreien eingebunden. `XCUIApplication()` ist dabei immer die
/// App, an der das jeweilige Bundle haengt.
extension XCTestCase {

    /// Startet die App mit Zugang und ohne Systemdialoge.
    ///
    /// Die drei Schalter sind kein Beiwerk: den Health-Dialog kann
    /// `addUIInterruptionMonitor` nicht verlaesslich wegklicken (er ist kein
    /// Springboard-Alert), Face ID kann XCUITest gar nicht bedienen, und ohne
    /// den dritten meldet jeder Lauf eine Push-Kennung beim food-Backend an.
    func start(tab: String, extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        let environment = ProcessInfo.processInfo.environment
        app.launchEnvironment = [
            "COCKPIT_FH_PRIVATE_TOKEN": environment["COCKPIT_FH_PRIVATE_TOKEN"] ?? "",
            "COCKPIT_WEIGHT_TOKEN": environment["COCKPIT_WEIGHT_TOKEN"] ?? "",
            "COCKPIT_TAB": tab,
            "COCKPIT_NO_HEALTH": "1",
            "COCKPIT_NO_PUSH": "1",
            // Vault sperrt die ganze App, und XCUITest kann kein Gesicht
            // vorzeigen - ohne das saehe jeder Test dort nur den Sperrbildschirm.
            "COCKPIT_NO_LOCK": "1",
        ].merging(extra) { _, neu in neu }
        app.launch()
        return app
    }

    /// Wischt von oberhalb der Bildmitte nach oben.
    ///
    /// Zwei Wege, die beide nicht taugen: `element.swipeUp()` wischt nur
    /// innerhalb des Rahmens des Elements - bei einer Beschriftung sind das
    /// dreissig Punkte, zu wenig zum Scrollen. Und `app.swipeUp()` setzt in
    /// der Bildmitte an, also mitten auf dem Diagramm, wo die Ziehgeste zum
    /// Werte-Ablesen liegt.
    func scrollDown(_ app: XCUIApplication, times: Int = 1) {
        for _ in 0..<times {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    /// Die Gegenrichtung - zurueck nach oben.
    ///
    /// Beginnt bei 0,30 und nicht weiter oben: darueber liegt die
    /// Navigationsleiste, und eine Ziehgeste, die dort ansetzt, scrollt
    /// nichts. Der Test sieht dann aus, als waere er unten haengengeblieben -
    /// war er auch.
    func scrollUp(_ app: XCUIApplication, times: Int = 1) {
        for _ in 0..<times {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    /// Legt einen Screenshot ab.
    ///
    /// `.keepAlways` ist der Punkt: die Vorgabe ist `.deleteOnSuccess`, und
    /// bei gruenen Testlaeufen wirft Xcode alles weg. Der Lauf meldet dann
    /// Erfolg und das Verzeichnis ist leer - der stillste aller stillen
    /// Fehler.
    func shoot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Wartet, bis eine Beschriftung wieder einen bestimmten Wert hat.
    func waitFor(_ element: XCUIElement, toReadAgain text: String) -> Bool {
        let predicate = NSPredicate(format: "label == %@", text)
        let erwartung = expectation(for: predicate, evaluatedWith: element)
        return XCTWaiter.wait(for: [erwartung], timeout: 10) == .completed
    }

    func waitFor(_ element: XCUIElement, toChangeFrom text: String) -> Bool {
        let predicate = NSPredicate(format: "label != %@", text)
        let erwartung = expectation(for: predicate, evaluatedWith: element)
        return XCTWaiter.wait(for: [erwartung], timeout: 10) == .completed
    }
}
