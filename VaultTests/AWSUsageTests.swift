import XCTest
@testable import Vault

/// Der AWS-Tab und die Menüleisten-App lesen denselben Stand (`AWSUsageShared`):
/// Vertrag `../aws-usage/docs/API.md`. Kein Netz - der Client läuft gegen einen
/// Stub-`URLProtocol`.
final class AWSUsageTests: XCTestCase {

    private let nbsp = "\u{00A0}"

    /// Das Beispiel aus API.md, dazu eine zweite Instanz ohne Preis (Vertrag vom
    /// 01.11.: `pricePerHour` kann `null` sein) und Nanosekunden am Zeitpunkt.
    static let example = Data("""
    {
      "currency": "USD",
      "month": "2026-11",
      "budget": { "name": "30€ pro Monat", "limit": 50.0 },
      "spent": 19.01,
      "billed": 17.20,
      "live": 1.81,
      "percent": 38.0,
      "forecast": 37.31,
      "categories": [
        { "key": "llm", "name": "LLM", "amount": 8.10, "live": 1.81,
          "items": [
            { "label": "EC2-Rechenzeit", "amount": 6.29, "live": false },
            { "label": "Läuft: Spot g7e.2xlarge", "amount": 1.81, "live": true }
          ] },
        { "key": "hytale",  "name": "Hytale",    "amount": 6.40, "live": 0.0, "items": [] },
        { "key": "hosting", "name": "Hosting",   "amount": 4.12, "live": 0.0, "items": [] },
        { "key": "other",   "name": "Sonstiges", "amount": 0.39, "live": 0.0, "items": [] }
      ],
      "running": [
        { "id": "i-0562fb060733c92b9", "name": "llm-ondemand", "category": "llm",
          "region": "eu-west-2", "type": "g7e.2xlarge", "lifecycle": "spot",
          "pricePerHour": 1.86, "launchedAt": "2026-11-01T14:02:00Z", "estimate": 1.81 },
        { "id": "i-0b39f02135d3a738c", "name": "flexiisgoggles-test", "category": "hytale",
          "region": "eu-central-1", "type": "m7i.xlarge", "lifecycle": "on-demand",
          "pricePerHour": null, "launchedAt": "2026-11-01T15:00:00.123456789Z", "estimate": 0.0 }
      ],
      "months": [
        { "month": "2026-10", "total": 37.10,
          "categories": { "llm": 0.0, "hytale": 22.79, "hosting": 9.79, "other": 0.54 } }
      ],
      "billedAt": "2026-11-01T15:00:00Z",
      "liveAt": "2026-11-01T16:05:00Z",
      "problem": null
    }
    """.utf8)

    private func usage() throws -> AWSUsage {
        try AWSUsageCoding.decoder().decode(AWSUsage.self, from: Self.example)
    }

    // MARK: - Lesen

    func testTheContractExampleReads() throws {
        let usage = try usage()
        XCTAssertEqual(usage.budget?.limit, 50)
        XCTAssertEqual(usage.percent, 38)
        XCTAssertEqual(usage.categories.map(\.key), ["llm", "hytale", "hosting", "other"])
        XCTAssertEqual(usage.categories[0].items.last?.live, true)
        XCTAssertEqual(usage.running.count, 2)
        XCTAssertEqual(usage.running[0].pricePerHour, 1.86)
        XCTAssertNil(usage.running[1].pricePerHour, "ohne Preis bleibt die Instanz lesbar")
        XCTAssertFalse(usage.running[1].isSpot)
        XCTAssertNotNil(usage.running[1].launchedAt, "Nanosekunden wie bei Spring")
        XCTAssertEqual(usage.months.first?.month, "2026-10")
        XCTAssertNil(usage.problem)
    }

    func testPercentAndForecastMayBeMissing() throws {
        var json = String(decoding: Self.example, as: UTF8.self)
        json = json.replacingOccurrences(of: "\"percent\": 38.0", with: "\"percent\": null")
            .replacingOccurrences(of: "\"forecast\": 37.31", with: "\"forecast\": null")
        let usage = try AWSUsageCoding.decoder().decode(AWSUsage.self, from: Data(json.utf8))
        XCTAssertNil(usage.percent)
        XCTAssertNil(usage.forecast)
        XCTAssertEqual(AWSUsageFormat.menuBarTitle(usage), "19,01\(nbsp)$", "ohne Prozent nur der Betrag")
    }

    // MARK: - Schreibweise

    func testDollars() {
        XCTAssertEqual(AWSUsageFormat.dollars(19.01), "19,01\(nbsp)$")
        XCTAssertEqual(AWSUsageFormat.dollars(1234.5), "1.234,50\(nbsp)$")
        XCTAssertEqual(AWSUsageFormat.dollars(0), "0,00\(nbsp)$")
        XCTAssertEqual(AWSUsageFormat.limit(50), "50\(nbsp)$")
        XCTAssertEqual(AWSUsageFormat.limit(62.5), "62,50\(nbsp)$")
    }

    func testPricePerHourKeepsUpToFourDecimals() {
        XCTAssertEqual(AWSUsageFormat.perHour(0.2394), "0,2394\(nbsp)$/h")
        XCTAssertEqual(AWSUsageFormat.perHour(1.86), "1,86\(nbsp)$/h")
        XCTAssertEqual(AWSUsageFormat.perHour(5.8), "5,80\(nbsp)$/h")
        XCTAssertEqual(AWSUsageFormat.perHour(nil), "–\(nbsp)$/h")
    }

    func testPercentIsWhole() {
        XCTAssertEqual(AWSUsageFormat.percent(38), "38\(nbsp)%")
        XCTAssertEqual(AWSUsageFormat.percent(37.6), "38\(nbsp)%")
        XCTAssertEqual(AWSUsageFormat.percent(112.4), "112\(nbsp)%")
        XCTAssertEqual(AWSUsageFormat.percent(nil), "–")
    }

    func testMenuBarTitle() throws {
        XCTAssertEqual(AWSUsageFormat.menuBarTitle(try usage()), "38\(nbsp)% · 19,01\(nbsp)$")
        XCTAssertEqual(AWSUsageFormat.menuBarTitle(nil), "–")
    }

    func testMonthTitle() {
        XCTAssertEqual(AWSUsageFormat.monthTitle("2026-11"), "November 2026")
        XCTAssertEqual(AWSUsageFormat.monthTitle("2026-03"), "März 2026")
        XCTAssertEqual(AWSUsageFormat.monthTitle("kaputt"), "kaputt")
    }

    func testTimeSaysTodayYesterdayOrDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let now = try XCTUnwrap(AWSUsageCoding.parseInstant("2026-11-01T16:00:00Z"))
        let today = try XCTUnwrap(AWSUsageCoding.parseInstant("2026-11-01T14:00:00Z"))
        let yesterday = try XCTUnwrap(AWSUsageCoding.parseInstant("2026-10-31T14:00:00Z"))
        let earlier = try XCTUnwrap(AWSUsageCoding.parseInstant("2026-10-29T14:00:00Z"))
        // Die Uhrzeit selbst schreibt Foundation in der Zone des Geräts - geprüft
        // wird nur, was davor steht.
        XCTAssertFalse(AWSUsageFormat.time(today, now: now, calendar: calendar).contains("gestern"))
        XCTAssertTrue(AWSUsageFormat.time(yesterday, now: now, calendar: calendar).hasPrefix("gestern "))
        XCTAssertTrue(AWSUsageFormat.time(earlier, now: now, calendar: calendar).hasPrefix("29.10. "))
    }

    func testRuntime() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(AWSUsageFormat.runtime(from: start, to: start.addingTimeInterval(35 * 60)), "35\(nbsp)min")
        XCTAssertEqual(AWSUsageFormat.runtime(from: start, to: start.addingTimeInterval(123 * 60)), "2:03\(nbsp)h")
        XCTAssertEqual(AWSUsageFormat.runtime(from: start, to: start.addingTimeInterval(76 * 3600)),
                       "3\(nbsp)T 4\(nbsp)h")
    }

    func testBudgetInput() {
        XCTAssertEqual(AWSUsageFormat.parseLimit("60"), 60)
        XCTAssertEqual(AWSUsageFormat.parseLimit("60,5"), 60.5)
        XCTAssertEqual(AWSUsageFormat.parseLimit("60.50"), 60.5)
        XCTAssertEqual(AWSUsageFormat.parseLimit(" 75 $ "), 75)
        XCTAssertEqual(AWSUsageFormat.parseLimit("1.250,50"), 1250.5)
        XCTAssertNil(AWSUsageFormat.parseLimit("0"))
        XCTAssertNil(AWSUsageFormat.parseLimit("-5"))
        XCTAssertNil(AWSUsageFormat.parseLimit("20000"), "mehr als 10.000 nimmt der Dienst nicht")
        XCTAssertNil(AWSUsageFormat.parseLimit("viel"))
        XCTAssertEqual(AWSUsageFormat.limitInput(1250), "1250", "ohne Tausenderpunkt, sonst läse es 1,25")
        XCTAssertEqual(AWSUsageFormat.limitInput(62.5), "62,5")
        XCTAssertEqual(AWSUsageFormat.parseLimit(AWSUsageFormat.limitInput(62.5)), 62.5)
    }

    // MARK: - Balken

    func testBarSegmentsAreFractionsOfTheBudget() throws {
        let segments = try usage().barSegments()
        XCTAssertEqual(segments.map(\.key), ["llm", "llm", "hytale", "hosting", "other"])
        XCTAssertEqual(segments[0].fraction, 6.29 / 50, accuracy: 0.000_1)
        XCTAssertFalse(segments[0].live)
        XCTAssertEqual(segments[1].fraction, 1.81 / 50, accuracy: 0.000_1)
        XCTAssertTrue(segments[1].live)
        XCTAssertEqual(segments.map(\.fraction).reduce(0, +), 19.01 / 50, accuracy: 0.000_1)
    }

    func testOverBudgetFillsTheBarAndNoMore() throws {
        let json = String(decoding: Self.example, as: UTF8.self)
            .replacingOccurrences(of: "\"limit\": 50.0", with: "\"limit\": 10.0")
        let usage = try AWSUsageCoding.decoder().decode(AWSUsage.self, from: Data(json.utf8))
        let segments = usage.barSegments()
        XCTAssertEqual(segments.map(\.fraction).reduce(0, +), 1, accuracy: 0.000_1)
        XCTAssertEqual(segments.first?.key, "llm", "von hinten gekappt - die Reihenfolge bleibt")
    }

    func testMonthPartsKeepTheCategoryOrder() throws {
        let month = try XCTUnwrap(try usage().months.first)
        XCTAssertEqual(month.parts.map(\.key), ["llm", "hytale", "hosting", "other"])
        XCTAssertEqual(month.parts[1].amount, 22.79)
    }

    // MARK: - Client

    func testTheClientSendsTheTokenAsBearer() async throws {
        StubProtocol.respond(status: 200, body: Self.example)
        let (usage, _) = try await client().usage()
        XCTAssertEqual(usage.spent, 19.01)
        let request = try XCTUnwrap(StubProtocol.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer geheim")
        XCTAssertEqual(request.url?.absoluteString, "https://example.invalid/aws-usage/api/usage")
    }

    func testNoAccessIsAnAccessProblem() async {
        StubProtocol.respond(status: 401, body: Data(#"{"error": "Kein Zugang"}"#.utf8))
        do {
            _ = try await client().usage()
            XCTFail("401 darf nicht als Stand durchgehen")
        } catch {
            XCTAssertEqual(error as? AWSUsageError, .notAuthorised)
        }
    }

    func testNotYetFetchedShowsTheServiceMessage() async {
        StubProtocol.respond(status: 503, body: Data(#"{"error": "Noch kein Abruf bei AWS."}"#.utf8))
        do {
            _ = try await client().usage()
            XCTFail("503 ist kein Stand")
        } catch {
            XCTAssertEqual(error as? AWSUsageError, .unavailable("Noch kein Abruf bei AWS."))
        }
    }

    func testBudgetIsAPutWithTheLimit() async throws {
        StubProtocol.respond(status: 200, body: Self.example)
        _ = try await client().setBudget(limit: 60)
        let request = try XCTUnwrap(StubProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path(), "/aws-usage/api/budget")
        let body = try XCTUnwrap(StubProtocol.lastBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Double])
        XCTAssertEqual(object["limit"], 60)
    }

    private func client() -> AWSUsageClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return AWSUsageClient(baseURL: URL(string: "https://example.invalid/aws-usage")!,
                              token: "geheim",
                              session: URLSession(configuration: configuration))
    }
}

/// Antwortet ohne Netz und merkt sich die Anfrage.
private final class StubProtocol: URLProtocol, @unchecked Sendable {

    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    static func respond(status: Int, body: Data) {
        self.status = status
        self.body = body
        lastRequest = nil
        lastBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        // URLSession reicht den Rumpf als Stream weiter, nicht als `httpBody`.
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            stream.close()
            Self.lastBody = data
        } else {
            Self.lastBody = request.httpBody
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
