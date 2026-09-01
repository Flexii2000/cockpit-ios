import Foundation

/// Die Endpunkte des Weight Trackers. Siehe docs/BACKENDS.md.
struct WeightAPI: Sendable {

    private let client = APIClient(backend: .weight)

    func summary() async throws -> WeightSummary {
        try await client.get("/api/weight/summary")
    }

    func points(_ range: WeightRange) async throws -> [WeightPoint] {
        try await client.get(range.path)
    }

    func vacations() async throws -> [Vacation] {
        try await client.get("/api/weight/vacations")
    }

    func dashboard() async throws -> DashboardConfig {
        try await client.get("/api/dashboard")
    }

    func saveDashboard(_ widgets: [String]) async throws -> DashboardConfig {
        try await client.send("PUT", "/api/dashboard", body: DashboardConfig(widgets: widgets))
    }

    func add(date: CalendarDate, weightKg: Double) async throws -> WeightSummary {
        try await client.send("POST", "/api/weight",
                              body: NewWeightRequest(date: date, weightKg: weightKg))
    }

    func updateTarget(_ weightKg: Double) async throws -> WeightSummary {
        try await client.send("PUT", "/api/weight/target",
                              body: UpdateTargetRequest(targetWeightKg: weightKg))
    }
}
