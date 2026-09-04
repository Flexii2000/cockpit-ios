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

    /// - Parameter keepExisting: `true` laesst einen vorhandenen Wert fuer
    ///   diesen Tag stehen - fuer den Health-Abgleich, der nichts
    ///   ueberschreiben soll.
    /// - Parameter queueWhenOffline: nur fuer die Eingabe von Hand. Der
    ///   Health-Abgleich laesst es aus - er merkt sich seinen Anker erst, wenn
    ///   etwas angekommen ist, und kaeme sonst beim naechsten Lauf mit
    ///   denselben Werten wieder.
    func add(date: CalendarDate, weightKg: Double,
             keepExisting: Bool = false,
             queueWhenOffline: Bool = false) async throws -> WeightSummary {
        try await client.send("POST", "/api/weight",
                              body: NewWeightRequest(date: date, weightKg: weightKg,
                                                     keepExisting: keepExisting),
                              queueWhenOffline: queueWhenOffline)
    }

    // MARK: - Schritte

    func steps(from: CalendarDate, to: CalendarDate) async throws -> [StepDay] {
        try await client.get("/api/steps", query: [
            URLQueryItem(name: "from", value: from.iso),
            URLQueryItem(name: "to", value: to.iso),
        ])
    }

    /// Schickt ein ganzes Fenster auf einmal.
    ///
    /// - Returns: den **gespeicherten** Stand dieser Tage. Der kann hoeher
    ///   sein als das Geschickte: der Server nimmt das Maximum, weil eine
    ///   Schrittzahl innerhalb eines Tages nur wachsen kann.
    @discardableResult
    func sendSteps(_ days: [StepDay]) async throws -> [StepDay] {
        try await client.send("POST", "/api/steps", body: StepsUpload(days: days, replace: nil))
    }

    func stepsGoal() async throws -> StepsGoal {
        try await client.get("/api/steps/goal")
    }

    func updateStepsGoal(_ stepsPerDay: Int) async throws -> StepsGoal {
        try await client.send("PUT", "/api/steps/goal", body: StepsGoal(stepsPerDay: stepsPerDay))
    }

    func updateTarget(_ weightKg: Double) async throws -> WeightSummary {
        try await client.send("PUT", "/api/weight/target",
                              body: UpdateTargetRequest(targetWeightKg: weightKg))
    }
}
