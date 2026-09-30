import Foundation
@testable import coHabit

/// Ein Dienst im Speicher: `URLProtocol` faengt jede Anfrage der Test-Session
/// ab. Kein Netz in Tests (CLAUDE.md) - und so laesst sich auch „kein Netz"
/// nachstellen.
final class StubServer: URLProtocol, @unchecked Sendable {

    struct Recorded: Sendable {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data
    }

    enum Reply: Sendable {
        case json(Int, String)
        case offline
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (Recorded) -> Reply)?
    nonisolated(unsafe) private static var recorded: [Recorded] = []

    static func install(_ handler: @escaping @Sendable (Recorded) -> Reply) {
        lock.lock()
        defer { lock.unlock() }
        self.handler = handler
        recorded = []
    }

    static var requests: [Recorded] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// Eine Session, deren Anfragen hier landen.
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        return URLSession(configuration: configuration)
    }

    static func api(token: String? = "test-token", usesCache: Bool = false) -> CohabitAPI {
        CohabitAPI(token: token, baseURL: URL(string: "https://stub.test/cohabit/api")!,
                   timeout: 5, session: session(), usesCache: usesCache)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            // URLSession reicht den Rumpf als Strom weiter, nicht als Daten.
            stream.open()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: 4096)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
            buffer.deallocate()
            stream.close()
        }
        let recordedRequest = Recorded(method: request.httpMethod ?? "GET", url: request.url!,
                                       headers: request.allHTTPHeaderFields ?? [:], body: body)
        Self.lock.lock()
        Self.recorded.append(recordedRequest)
        let handler = Self.handler
        Self.lock.unlock()

        switch handler?(recordedRequest) ?? .json(404, #"{"message":"unbekannt"}"#) {
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .json(let status, let json):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

extension StubServer.Recorded {
    var path: String { url.path() }

    var json: [String: Any]? {
        try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }
}
