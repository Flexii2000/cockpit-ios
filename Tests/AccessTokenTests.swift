import XCTest
@testable import Healthy

/// Der persoenliche Healthy-Token aus dem, was jemand einfuegt - dieselben
/// Faelle wie in der Android-App (`AccessTokenTest.kt`). Der Token hier ist
/// erfunden.
final class AccessTokenTests: XCTestCase {

    private let token = "0123456789abcdef0123456789abcdef0123456789abcdef"

    func testAcceptsTheBareToken() {
        XCTAssertEqual(AccessToken.extract(token), token)
        XCTAssertEqual(AccessToken.extract("  \(token)\n"), token)
    }

    func testTakesTheTokenOutOfASetupLink() {
        XCTAssertEqual(AccessToken.extract("https://food.fherrmann.com/setup?token=\(token)"), token)
        XCTAssertEqual(AccessToken.extract("https://weight.fherrmann.com/setup?foo=1&token=\(token)#x"), token)
    }

    /// Die ganze Nachricht kopiert - der Link darin zaehlt.
    func testFindsTheLinkInsideASentence() {
        XCTAssertEqual(
            AccessToken.extract("Hier dein Zugang: https://food.fherrmann.com/setup?token=\(token) viel Spaß"),
            token)
    }

    func testDecodesPercentEscapes() {
        XCTAssertEqual(AccessToken.extract("https://food.fherrmann.com/setup?token=ab%2Dcd"), "ab-cd")
    }

    func testRejectsWhatIsNoToken() {
        XCTAssertNil(AccessToken.extract(""))
        XCTAssertNil(AccessToken.extract("   "))
        XCTAssertNil(AccessToken.extract("https://food.fherrmann.com/"))
        XCTAssertNil(AccessToken.extract("irgendein Satz ohne Link"))
        XCTAssertNil(AccessToken.extract("https://food.fherrmann.com/setup?token="))
    }
}

/// Welcher Cookie in Kacheln und auf der Uhr gilt.
final class HealthCookieTests: XCTestCase {

    /// Der persoenliche Token schlaegt Felix' Privat-Token - wie beim Dienst.
    func testThePersonalTokenWins() {
        XCTAssertEqual(HealthCookie.header(health: "person", owner: "felix"), "health_token=person")
    }

    func testWithoutAPersonalTokenItIsTheOwnerCookie() {
        XCTAssertEqual(HealthCookie.header(health: nil, owner: "felix"), "fh_private=felix")
        XCTAssertEqual(HealthCookie.header(health: "", owner: "felix"), "fh_private=felix")
    }

    func testWithoutAnyTokenThereIsNoCookie() {
        XCTAssertNil(HealthCookie.header(health: nil, owner: nil))
        XCTAssertNil(HealthCookie.header(health: "", owner: ""))
    }
}

/// Die Pruefung eines persoenlichen Tokens gegen beide Dienste - die Regel,
/// ohne Netz.
final class HealthAccessCheckTests: XCTestCase {

    private let features = Data(#"{"quickCapture":true,"me":"person-a"}"#.utf8)

    func testBothServicesMustAccept() {
        XCTAssertEqual(
            HealthAccessCheck.outcome(token: "t", food: .accepted(features), weight: .accepted(Data("{}".utf8))),
            .valid(token: "t", name: "person-a"))
    }

    /// Ein Token, der nur die Haelfte der App oeffnet, gilt nicht.
    func testOneRefusalIsEnough() {
        XCTAssertEqual(
            HealthAccessCheck.outcome(token: "t", food: .accepted(features), weight: .denied),
            .invalid("Gewicht: Kein Zugang – Token prüfen."))
        XCTAssertEqual(
            HealthAccessCheck.outcome(token: "t", food: .denied, weight: .accepted(Data())),
            .invalid("Essen: Kein Zugang – Token prüfen."))
    }

    func testOfflineAndServerErrorsAreNamed() {
        XCTAssertEqual(HealthAccessCheck.outcome(token: "t", food: .offline, weight: .offline),
                       .invalid("Kein Netz."))
        XCTAssertEqual(HealthAccessCheck.outcome(token: "t", food: .accepted(features), weight: .failed(502)),
                       .invalid("Gewicht: Der Dienst hat mit 502 geantwortet."))
    }

    /// Ein aelterer Dienst nennt keinen Namen - der Token gilt trotzdem.
    func testTheNameIsOptional() {
        let old = Data(#"{"quickCapture":false}"#.utf8)
        XCTAssertEqual(HealthAccessCheck.outcome(token: "t", food: .accepted(old), weight: .accepted(Data())),
                       .valid(token: "t", name: nil))
        XCTAssertNil(HealthAccessCheck.name(from: Data(#"{"me":"  "}"#.utf8)))
    }

    /// Fehlender Zugang sieht bei diesen Diensten nicht aus wie 401: 403 mit
    /// HTML, oder eine Anmeldeseite mit 200 nach der Weiterleitung.
    func testClassifiesWhatTheServicesAnswer() {
        let body = Data("{}".utf8)
        XCTAssertEqual(HealthAccessCheck.classify(status: 200, contentType: "application/json", body: body),
                       .accepted(body))
        XCTAssertEqual(HealthAccessCheck.classify(status: 200, contentType: "text/html; charset=utf-8", body: body),
                       .denied)
        XCTAssertEqual(HealthAccessCheck.classify(status: 200, contentType: nil, body: body), .denied)
        XCTAssertEqual(HealthAccessCheck.classify(status: 403, contentType: "text/html", body: body), .denied)
        XCTAssertEqual(HealthAccessCheck.classify(status: 302, contentType: nil, body: body), .denied)
        XCTAssertEqual(HealthAccessCheck.classify(status: 500, contentType: "application/json", body: body),
                       .failed(500))
    }
}

/// Was das Zugang-Blatt von Healthy zeigt, und wie der Health-Abgleich seine
/// Merker je Person trennt.
final class HealthySetupTests: XCTestCase {

    func testWithAPersonalTokenOnlyItsField() {
        let choice = HealthySetup.sections(health: true, owner: true)
        XCTAssertEqual(choice.shown, [.healthToken])
        XCTAssertTrue(choice.collapsed.isEmpty)
    }

    /// Felix' iPhone: genau das Blatt von vorher.
    func testWithOwnerTokensTheSheetIsAsBefore() {
        let choice = HealthySetup.sections(health: false, owner: true)
        XCTAssertEqual(choice.shown, [.privateToken, .weightToken])
        XCTAssertTrue(choice.collapsed.isEmpty)
    }

    /// Ein frisches iPhone: der persoenliche Token zuerst, Felix' Token zugeklappt.
    func testAFreshPhoneAsksForThePersonalToken() {
        let choice = HealthySetup.sections(health: false, owner: false)
        XCTAssertEqual(choice.shown, [.healthToken])
        XCTAssertEqual(choice.collapsed, [.privateToken, .weightToken])
    }

    func testTheHeaderNamesThePerson() {
        XCTAssertNil(SetupView.healthHeader(hasToken: false, name: nil))
        XCTAssertEqual(SetupView.healthHeader(hasToken: true, name: nil), "✓")
        XCTAssertEqual(SetupView.healthHeader(hasToken: true, name: "person-a"), "✓ Person-a")
        XCTAssertNil(SetupView.healthHeader(hasToken: false, name: "person-a"))
    }

    /// Ohne Zugang kein Abgleich: auf einem frischen iPhone soll der
    /// Health-Dialog nicht ueber dem Zugang-Blatt liegen.
    func testSyncNeedsAnAccess() {
        XCTAssertFalse(HealthSyncScope.hasAccess(healthToken: nil, weightToken: nil))
        XCTAssertFalse(HealthSyncScope.hasAccess(healthToken: "", weightToken: ""))
        XCTAssertTrue(HealthSyncScope.hasAccess(healthToken: "person", weightToken: nil))
        XCTAssertTrue(HealthSyncScope.hasAccess(healthToken: nil, weightToken: "felix"))
    }

    /// Felix' Schluessel bleiben, wie sie waren; eine Person bekommt eigene.
    func testSyncKeysAreScopedPerPerson() {
        XCTAssertEqual(HealthSyncScope.suffix(healthToken: nil), "")
        XCTAssertEqual(HealthSyncScope.suffix(healthToken: ""), "")
        let a = HealthSyncScope.suffix(healthToken: "token-a")
        let b = HealthSyncScope.suffix(healthToken: "token-b")
        XCTAssertEqual(a.count, 9)
        XCTAssertTrue(a.hasPrefix("."))
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, HealthSyncScope.suffix(healthToken: "token-a"))
        // Der Token selbst steht nicht im Schluessel.
        XCTAssertFalse(a.contains("token"))
    }
}
