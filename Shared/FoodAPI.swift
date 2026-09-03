import Foundation

/// Die Endpunkte des Kalorienzaehlers. Siehe docs/BACKENDS.md.
struct FoodAPI: Sendable {

    private let client: APIClient

    /// - Parameters:
    ///   - cookie: nur fuer die Widget-Erweiterung, die keinen gemeinsamen
    ///     Cookie-Speicher hat.
    ///   - timeout: in einer Erweiterung ist das Zeitbudget knapp - dort
    ///     lieber zwoelf Sekunden als die zweihundert, die die
    ///     Schnellerfassung braucht.
    init(cookie: String? = nil, timeout: TimeInterval = 200) {
        client = APIClient(backend: .food, cookie: cookie, timeout: timeout)
    }

    func day(_ date: CalendarDate) async throws -> DaySummary {
        try await client.get("/api/food/day", query: [URLQueryItem(name: "date", value: date.iso)])
    }

    func daily(from: CalendarDate, to: CalendarDate) async throws -> [DayTotal] {
        try await client.get("/api/food/daily", query: [
            URLQueryItem(name: "from", value: from.iso),
            URLQueryItem(name: "to", value: to.iso),
        ])
    }

    func dishes() async throws -> [Dish] {
        try await client.get("/api/food/dishes")
    }

    func createDish(_ request: DishRequest) async throws -> Dish {
        try await client.send("POST", "/api/food/dishes", body: request)
    }

    func updateDish(id: String, _ request: DishRequest) async throws -> Dish {
        try await client.send("PUT", "/api/food/dishes/\(id)", body: request)
    }

    func deleteDish(id: String) async throws {
        let _: APIClient.Empty = try await client.delete("/api/food/dishes/\(id)")
    }

    /// Darf ohne Netz warten: der Eintrag traegt sein Datum, er gilt spaeter
    /// genauso.
    func addEntry(_ request: NewEntryRequest) async throws -> DaySummary {
        try await client.send("POST", "/api/food/entries", body: request, queueWhenOffline: true)
    }

    func deleteEntry(id: String) async throws -> DaySummary {
        try await client.delete("/api/food/entries/\(id)", queueWhenOffline: true)
    }

    func targets() async throws -> Nutrients {
        try await client.get("/api/food/targets")
    }

    func updateTargets(_ request: TargetsRequest) async throws -> Nutrients {
        try await client.send("PUT", "/api/food/targets", body: request)
    }

    /// Ob die Schnellerfassung ueberhaupt angeboten wird - sie ist
    /// serverseitig abschaltbar, dann gibt es sie schlicht nicht.
    func features() async throws -> Features {
        try await client.get("/api/food/features")
    }

    /// Meldet dieses Geraet fuer Benachrichtigungen an.
    func registerDevice(token: String) async throws {
        let _: APIClient.Empty = try await client.send(
            "POST", "/api/food/devices", body: DeviceRegistration(token: token))
    }

    func startQuickCapture(_ request: QuickCaptureRequest) async throws -> QuickCaptureJob {
        try await client.send("POST", "/api/food/quick-capture", body: request)
    }

    func quickCaptureStatus(id: String) async throws -> QuickCaptureJob {
        try await client.get("/api/food/quick-capture/\(id)")
    }
}
