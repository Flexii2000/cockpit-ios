import XCTest
@testable import Vault

/// Der Cloud-Tab und die Menüleisten-App lesen denselben Stand (`CloudUsageShared`):
/// Vertrag `../cloud-usage/docs/API.md`. Hier die AWS-Felder und der Client, Verda in
/// `VerdaUsageTests`. Kein Netz - der Client läuft gegen einen Stub-`URLProtocol`.
final class CloudUsageTests: XCTestCase {

    private let nbsp = "\u{00A0}"

    /// Das Beispiel aus API.md vom 01.11. (ohne `spot` und `verda`, wie ein älterer
    /// Dienst), dazu eine zweite Instanz ohne Preis (`pricePerHour` kann `null` sein)
    /// und Nanosekunden am Zeitpunkt.
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
        try CloudUsageCoding.decoder().decode(AWSUsage.self, from: Self.example)
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
        let usage = try CloudUsageCoding.decoder().decode(AWSUsage.self, from: Data(json.utf8))
        XCTAssertNil(usage.percent)
        XCTAssertNil(usage.forecast)
        XCTAssertEqual(CloudUsageFormat.menuBarTitle(usage), "19,01\(nbsp)$", "ohne Prozent nur der Betrag")
    }

    // MARK: - Schreibweise

    func testDollars() {
        XCTAssertEqual(CloudUsageFormat.dollars(19.01), "19,01\(nbsp)$")
        XCTAssertEqual(CloudUsageFormat.dollars(1234.5), "1.234,50\(nbsp)$")
        XCTAssertEqual(CloudUsageFormat.dollars(0), "0,00\(nbsp)$")
        XCTAssertEqual(CloudUsageFormat.limit(50), "50\(nbsp)$")
        XCTAssertEqual(CloudUsageFormat.limit(62.5), "62,50\(nbsp)$")
    }

    func testPricePerHourKeepsUpToFourDecimals() {
        XCTAssertEqual(CloudUsageFormat.perHour(0.2394), "0,2394\(nbsp)$/h")
        XCTAssertEqual(CloudUsageFormat.perHour(1.86), "1,86\(nbsp)$/h")
        XCTAssertEqual(CloudUsageFormat.perHour(5.8), "5,80\(nbsp)$/h")
        XCTAssertEqual(CloudUsageFormat.perHour(nil), "–\(nbsp)$/h")
    }

    func testPercentIsWhole() {
        XCTAssertEqual(CloudUsageFormat.percent(38), "38\(nbsp)%")
        XCTAssertEqual(CloudUsageFormat.percent(37.6), "38\(nbsp)%")
        XCTAssertEqual(CloudUsageFormat.percent(112.4), "112\(nbsp)%")
        XCTAssertEqual(CloudUsageFormat.percent(nil), "–")
    }

    func testMenuBarTitle() throws {
        XCTAssertEqual(CloudUsageFormat.menuBarTitle(try usage()), "38\(nbsp)% · 19,01\(nbsp)$")
        XCTAssertEqual(CloudUsageFormat.menuBarTitle(nil), "–")
    }

    func testMonthTitle() {
        XCTAssertEqual(CloudUsageFormat.monthTitle("2026-11"), "November 2026")
        XCTAssertEqual(CloudUsageFormat.monthTitle("2026-03"), "März 2026")
        XCTAssertEqual(CloudUsageFormat.monthTitle("kaputt"), "kaputt")
    }

    func testTimeSaysTodayYesterdayOrDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Berlin"))
        let now = try XCTUnwrap(CloudUsageCoding.parseInstant("2026-11-01T16:00:00Z"))
        let today = try XCTUnwrap(CloudUsageCoding.parseInstant("2026-11-01T14:00:00Z"))
        let yesterday = try XCTUnwrap(CloudUsageCoding.parseInstant("2026-10-31T14:00:00Z"))
        let earlier = try XCTUnwrap(CloudUsageCoding.parseInstant("2026-10-29T14:00:00Z"))
        // Die Uhrzeit selbst schreibt Foundation in der Zone des Geräts - geprüft
        // wird nur, was davor steht.
        XCTAssertFalse(CloudUsageFormat.time(today, now: now, calendar: calendar).contains("gestern"))
        XCTAssertTrue(CloudUsageFormat.time(yesterday, now: now, calendar: calendar).hasPrefix("gestern "))
        XCTAssertTrue(CloudUsageFormat.time(earlier, now: now, calendar: calendar).hasPrefix("29.10. "))
    }

    func testRuntime() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(CloudUsageFormat.runtime(from: start, to: start.addingTimeInterval(35 * 60)), "35\(nbsp)min")
        XCTAssertEqual(CloudUsageFormat.runtime(from: start, to: start.addingTimeInterval(123 * 60)), "2:03\(nbsp)h")
        XCTAssertEqual(CloudUsageFormat.runtime(from: start, to: start.addingTimeInterval(76 * 3600)),
                       "3\(nbsp)T 4\(nbsp)h")
    }

    func testBudgetInput() {
        XCTAssertEqual(CloudUsageFormat.parseLimit("60"), 60)
        XCTAssertEqual(CloudUsageFormat.parseLimit("60,5"), 60.5)
        XCTAssertEqual(CloudUsageFormat.parseLimit("60.50"), 60.5)
        XCTAssertEqual(CloudUsageFormat.parseLimit(" 75 $ "), 75)
        XCTAssertEqual(CloudUsageFormat.parseLimit("1.250,50"), 1250.5)
        XCTAssertNil(CloudUsageFormat.parseLimit("0"))
        XCTAssertNil(CloudUsageFormat.parseLimit("-5"))
        XCTAssertNil(CloudUsageFormat.parseLimit("20000"), "mehr als 10.000 nimmt der Dienst nicht")
        XCTAssertNil(CloudUsageFormat.parseLimit("viel"))
        XCTAssertEqual(CloudUsageFormat.limitInput(1250), "1250", "ohne Tausenderpunkt, sonst läse es 1,25")
        XCTAssertEqual(CloudUsageFormat.limitInput(62.5), "62,5")
        XCTAssertEqual(CloudUsageFormat.parseLimit(CloudUsageFormat.limitInput(62.5)), 62.5)
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
        let usage = try CloudUsageCoding.decoder().decode(AWSUsage.self, from: Data(json.utf8))
        let segments = usage.barSegments()
        XCTAssertEqual(segments.map(\.fraction).reduce(0, +), 1, accuracy: 0.000_1)
        XCTAssertEqual(segments.first?.key, "llm", "von hinten gekappt - die Reihenfolge bleibt")
    }

    func testMonthPartsKeepTheCategoryOrder() throws {
        let month = try XCTUnwrap(try usage().months.first)
        XCTAssertEqual(month.parts.map(\.key), ["llm", "hytale", "hosting", "other"])
        XCTAssertEqual(month.parts[1].amount, 22.79)
    }

    // MARK: - Spot

    /// Das `spot`-Feld aus API.md (seit 02.11.), angehängt ans Beispiel - mit der
    /// LLM-Instanz auf On-Demand, wie nach einer Rückholung.
    private func usageWithSpot(estimate: Int = 4, launchable: Bool = true, checkedAt: String = "2026-11-02T14:32:00Z",
                               lifecycle: String = "on-demand") throws -> AWSUsage {
        var json = String(decoding: Self.example, as: UTF8.self)
        json = json.replacingOccurrences(of: "\"lifecycle\": \"spot\"", with: "\"lifecycle\": \"\(lifecycle)\"")
            .replacingOccurrences(of: "\"pricePerHour\": 1.86,", with: "\"pricePerHour\": 5.85,")
        json = json.replacingOccurrences(of: "\"problem\": null\n}", with: """
        "problem": null,
          "spot": {
            "region": "eu-west-2", "threshold": 7, "counts": [1, 2, 4, 8], "quotaVcpus": 8,
            "types": [
              { "type": "g7e.2xlarge", "vcpus": 8, "launchable": \(launchable), "estimate": \(estimate),
                "pricePerHour": 1.883,
                "zones": [
                  { "zone": "eu-west-2a", "score": 9, "estimate": \(estimate), "pricePerHour": 1.8849 },
                  { "zone": "eu-west-2c", "score": 7, "estimate": 1, "pricePerHour": 1.883 }
                ] },
              { "type": "g7e.12xlarge", "vcpus": 48, "launchable": false, "estimate": 0,
                "pricePerHour": 4.2069, "zones": [] }
            ],
            "checkedAt": "\(checkedAt)",
            "problem": null
          }
        }
        """)
        return try CloudUsageCoding.decoder().decode(AWSUsage.self, from: Data(json.utf8))
    }

    private let afterCheck = CloudUsageCoding.parseInstant("2026-11-02T14:33:00Z")!

    func testWithoutSpotTheUsageStillReads() throws {
        XCTAssertNil(try usage().spot, "ein älterer Dienst kennt das Feld nicht")
    }

    func testSpotReads() throws {
        let spot = try XCTUnwrap(try usageWithSpot().spot)
        XCTAssertEqual(spot.maxCount, 8)
        XCTAssertEqual(spot.quotaVcpus, 8)
        XCTAssertEqual(spot.types.map(\.type), ["g7e.2xlarge", "g7e.12xlarge"])
        XCTAssertTrue(spot.types[0].isLaunchable)
        XCTAssertFalse(spot.types[1].isLaunchable)
        XCTAssertEqual(spot.types[0].zones.map(\.score), [9, 7])
    }

    func testSpotCountAndZones() throws {
        XCTAssertEqual(CloudUsageFormat.spotCount(0, max: 8), "0\(nbsp)frei")
        XCTAssertEqual(CloudUsageFormat.spotCount(4, max: 8), "≈\(nbsp)4\(nbsp)frei")
        XCTAssertEqual(CloudUsageFormat.spotCount(8, max: 8), "8+\(nbsp)frei")
        let zones = try XCTUnwrap(try usageWithSpot().spot).types[0].zones
        XCTAssertEqual(CloudUsageFormat.spotZones(zones), "2a\(nbsp)9/10 · 2c\(nbsp)7/10")
        XCTAssertEqual(CloudUsageFormat.spotZones([]), "–")
        XCTAssertEqual(CloudUsageFormat.regionName("eu-west-2"), "London")
    }

    func testSpotAlertWhileTheLlmRunsOnDemand() throws {
        let alert = try XCTUnwrap(AWSSpotAlert.due(try usageWithSpot(), sent: [], now: afterCheck))
        XCTAssertEqual(alert.instanceID, "i-0562fb060733c92b9")
        XCTAssertEqual(alert.title, "LLM: Spot frei")
        XCTAssertEqual(alert.body, "g7e.2xlarge · ≈\(nbsp)4\(nbsp)frei · 1,883\(nbsp)$/h statt 5,85\(nbsp)$/h")
    }

    func testSpotAlertOnlyOnceAndOnlyWhenItHelps() throws {
        XCTAssertNil(AWSSpotAlert.due(try usageWithSpot(), sent: ["i-0562fb060733c92b9"], now: afterCheck),
                     "einmal je Instanz")
        XCTAssertNil(AWSSpotAlert.due(try usageWithSpot(estimate: 0), sent: [], now: afterCheck), "nichts frei")
        XCTAssertNil(AWSSpotAlert.due(try usageWithSpot(launchable: false), sent: [], now: afterCheck),
                     "Quota reicht nicht")
        XCTAssertNil(AWSSpotAlert.due(try usageWithSpot(lifecycle: "spot"), sent: [], now: afterCheck),
                     "läuft schon auf Spot")
        XCTAssertNil(AWSSpotAlert.due(try usageWithSpot(checkedAt: "2026-11-02T14:00:00Z"), sent: [], now: afterCheck),
                     "alte Spot-Zahlen")
    }

    // MARK: - Client

    func testTheClientSendsTheTokenAsBearer() async throws {
        StubProtocol.respond(status: 200, body: Self.example)
        let (usage, _) = try await client().usage()
        XCTAssertEqual(usage.spent, 19.01)
        let request = try XCTUnwrap(StubProtocol.lastRequest)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer geheim")
        XCTAssertEqual(request.url?.absoluteString, "https://example.invalid/cloud-usage/api/usage")
    }

    func testNoAccessIsAnAccessProblem() async {
        StubProtocol.respond(status: 401, body: Data(#"{"error": "Kein Zugang"}"#.utf8))
        do {
            _ = try await client().usage()
            XCTFail("401 darf nicht als Stand durchgehen")
        } catch {
            XCTAssertEqual(error as? CloudUsageError, .notAuthorised)
        }
    }

    func testNotYetFetchedShowsTheServiceMessage() async {
        StubProtocol.respond(status: 503, body: Data(#"{"error": "Noch kein Abruf bei AWS."}"#.utf8))
        do {
            _ = try await client().usage()
            XCTFail("503 ist kein Stand")
        } catch {
            XCTAssertEqual(error as? CloudUsageError, .unavailable("Noch kein Abruf bei AWS."))
        }
    }

    /// Beide Kopien der Adresse (Vault: `Backend.cloud`, Mac: `CloudUsageEndpoint`)
    /// zeigen auf den umbenannten Dienst (02.11.).
    func testBothAddressesPointToCloudUsage() {
        XCTAssertEqual(CloudUsageEndpoint.url.absoluteString, "https://fherrmann.com/cloud-usage")
        XCTAssertEqual(Backend.cloud.url, CloudUsageEndpoint.url)
        XCTAssertEqual(Backend.cloud.title, "Cloud")
        XCTAssertEqual(Backend.cloud.systemImage, "cloud")
    }

    func testBudgetIsAPutWithTheLimit() async throws {
        StubProtocol.respond(status: 200, body: Self.example)
        _ = try await client().setBudget(limit: 60)
        let request = try XCTUnwrap(StubProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path(), "/cloud-usage/api/budget")
        let body = try XCTUnwrap(StubProtocol.lastBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Double])
        XCTAssertEqual(object["limit"], 60)
    }

    private func client() -> CloudUsageClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return CloudUsageClient(baseURL: URL(string: "https://example.invalid/cloud-usage")!,
                              token: "geheim",
                              session: URLSession(configuration: configuration))
    }
}
