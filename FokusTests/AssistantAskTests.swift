import XCTest
@testable import Fokus

/// Die Abfrage-Schleife hinter dem Action Button (`AssistantAsk.run`) — ohne
/// Netz: Server und Warten sind ersetzt.
final class AssistantAskTests: XCTestCase {

    /// Zählt Aufrufe und spielt vorgegebene Antworten ab.
    private final class FakeServer: @unchecked Sendable {
        private let lock = NSLock()
        private var pollReplies: [AssistantAsk.Reply]
        private(set) var postCount = 0
        private(set) var pollCount = 0
        private(set) var slept = 0.0
        private(set) var seenIds: [String] = []
        let postReply: AssistantAsk.Reply

        init(post: AssistantAsk.Reply, polls: [AssistantAsk.Reply]) {
            postReply = post
            pollReplies = polls
        }

        var client: AssistantAsk {
            AssistantAsk(
                post: { id, _ in
                    self.lock.withLock {
                        self.postCount += 1
                        self.seenIds.append(id)
                        return self.postReply
                    }
                },
                poll: { id in
                    self.lock.withLock {
                        self.pollCount += 1
                        self.seenIds.append(id)
                        return self.pollReplies.isEmpty ? AssistantAskTests.running : self.pollReplies.removeFirst()
                    }
                },
                sleep: { seconds in self.lock.withLock { self.slept += seconds } })
        }
    }

    private static let id = "abcd-1234"
    private static let running = AssistantAsk.Reply(id: id, status: "running", answer: nil)
    private static func done(_ answer: String) -> AssistantAsk.Reply {
        AssistantAsk.Reply(id: id, status: "done", answer: answer)
    }

    func testReturnsTheAnswerOnceItIsDone() async throws {
        let server = FakeServer(post: Self.running, polls: [Self.running, Self.done("Antwort A")])
        let outcome = try await server.client.run("Frage A", id: Self.id)
        XCTAssertEqual(outcome, .answered("Antwort A"))
        XCTAssertEqual(server.postCount, 1)
        XCTAssertEqual(server.pollCount, 2)
        XCTAssertEqual(server.seenIds, [Self.id, Self.id, Self.id], "immer dieselbe ID")
    }

    func testAnswerAlreadyInThePostReplySkipsPolling() async throws {
        let server = FakeServer(post: Self.done("Antwort A"), polls: [])
        let outcome = try await server.client.run("Frage A", id: Self.id)
        XCTAssertEqual(outcome, .answered("Antwort A"))
        XCTAssertEqual(server.pollCount, 0)
    }

    func testGivesUpAfterPatienceAndPointsToTelegram() async throws {
        let server = FakeServer(post: Self.running, polls: [])
        var client = server.client
        client.patience = 20
        client.interval = 1.5
        let outcome = try await client.run("Frage A", id: Self.id)
        XCTAssertEqual(outcome, .stillRunning)
        XCTAssertEqual(server.pollCount, 14, "0 … 19,5 s in Schritten von 1,5 s")
        XCTAssertEqual(server.slept, 21, accuracy: 0.001)
    }

    func testAnAnswerWithoutDoneStatusIsNotFinal() async throws {
        let half = AssistantAsk.Reply(id: Self.id, status: "running", answer: "Zwischenstand")
        let server = FakeServer(post: half, polls: [Self.done("Antwort A")])
        let outcome = try await server.client.run("Frage A", id: Self.id)
        XCTAssertEqual(outcome, .answered("Antwort A"))
    }

    func testAccessErrorsReachTheCaller() async {
        let client = AssistantAsk(
            post: { _, _ in throw AssistantAsk.Failure.noAccess },
            poll: { _ in Self.running },
            sleep: { _ in })
        do {
            _ = try await client.run("Frage A", id: Self.id)
            XCTFail("Ohne Zugang darf keine Antwort kommen")
        } catch {
            XCTAssertEqual(error as? AssistantAsk.Failure, .noAccess)
        }
    }

    func testDefaultIdsFitTheServersPattern() {
        let id = UUID().uuidString.lowercased()
        XCTAssertNotNil(id.range(of: "^[A-Za-z0-9-]{8,64}$", options: .regularExpression))
    }
}
