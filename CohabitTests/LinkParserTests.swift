import XCTest
@testable import coHabit

/// „Link einfügen" (Vertrag §5.4) und die Deep Links (§4).
final class LinkParserTests: XCTestCase {

    private func parse(_ text: String) -> DeepLink? {
        URL(string: text).flatMap(LinkParser.parse)
    }

    func testAppLinksFromTheContract() {
        XCTAssertEqual(parse("cohabit://today"), .today)
        XCTAssertEqual(parse("cohabit://timeline"), .timeline)
        XCTAssertEqual(parse("cohabit://new"), .new)
        XCTAssertEqual(parse("cohabit://stats"), .stats)
        XCTAssertEqual(parse("cohabit://profile"), .profile)
        XCTAssertEqual(parse("cohabit://friends"), .friends)
        XCTAssertEqual(parse("cohabit://cohabit/c-3f2a"), .cohabit("c-3f2a"))
        XCTAssertEqual(parse("cohabit://cohabit/c-3f2a/chat"), .chat("c-3f2a"))
        XCTAssertEqual(parse("cohabit://cohabit/c-3f2a/checkin"), .checkIn("c-3f2a"))
        XCTAssertEqual(parse("cohabit://invitation/i-1"), .invitation("i-1"))
        XCTAssertEqual(parse("cohabit://join/AbCdEfGhIjKlMnOpQrStUv"), .join("AbCdEfGhIjKlMnOpQrStUv"))
        XCTAssertEqual(parse("cohabit://setup?token=abc123"), .setup(token: "abc123"))
        XCTAssertNil(parse("cohabit://cohabit"))
        XCTAssertNil(parse("cohabit://unknown"))
    }

    func testSetupAndInviteLinks() {
        let token = String(repeating: "a1", count: 24)
        XCTAssertEqual(parse("https://fherrmann.com/cohabit/setup?token=\(token)"), .setup(token: token))
        XCTAssertEqual(parse("https://food.fherrmann.com/setup?token=xyz"), .healthySetup(token: "xyz"))
        XCTAssertEqual(parse("https://fherrmann.com/cohabit/join/Code22Characters123456"), .join("Code22Characters123456"))
        XCTAssertNil(parse("https://fherrmann.com/cohabit/setup"), "ohne Token kein Zugang")
        XCTAssertNil(parse("https://food.fherrmann.com/api/food/day"))
        XCTAssertNil(parse("https://example.com/whatever"))
        // Ein lokal gestarteter Dienst stellt Links auf seine eigene Adresse aus.
        XCTAssertEqual(parse("http://127.0.0.1:48792/cohabit/setup?token=t"), .setup(token: "t"))
        XCTAssertEqual(DeepLink.setup(token: "t").token, "t")
        XCTAssertNil(DeepLink.join("x").token)
    }

    func testWebCounterparts() {
        XCTAssertEqual(parse("https://fherrmann.com/cohabit/"), .today)
        XCTAssertEqual(parse("https://fherrmann.com/cohabit/timeline"), .timeline)
        XCTAssertEqual(parse("https://fherrmann.com/cohabit/neu"), .new)
        XCTAssertEqual(parse("https://fherrmann.com/cohabit/statistik"), .stats)
        XCTAssertEqual(parse("https://fherrmann.com/cohabit/profil"), .profile)
        XCTAssertEqual(parse("https://fherrmann.com/cohabit/freunde"), .friends)
        XCTAssertEqual(parse("https://fherrmann.com/cohabit/c/c-1"), .cohabit("c-1"))
        XCTAssertEqual(parse("https://fherrmann.com/cohabit/c/c-1/chat"), .chat("c-1"))
    }

    func testFindsTheLinkInsideCopiedText() {
        XCTAssertEqual(LinkParser.find(in: "Hier ist dein Link: https://fherrmann.com/cohabit/setup?token=abc. Viel Spaß!"),
                       .setup(token: "abc"))
        XCTAssertEqual(LinkParser.find(in: "Mach mit!\n„https://fherrmann.com/cohabit/join/XYZ“"), .join("XYZ"))
        XCTAssertEqual(LinkParser.find(in: "(cohabit://cohabit/c-9/chat)"), .chat("c-9"))
        XCTAssertEqual(LinkParser.find(in: "fherrmann.com/cohabit/join/ohneSchema"), .join("ohneSchema"),
                       "manche Messenger kuerzen das https weg")
        XCTAssertEqual(LinkParser.find(in: "  https://food.fherrmann.com/setup?token=t0k  "), .healthySetup(token: "t0k"))
        XCTAssertNil(LinkParser.find(in: "kein Link hier"))
        XCTAssertNil(LinkParser.find(in: ""))
    }

    func testUsernameRules() {
        XCTAssertTrue(JoinView.isValidUsername("lena.k"))
        XCTAssertTrue(JoinView.isValidUsername("sara_a"))
        XCTAssertFalse(JoinView.isValidUsername("ab"), "mindestens drei Zeichen")
        XCTAssertFalse(JoinView.isValidUsername("1lena"), "beginnt mit einem Buchstaben")
        XCTAssertFalse(JoinView.isValidUsername("Lena"), "nur Kleinbuchstaben")
        XCTAssertFalse(JoinView.isValidUsername("lena-k"))
        XCTAssertFalse(JoinView.isValidUsername(String(repeating: "a", count: 21)))
    }
}
