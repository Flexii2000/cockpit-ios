import XCTest
@testable import Healthy

/// Der Chat (Vertrag §8.2): was aus Fragen und Antworten an Blasen wird, wie
/// oft nachgefragt wird und wann der Knopf im Dashboard eine neue Antwort zeigt.
final class ChatTests: XCTestCase {

    private func exchange(_ id: String, _ status: ChatStatus, answer: String? = nil, error: String? = nil,
                          answeredAt: Date? = nil) -> ChatExchange {
        ChatExchange(id: id, question: "Frage \(id)", askedAt: Date(timeIntervalSince1970: 1_000),
                     status: status, answer: answer, answeredAt: answeredAt, error: error)
    }

    // MARK: - Blasen

    /// Je Frage die eigene Blase, darunter Antwort, Fortschritt oder Fehler.
    func testBubblesFollowTheStatus() {
        let bubbles = ChatTimeline.bubbles(exchanges: [
            exchange("a", .done, answer: "Antwort A"),
            exchange("b", .failed, error: "Die Anmeldung von Claude auf dem Server ist abgelaufen."),
            exchange("c", .running),
        ], sending: [])
        XCTAssertEqual(bubbles.map(\.kind), [
            .question, .answer,
            .question, .failed(.askAgain(question: "Frage b")),
            .question, .progress,
        ])
        XCTAssertEqual(bubbles[1].text, "Antwort A")
        XCTAssertEqual(bubbles[3].text, "Die Anmeldung von Claude auf dem Server ist abgelaufen.")
        XCTAssertEqual(Set(bubbles.map(\.id)).count, bubbles.count, "jede Blase hat ihre eigene Kennung")
    }

    /// Ein Status, den diese App noch nicht kennt, steht da wie „läuft noch“ -
    /// und eine gescheiterte Frage ohne Grund bekommt einen.
    func testUnknownStatusAndMissingReason() {
        let bubbles = ChatTimeline.bubbles(exchanges: [exchange("a", .unknown), exchange("b", .failed)],
                                           sending: [])
        XCTAssertEqual(bubbles[1].kind, .progress)
        XCTAssertFalse(bubbles[3].text.isEmpty)
    }

    /// Was unterwegs ist, steht am Ende; was nicht ankam, laesst sich mit
    /// derselben Kennung noch einmal schicken. Kennt der Dienst die Frage
    /// schon, zaehlt sein Stand.
    func testPendingSendsComeLastAndRetryWithTheSameID() {
        let failed = ChatPendingSend(id: "p2", text: "Nicht angekommen", failure: "Kein Netz.")
        let bubbles = ChatTimeline.bubbles(
            exchanges: [exchange("a", .done, answer: "Antwort A")],
            sending: [ChatPendingSend(id: "a", text: "doppelt"),
                      ChatPendingSend(id: "p1", text: "Unterwegs"), failed])
        XCTAssertEqual(bubbles.map(\.text), ["Frage a", "Antwort A", "Unterwegs", "", "Nicht angekommen", "Kein Netz."])
        XCTAssertEqual(bubbles[3].kind, .progress)
        XCTAssertEqual(bubbles[5].kind, .failed(.resend(failed)))
    }

    // MARK: - Abfragen

    /// 1,5 s in den ersten 30 Sekunden, dann alle 3 s, nach fuenf Minuten nicht mehr.
    func testPollDelay() {
        XCTAssertEqual(ChatTimeline.pollDelay(elapsed: 0), 1.5)
        XCTAssertEqual(ChatTimeline.pollDelay(elapsed: 29.9), 1.5)
        XCTAssertEqual(ChatTimeline.pollDelay(elapsed: 30), 3)
        XCTAssertEqual(ChatTimeline.pollDelay(elapsed: 299), 3)
        XCTAssertNil(ChatTimeline.pollDelay(elapsed: 300))
    }

    // MARK: - Ungesehen

    func testUnseenAnswer() {
        let early = Date(timeIntervalSince1970: 2_000)
        let late = Date(timeIntervalSince1970: 3_000)
        let exchanges = [exchange("a", .done, answer: "A", answeredAt: early),
                         exchange("b", .done, answer: "B", answeredAt: late),
                         exchange("c", .failed, error: "x", answeredAt: late.addingTimeInterval(60)),
                         exchange("d", .running)]
        XCTAssertEqual(ChatTimeline.latestAnswer(exchanges), late, "gescheiterte und laufende zaehlen nicht")
        XCTAssertTrue(ChatTimeline.hasUnseenAnswer(exchanges, seenThrough: nil))
        XCTAssertTrue(ChatTimeline.hasUnseenAnswer(exchanges, seenThrough: early))
        XCTAssertFalse(ChatTimeline.hasUnseenAnswer(exchanges, seenThrough: late))
        XCTAssertFalse(ChatTimeline.hasUnseenAnswer([exchange("d", .running)], seenThrough: nil))
        XCTAssertFalse(ChatTimeline.hasUnseenAnswer([], seenThrough: nil))
    }

    // MARK: - Senden

    func testQuestionIsTrimmedAndEmptyIsNothing() {
        XCTAssertEqual(ChatTimeline.question(from: "  Was nun? \n"), "Was nun?")
        XCTAssertNil(ChatTimeline.question(from: " \n "))
    }

    /// Der Dienst nimmt nur UUIDs in Kleinbuchstaben.
    func testNewIDIsALowercaseUUID() {
        let id = ChatTimeline.newID()
        XCTAssertNotNil(UUID(uuidString: id))
        XCTAssertEqual(id, id.lowercased())
        XCTAssertNotEqual(id, ChatTimeline.newID())
    }

    /// Was der Dienst ablehnt, geht mit einem Satz zurueck ins Feld; alles
    /// andere (kein Netz) laesst die Blase stehen.
    func testRejections() {
        XCTAssertEqual(ChatTimeline.rejection(APIError.http(409, "egal")), "Eine Antwort läuft noch.")
        XCTAssertEqual(ChatTimeline.rejection(APIError.http(429, "Für heute sind die 30 Fragen aufgebraucht.")),
                       "Für heute sind die 30 Fragen aufgebraucht.")
        XCTAssertNotNil(ChatTimeline.rejection(APIError.http(429, nil)))
        XCTAssertEqual(ChatTimeline.rejection(APIError.http(503, nil)), "Claude ist gerade nicht erreichbar.")
        XCTAssertEqual(ChatTimeline.rejection(APIError.http(400, "Höchstens 1000 Zeichen.")), "Höchstens 1000 Zeichen.")
        XCTAssertNotNil(ChatTimeline.rejection(APIError.notAuthorised))
        XCTAssertNil(ChatTimeline.rejection(APIError.offline))
        XCTAssertNil(ChatTimeline.rejection(APIError.http(500, nil)))
        XCTAssertEqual(ChatTimeline.failure(APIError.offline), "Kein Netz.")
        XCTAssertEqual(ChatTimeline.failure(APIError.http(500, nil)), "Nicht gesendet.")
    }
}
