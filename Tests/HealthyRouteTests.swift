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

    /// Die Evaluation wohnt seit 14.10. in Fokus - eine alte Erinnerung, die
    /// noch in Healthy angetippt wird, fuehrt nirgends hin.
    func testEvaluationReminderNoLongerOpensAnything() {
        XCTAssertNil(HealthyRoute.notification(kind: "evaluation"))
    }

    /// Die Erinnerung um 09:00 fuehrt ins Dashboard und dort aufs Logbook.
    func testLogbookReminderOpensTheLogbook() {
        XCTAssertEqual(HealthyRoute.notification(kind: "logbook"), .logbook)
    }

    /// Die Arten des Weight Trackers (Vertrag §11.5): die Antwort im Chat
    /// oeffnet den Chat, Stupser und Serien-Warnung die Freunde.
    func testChatAndFriendsKinds() {
        XCTAssertEqual(HealthyRoute.notification(kind: "chat-answer"), .chat)
        XCTAssertEqual(HealthyRoute.notification(kind: "friend-nudge"), .friends)
        XCTAssertEqual(HealthyRoute.notification(kind: "streak-warning"), .friends)
        XCTAssertNil(HealthyRoute.notification(kind: "briefing"), "fuers Briefing gibt es keine Push")
    }

    /// `healthy://friends` und `healthy://chat`.
    func testLinksToFriendsAndChat() throws {
        XCTAssertEqual(HealthyRoute.url(try XCTUnwrap(URL(string: "healthy://friends"))), .friends)
        XCTAssertEqual(HealthyRoute.url(try XCTUnwrap(URL(string: "healthy://chat"))), .chat)
    }

    /// Die Freunde sind ein Tab; der Chat ist ein Blatt ueber dem Dashboard -
    /// die Bitte wird gezaehlt, damit sie auch beim zweiten Mal wirkt.
    @MainActor
    func testRouterOpensFriendsAndCountsChatRequests() {
        let router = Router.shared
        let before = (router.selection, router.dashboardPath)
        addTeardownBlock { @MainActor in
            router.selection = before.0
            router.dashboardPath = before.1
        }
        router.follow(.friends)
        XCTAssertEqual(router.selection, .friends)

        router.open(.recovery)
        let requests = router.chatRequests
        router.follow(.chat)
        XCTAssertEqual(router.selection, .dashboard)
        XCTAssertEqual(router.dashboardPath, [], "der Chat liegt ueber dem Dashboard, nicht ueber der Recovery")
        XCTAssertEqual(router.chatRequests, requests + 1)
        router.follow(.chat)
        XCTAssertEqual(router.chatRequests, requests + 2)
        // Das Dashboard bedient die Bitte genau einmal - auch wenn es sie erst
        // beim Erscheinen sieht (Kaltstart).
        XCTAssertTrue(router.takeChatRequest())
        XCTAssertFalse(router.takeChatRequest())
        router.follow(.chat)
        XCTAssertTrue(router.takeChatRequest())
    }

    /// Fuehrt ein Weg anderswohin als in den Chat, schliesst das Dashboard sein
    /// Blatt (Chat, Strain-Fenster) - es laege sonst ueber dem Ziel. Der Weg in
    /// den Chat laesst es offen.
    @MainActor
    func testRoutesElsewhereCloseTheDashboardSheets() {
        let router = Router.shared
        let before = (router.selection, router.dashboardPath)
        addTeardownBlock { @MainActor in
            router.selection = before.0
            router.dashboardPath = before.1
            _ = router.takeChatRequest()
        }
        var dismissals = router.dashboardSheetDismissals
        for route in [HealthyRoute.friends, .logbook, .food, .foodToday, .dashboard] {
            router.follow(route)
            dismissals += 1
            XCTAssertEqual(router.dashboardSheetDismissals, dismissals, "\(route)")
        }
        router.follow(.chat)
        XCTAssertEqual(router.dashboardSheetDismissals, dismissals)
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
        XCTAssertEqual(HealthyRoute.url(try XCTUnwrap(URL(string: "healthy://dashboard"))), .dashboard)
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

        router.open(.recovery)
        XCTAssertEqual(router.selection, .dashboard)
        XCTAssertEqual(router.dashboardPath, [.recovery])

        router.show(.food)
        let logbookRequests = router.logbookRequests
        router.follow(.logbook)
        XCTAssertEqual(router.selection, .dashboard)
        XCTAssertEqual(router.dashboardPath, [], "das Logbook steht im Dashboard selbst, nicht unter der Recovery")
        XCTAssertEqual(router.logbookRequests, logbookRequests + 1, "das Dashboard scrollt dorthin")
    }
}
