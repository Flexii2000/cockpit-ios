import Foundation

/// Eine diktierte Frage an den persönlichen Assistenten auf dem Heimserver
/// (Repo `assistant`, Channel „diktat“ in der dauerhaft laufenden Claude-Sitzung).
///
/// Kein Teil von `Backend`: der Assistent ist kein Tab, nur das Ziel des Action
/// Buttons. nginx prüft den `fh_private`-Cookie; der Server nimmt die Frage mit
/// 202 an, die Antwort entsteht in der Sitzung und wird hier abgefragt. Kein
/// langer Request — der Weg über VPS und WireGuard verträgt keine 60 s.
///
/// Wartet höchstens `patience` Sekunden. Was länger dauert, schickt der
/// Assistent nach Telegram, wo Frage und Antwort ohnehin mitlaufen.
struct AssistantAsk: Sendable {

    struct Reply: Decodable, Sendable, Equatable {
        let id: String
        let status: String
        let answer: String?

        var finishedAnswer: String? { status == "done" ? answer : nil }
    }

    enum Failure: LocalizedError, Equatable {
        case noAccess
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .noAccess: "Kein Zugang zum Assistenten – fh_private in Fokus einrichten."
            case .http(let code): "Der Assistent hat mit \(code) geantwortet."
            }
        }
    }

    enum Outcome: Equatable, Sendable {
        case answered(String)
        case stillRunning
    }

    static let stillRunningText = "Läuft noch – die Antwort kommt in Telegram."

    /// Die beiden Aufrufe und das Warten — austauschbar, damit die Schleife ohne
    /// Netz testbar ist (Tests dürfen die privaten Dienste nicht erreichen).
    var post: @Sendable (_ id: String, _ text: String) async throws -> Reply
    var poll: @Sendable (_ id: String) async throws -> Reply
    var sleep: @Sendable (_ seconds: Double) async throws -> Void = { seconds in
        try await Task.sleep(for: .seconds(seconds))
    }
    var patience: Double = 20
    var interval: Double = 1.5

    /// Die ID vergibt das iPhone: schickt es dieselbe Frage zweimal (Netz weg und
    /// wieder da), legt der Server keinen zweiten Auftrag an.
    func run(_ text: String, id: String = UUID().uuidString.lowercased()) async throws -> Outcome {
        if let answer = try await post(id, text).finishedAnswer {
            return .answered(answer)
        }
        var waited = 0.0
        while waited < patience {
            try await sleep(interval)
            waited += interval
            if let answer = try await poll(id).finishedAnswer {
                return .answered(answer)
            }
        }
        return .stillRunning
    }
}

extension AssistantAsk {

    static let endpoint = URL(string: "https://fherrmann.com/assistant/api/ask")!

    /// Der echte Weg. Der Cookie wird ausdrücklich gesetzt: der Intent läuft,
    /// ohne dass die App geöffnet war — `Access.applyCookies()` ist dann
    /// womöglich nie gelaufen.
    static func live(token: String, session: URLSession = .shared) -> AssistantAsk {
        AssistantAsk(
            post: { id, text in
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(["id": id, "text": text])
                return try await send(request, token: token, session: session)
            },
            poll: { id in
                try await send(URLRequest(url: endpoint.appending(path: id)), token: token, session: session)
            })
    }

    private static func send(_ request: URLRequest, token: String, session: URLSession) async throws -> Reply {
        var request = request
        request.timeoutInterval = 15
        request.httpShouldHandleCookies = false
        request.setValue("fh_private=\(token)", forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            return try JSONDecoder().decode(Reply.self, from: data)
        case 302, 401, 403:
            throw Failure.noAccess
        default:
            throw Failure.http(status)
        }
    }
}
