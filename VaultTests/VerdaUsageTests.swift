import XCTest
@testable import Vault

/// Verda im Stand von `GET /cloud-usage/api/usage` (seit 02.11.) - Vertrag
/// `../cloud-usage/docs/API.md`, Abschnitt „`verda`“. Euro, eigenes Budget, in der
/// Menüleiste hinter AWS.
final class VerdaUsageTests: XCTestCase {

    private let nbsp = "\u{00A0}"

    /// Das Beispiel aus API.md vom 02.11., wörtlich - mit `spot` und `verda`.
    static let contract = Data("""
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
        {
          "key": "llm",
          "name": "LLM",
          "amount": 8.10,
          "live": 1.81,
          "items": [
            { "label": "EC2-Rechenzeit", "amount": 6.29, "live": false },
            { "label": "Läuft: Spot g7e.2xlarge", "amount": 1.81, "live": true }
          ]
        },
        { "key": "hytale",  "name": "Hytale",    "amount": 6.40, "live": 0.0, "items": [] },
        { "key": "hosting", "name": "Hosting",   "amount": 4.12, "live": 0.0, "items": [] },
        { "key": "other",   "name": "Sonstiges", "amount": 0.39, "live": 0.0, "items": [] }
      ],
      "running": [
        {
          "id": "i-0562fb060733c92b9",
          "name": "llm-ondemand",
          "category": "llm",
          "region": "eu-west-2",
          "type": "g7e.2xlarge",
          "lifecycle": "spot",
          "pricePerHour": 1.86,
          "launchedAt": "2026-11-01T14:02:00Z",
          "estimate": 1.81
        }
      ],
      "months": [
        {
          "month": "2026-10",
          "total": 37.10,
          "categories": { "llm": 0.0, "hytale": 22.79, "hosting": 9.79, "other": 0.54 }
        }
      ],
      "billedAt": "2026-11-01T15:00:00Z",
      "liveAt": "2026-11-01T16:05:00Z",
      "problem": null,
      "spot": {
        "region": "eu-west-2",
        "threshold": 7,
        "counts": [1, 2, 4, 8],
        "quotaVcpus": 8,
        "types": [
          {
            "type": "g7e.2xlarge",
            "vcpus": 8,
            "launchable": true,
            "estimate": 4,
            "pricePerHour": 1.8849,
            "zones": [
              { "zone": "eu-west-2a", "score": 9, "estimate": 4, "pricePerHour": 1.8849 },
              { "zone": "eu-west-2c", "score": 7, "estimate": 1, "pricePerHour": 1.883 }
            ]
          },
          {
            "type": "g7e.12xlarge",
            "vcpus": 48,
            "launchable": false,
            "estimate": 0,
            "pricePerHour": 4.1923,
            "zones": [
              { "zone": "eu-west-2a", "score": 1, "estimate": 0, "pricePerHour": 4.1923 },
              { "zone": "eu-west-2c", "score": 3, "estimate": 0, "pricePerHour": 4.2069 }
            ]
          }
        ],
        "checkedAt": "2026-11-02T14:32:00Z",
        "problem": null
      },
      "verda": {
        "currency": "EUR",
        "month": "2026-11",
        "balance": 21.80,
        "spent": 3.20,
        "topUps": 0.0,
        "budget": { "limit": 50.0 },
        "percent": 6.4,
        "running": [
          {
            "id": "b49beaee-5b97-4a60-aa1d-75a6b89ca23b",
            "name": "verda-llm-server-1102-1800",
            "role": "server",
            "phase": "ready",
            "type": "2B300.60V",
            "location": "FIN-03",
            "lifecycle": "spot",
            "pricePerHour": 9.87,
            "launchedAt": "2026-11-02T17:00:00Z",
            "estimate": 3.29
          }
        ],
        "volumes": [
          { "id": "…", "name": "alt-os", "sizeGb": 900, "status": "detached" }
        ],
        "buckets": [
          { "name": "verda-llm-efe19818", "sizeGb": 510.3 }
        ],
        "months": [
          { "month": "2026-10", "spent": 0.0 }
        ],
        "trackingSince": "2026-11-02T16:30:00Z",
        "checkedAt": "2026-11-02T18:05:00Z",
        "problem": null
      }
    }
    """.utf8)

    private func decode(_ json: String) throws -> AWSUsage {
        try CloudUsageCoding.decoder().decode(AWSUsage.self, from: Data(json.utf8))
    }

    private var contractJSON: String { String(decoding: Self.contract, as: UTF8.self) }

    /// Der `verda`-Block des Beispiels, durch `replacement` ersetzt.
    private func withVerda(_ replacement: String) throws -> AWSUsage {
        let json = contractJSON
        let start = try XCTUnwrap(json.range(of: "\"verda\": {"))
        let end = try XCTUnwrap(json.range(of: "\n  }\n}", options: .backwards))
        return try decode(json.replacingCharacters(in: start.lowerBound..<end.upperBound,
                                                   with: "\"verda\": \(replacement)\n}"))
    }

    private func date(_ raw: String) throws -> Date {
        try XCTUnwrap(CloudUsageCoding.parseInstant(raw))
    }

    // MARK: - Lesen

    func testTheContractExampleReadsEveryVerdaField() throws {
        let usage = try decode(contractJSON)
        // AWS unverändert daneben.
        XCTAssertEqual(usage.spent, 19.01)
        XCTAssertEqual(usage.percent, 38)
        XCTAssertNotNil(usage.spot)

        let verda = try XCTUnwrap(usage.verda)
        XCTAssertEqual(verda.currency, "EUR")
        XCTAssertEqual(verda.month, "2026-11")
        XCTAssertEqual(verda.balance, 21.80)
        XCTAssertEqual(verda.spent, 3.20)
        XCTAssertEqual(verda.topUps, 0)
        XCTAssertEqual(verda.budget?.limit, 50)
        XCTAssertEqual(verda.percent, 6.4)
        XCTAssertEqual(verda.trackingSince, try date("2026-11-02T16:30:00Z"))
        XCTAssertEqual(verda.checkedAt, try date("2026-11-02T18:05:00Z"))
        XCTAssertNil(verda.problem)

        let instance = try XCTUnwrap(verda.running.first)
        XCTAssertEqual(verda.running.count, 1)
        XCTAssertEqual(instance.id, "b49beaee-5b97-4a60-aa1d-75a6b89ca23b")
        XCTAssertEqual(instance.name, "verda-llm-server-1102-1800")
        XCTAssertEqual(instance.role, "server")
        XCTAssertEqual(instance.phase, "ready")
        XCTAssertEqual(instance.type, "2B300.60V")
        XCTAssertEqual(instance.location, "FIN-03")
        XCTAssertEqual(instance.lifecycle, "spot")
        XCTAssertTrue(instance.isSpot)
        XCTAssertEqual(instance.pricePerHour, 9.87)
        XCTAssertEqual(instance.launchedAt, try date("2026-11-02T17:00:00Z"))
        XCTAssertEqual(instance.estimate, 3.29)

        let volume = try XCTUnwrap(verda.volumes.first)
        XCTAssertEqual(volume.id, "…")
        XCTAssertEqual(volume.name, "alt-os")
        XCTAssertEqual(volume.sizeGb, 900)
        XCTAssertEqual(volume.status, "detached")

        XCTAssertEqual(verda.buckets.map(\.name), ["verda-llm-efe19818"])
        XCTAssertEqual(verda.buckets.first?.sizeGb, 510.3)
        XCTAssertEqual(verda.months.map(\.month), ["2026-10"])
        XCTAssertEqual(verda.months.first?.spent, 0)
    }

    func testVerdaNullLeavesAWSAsItWas() throws {
        let usage = try withVerda("null")
        XCTAssertNil(usage.verda)
        XCTAssertEqual(usage.spent, 19.01)
        XCTAssertEqual(CloudUsageFormat.menuBarTitle(usage), "38\(nbsp)% · 19,01\(nbsp)$", "wie vor Verda")
    }

    func testAnOlderServiceWithoutVerdaStillReads() throws {
        let usage = try CloudUsageCoding.decoder().decode(AWSUsage.self, from: CloudUsageTests.example)
        XCTAssertNil(usage.verda)
    }

    func testAnUnreadableVerdaBlockOnlyHidesVerda() throws {
        let json = contractJSON.replacingOccurrences(of: "\"balance\": 21.80", with: "\"balance\": \"viel\"")
        let usage = try decode(json)
        XCTAssertNil(usage.verda, "Verda ausgeblendet")
        XCTAssertEqual(usage.spent, 19.01, "AWS bleibt lesbar")
        XCTAssertNotNil(usage.spot)
    }

    func testWithoutBudgetAndForeignInstance() throws {
        let usage = try withVerda("""
        {
            "currency": "EUR", "month": "2026-11", "balance": 5.0, "spent": 12.5, "topUps": 10.0,
            "budget": null, "percent": null,
            "running": [
              { "id": "x-1", "name": "fremd", "role": null, "phase": null, "type": "1V100.6V",
                "location": "FIN-01", "lifecycle": "on-demand", "pricePerHour": null,
                "launchedAt": "2026-11-02T17:00:00.123456789Z", "estimate": 0.12 }
            ],
            "volumes": [], "buckets": [], "months": [],
            "trackingSince": "2026-10-20T08:00:00Z", "checkedAt": "2026-11-02T18:05:00Z",
            "problem": "Verda antwortet nicht."
          }
        """)
        let verda = try XCTUnwrap(usage.verda)
        XCTAssertNil(verda.budget)
        XCTAssertNil(verda.percent)
        XCTAssertEqual(verda.budgetFraction, 0, "ohne Budget bleibt der Balken leer")
        let instance = try XCTUnwrap(verda.running.first)
        XCTAssertNil(instance.role)
        XCTAssertNil(instance.phase)
        XCTAssertNil(instance.pricePerHour)
        XCTAssertFalse(instance.isSpot)
        XCTAssertNotNil(instance.launchedAt, "Nanosekunden wie bei Spring")
        XCTAssertEqual(verda.problem, "Verda antwortet nicht.")
        XCTAssertFalse(verda.startedThisMonth, "Messung seit Oktober")
        XCTAssertEqual(CloudUsageFormat.menuBarTitle(usage), "38\(nbsp)% · 19,01\(nbsp)$ · 12,50\(nbsp)€",
                       "auch ohne Verda-Budget der Betrag")
    }

    // MARK: - Menüleiste

    func testMenuBarTitleWithVerda() throws {
        let usage = try decode(contractJSON)
        XCTAssertEqual(CloudUsageFormat.menuBarTitle(usage), "38\(nbsp)% · 19,01\(nbsp)$ · 3,20\(nbsp)€")
    }

    func testMenuBarTitleWithVerdaButNoAWSPercent() throws {
        let json = contractJSON.replacingOccurrences(of: "\"percent\": 38.0", with: "\"percent\": null")
        XCTAssertEqual(CloudUsageFormat.menuBarTitle(try decode(json)), "19,01\(nbsp)$ · 3,20\(nbsp)€")
    }

    // MARK: - Schreibweise

    func testEuros() {
        XCTAssertEqual(CloudUsageFormat.euros(3.2), "3,20\(nbsp)€")
        XCTAssertEqual(CloudUsageFormat.euros(1234.5), "1.234,50\(nbsp)€")
        XCTAssertEqual(CloudUsageFormat.euros(0), "0,00\(nbsp)€")
        XCTAssertEqual(CloudUsageFormat.euroLimit(50), "50\(nbsp)€")
        XCTAssertEqual(CloudUsageFormat.euroLimit(62.5), "62,50\(nbsp)€")
        XCTAssertEqual(CloudUsageFormat.euroPerHour(9.87), "9,87\(nbsp)€/h")
        XCTAssertEqual(CloudUsageFormat.euroPerHour(nil), "–\(nbsp)€/h")
        XCTAssertEqual(CloudUsageFormat.limit(50), "50\(nbsp)$", "AWS bleibt in Dollar")
        XCTAssertEqual(CloudUsageFormat.perHour(1.86), "1,86\(nbsp)$/h")
    }

    func testGigabytes() {
        XCTAssertEqual(CloudUsageFormat.gigabytes(510.3), "510,3\(nbsp)GB")
        XCTAssertEqual(CloudUsageFormat.gigabytes(900), "900\(nbsp)GB")
        XCTAssertEqual(CloudUsageFormat.gigabytes(1234.56), "1.234,6\(nbsp)GB")
    }

    func testVerdaBudgetInputInEuro() {
        XCTAssertEqual(CloudUsageFormat.parseLimit("60 €"), 60)
        XCTAssertEqual(CloudUsageFormat.parseLimit("60€"), 60)
        XCTAssertEqual(CloudUsageFormat.parseLimit("62,50 €"), 62.5)
        XCTAssertEqual(CloudUsageFormat.parseLimit(" 1.250,50\(nbsp)€ "), 1250.5)
        XCTAssertNil(CloudUsageFormat.parseLimit("0 €"))
        XCTAssertNil(CloudUsageFormat.parseLimit("20000 €"), "mehr als 10.000 nimmt der Dienst nicht")
        XCTAssertNil(CloudUsageFormat.parseLimit("€"))
        XCTAssertEqual(CloudUsageFormat.parseLimit(CloudUsageFormat.limitInput(62.5)), 62.5)
    }

    // MARK: - Balken

    func testBudgetFraction() throws {
        let verda = try XCTUnwrap(try decode(contractJSON).verda)
        XCTAssertEqual(verda.budgetFraction, 3.2 / 50, accuracy: 0.000_1)
        XCTAssertEqual(verda.monthScale, 50, "das Budget ist größer als jeder Vormonat")
        let over = try XCTUnwrap(try decode(contractJSON
            .replacingOccurrences(of: "\"budget\": { \"limit\": 50.0 }", with: "\"budget\": { \"limit\": 2.0 }")).verda)
        XCTAssertEqual(over.budgetFraction, 1, "über dem Budget voll, nicht mehr")
    }

    func testTrackingStartedThisMonth() throws {
        XCTAssertTrue(try XCTUnwrap(try decode(contractJSON).verda).startedThisMonth)
    }

    // MARK: - Client

    func testVerdaBudgetIsAPutToItsOwnPath() async throws {
        StubProtocol.respond(status: 200, body: Self.contract)
        let (usage, _) = try await client().setVerdaBudget(limit: 60)
        XCTAssertEqual(usage.verda?.budget?.limit, 50, "Antwort wie GET /api/usage")
        let request = try XCTUnwrap(StubProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path(), "/cloud-usage/api/verda/budget")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer geheim")
        let body = try XCTUnwrap(StubProtocol.lastBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Double])
        XCTAssertEqual(object, ["limit": 60])
    }

    func testVerdaBudgetWithoutVerdaAccessShowsTheServiceMessage() async {
        StubProtocol.respond(status: 409, body: Data(#"{"error": "Kein Verda-Zugang."}"#.utf8))
        do {
            _ = try await client().setVerdaBudget(limit: 60)
            XCTFail("409 ist kein Stand")
        } catch {
            XCTAssertEqual(error as? CloudUsageError, .http(409, "Kein Verda-Zugang."))
        }
    }

    private func client() -> CloudUsageClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return CloudUsageClient(baseURL: URL(string: "https://example.invalid/cloud-usage")!,
                                token: "geheim",
                                session: URLSession(configuration: configuration))
    }
}
