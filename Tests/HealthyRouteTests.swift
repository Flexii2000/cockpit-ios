import XCTest
@testable import Healthy

/// Wohin ein Tipp fuehrt. Seit die App im Dashboard aufmacht, landet nichts
/// mehr von selbst im Essen-Tab - die Schnellerfassung haengt an dieser Weiche.
final class HealthyRouteTests: XCTestCase {

    /// Die APNs-Meldung des Kalorienzaehlers hat keine Art - sie muss trotzdem
    /// im Essen-Tab landen, ebenso die lokale „Vorschlag ist fertig".
    func testWithoutKindOrQuickCaptureItIsFood() {
        XCTAssertEqual(HealthyRoute.notification(kind: nil), .food)
        XCTAssertEqual(HealthyRoute.notification(kind: "quick-capture"), .food)
        XCTAssertEqual(HealthyRoute.notification(kind: HealthyRoute.quickCaptureKind), .food)
    }

    func testEvaluationReminderOpensItsTab() {
        XCTAssertEqual(HealthyRoute.notification(kind: "evaluation"), .evaluation)
        XCTAssertEqual(HealthyRoute.notification(kind: EvaluationReminder.kind), .evaluation)
    }

    /// Die Erinnerung um 09:00 fuehrt ins Dashboard und dort aufs Logbook.
    func testLogbookReminderOpensTheLogbook() {
        XCTAssertEqual(HealthyRoute.notification(kind: "logbook"), .logbook)
    }

    /// Eine unbekannte Art fuehrt nirgends hin, statt zu raten.
    func testUnknownKindGoesNowhere() {
        XCTAssertNil(HealthyRoute.notification(kind: "grade"))
        XCTAssertNil(HealthyRoute.notification(kind: ""))
    }

    /// Die Kalorien-Kachel: `healthy://food` ist Essen mit heute.
    func testWidgetLinkOpensFoodToday() throws {
        XCTAssertEqual(HealthyRoute.url(try XCTUnwrap(URL(string: "healthy://food"))), .foodToday)
        XCTAssertEqual(HealthyRoute.url(try XCTUnwrap(URL(string: "HEALTHY://Food"))), .foodToday)
        XCTAssertNil(HealthyRoute.url(try XCTUnwrap(URL(string: "healthy://weight"))))
        XCTAssertNil(HealthyRoute.url(try XCTUnwrap(URL(string: "https://food.fherrmann.com"))))
        XCTAssertNil(HealthyRoute.url(try XCTUnwrap(URL(string: "cohabit://food"))))
    }

    /// Die Weiche selbst: Essen mit heute zaehlt die Bitte hoch, auch wenn der
    /// Tab schon offen war.
    @MainActor
    func testRouterFollowsRoutes() {
        let router = Router.shared
        let before = (router.selection, router.dashboardPath)
        addTeardownBlock { @MainActor in
            router.selection = before.0
            router.dashboardPath = before.1
        }
        let requests = router.foodTodayRequests
        router.follow(.foodToday)
        XCTAssertEqual(router.selection, .food)
        XCTAssertEqual(router.foodTodayRequests, requests + 1)
        router.follow(.foodToday)
        XCTAssertEqual(router.foodTodayRequests, requests + 2)

        router.follow(.evaluation)
        XCTAssertEqual(router.selection, .evaluation)
        router.open(.recovery)
        XCTAssertEqual(router.selection, .dashboard)
        XCTAssertEqual(router.dashboardPath, [.recovery])

        router.show(.food)
        router.follow(.logbook)
        XCTAssertEqual(router.selection, .dashboard)
        XCTAssertEqual(router.dashboardPath, [.logbook], "frisch oben, nicht auf die Recovery gestapelt")
    }
}
