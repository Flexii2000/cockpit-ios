import Foundation

/// Haelt, was das Dashboard zeigt: Recovery, Energie, Gewicht, Essen und
/// Schritte von heute - je aus dem Dienst, der es rechnet.
///
/// **Jede Karte faellt fuer sich aus.** Die Abfragen laufen parallel und
/// scheitern einzeln: ein 404 heisst „kennt dieser Dienst noch nicht" (Recovery
/// und Energie gibt es erst seit dem 09.10.) - dann fehlt die Karte, ohne
/// Meldung. Ein Banner gibt es nur fuer fehlenden Zugang, denn nur dort hilft
/// ein Hinweis. Bei anderen Fehlern bleibt der letzte Stand stehen; ohne Netz
/// liefert ohnehin der Cache (`OfflineCache`).
@MainActor
@Observable
final class DashboardStore {

    private let recoveryApi = RecoveryAPI()
    private let energyApi = EnergyAPI()
    private let weightApi = WeightAPI()
    private let foodApi = FoodAPI()
    private let logbookApi = LogbookAPI()

    private(set) var recovery: RecoveryDay?
    private(set) var energy: EnergySummary?
    /// Die Woche der Energie-Karte: D−7 … heute aus `GET /api/energy` - die
    /// Balken zeigen die vollen Tage, heute dient nur als Ersatz fuer die
    /// Summary.
    private(set) var energyWeek: [EnergyDay]?
    private(set) var weight: WeightSummary?
    private(set) var food: DaySummary?
    private(set) var steps: Int?
    private(set) var logbook: LogbookOverview?
    /// Die Effekte der letzten 90 Tage - die Vorgabe der Logbook-Seite.
    private(set) var insights: LogbookInsights?
    /// Tage, deren Speichern im Postausgang wartet.
    private(set) var queuedLogbookDays: Set<CalendarDate> = []

    private(set) var isLoading = false
    /// Ob schon einmal geladen wurde - vorher zeigt der Tab einen Platzhalter
    /// statt einer leeren Seite.
    private(set) var hasLoaded = false
    /// Dienste, die den Zugang verweigert haben.
    private(set) var accessProblems: [Backend] = []

    /// „Kein Zugang zum Weight Tracker." - nur fuer Dienste ohne Zugang.
    var accessMessage: String? {
        switch (accessProblems.contains(.weight), accessProblems.contains(.food)) {
        case (true, true):  "Kein Zugang zu Weight Tracker und Kalorienzähler."
        case (true, false): "Kein Zugang zum Weight Tracker."
        case (false, true): "Kein Zugang zum Kalorienzähler."
        case (false, false): nil
        }
    }

    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        #if DEBUG
        if DashboardDemo.isOn {
            recovery = DashboardDemo.recoveryDay(offset: 0)
            energy = DashboardDemo.energySummary()
            energyWeek = DashboardDemo.energyDays(from: .today().adding(days: -7), to: .today())
            weight = DashboardDemo.weightSummary()
            food = DashboardDemo.foodDay()
            steps = DashboardDemo.steps
            logbook = DashboardDemo.logbookOverview()
            insights = DashboardDemo.logbookInsights(days: LogbookAPI.defaultPeriod)
            return
        }
        #endif
        // Lokale Kopien: die Abfragen laufen nebenher, ohne den Store.
        let recoveryApi = recoveryApi, energyApi = energyApi
        let weightApi = weightApi, foodApi = foodApi, logbookApi = logbookApi
        let today = CalendarDate.today()
        async let recovery = Self.attempt { try await recoveryApi.today() }
        async let energy = Self.attempt { try await energyApi.summary() }
        async let energyWeek = Self.attempt { try await energyApi.days(from: today.adding(days: -7), to: today) }
        async let weight = Self.attempt { try await weightApi.summary() }
        async let food = Self.attempt { try await foodApi.day(.today()) }
        async let logbook = Self.attempt { try await logbookApi.overview() }
        async let insights = Self.attempt { try await logbookApi.insights(days: LogbookAPI.defaultPeriod) }

        var problems: [Backend] = []
        self.recovery = Self.take(await recovery, previous: self.recovery, backend: .weight, problems: &problems)
        self.energy = Self.take(await energy, previous: self.energy, backend: .weight, problems: &problems)
        self.energyWeek = Self.take(await energyWeek, previous: self.energyWeek, backend: .weight,
                                    problems: &problems)
        self.weight = Self.take(await weight, previous: self.weight, backend: .weight, problems: &problems)
        self.food = Self.take(await food, previous: self.food, backend: .food, problems: &problems)
        self.logbook = Self.take(await logbook, previous: self.logbook, backend: .weight, problems: &problems)
        self.insights = Self.take(await insights, previous: self.insights, backend: .weight, problems: &problems)
        accessProblems = problems
        // Ein Tag im Postausgang ist gespeichert - nur noch nicht beim Dienst.
        if await Outbox.shared.count == 0 { LogbookMemory.clear() }
        queuedLogbookDays = Set(LogbookMemory.load().keys)
        await loadSteps()
    }

    /// Erst Health - das ist die laufende Zahl; der Bestand beim Dienst ist
    /// hoechstens so aktuell wie der letzte Abgleich. Wie im Gewicht-Tab.
    private func loadSteps() async {
        if let live = await HealthSync.shared.todaySteps() {
            steps = live
        } else {
            let today = CalendarDate.today()
            steps = (try? await weightApi.steps(from: today, to: today))?.first?.steps
        }
    }

    nonisolated private static func attempt<T: Sendable>(
        _ call: @Sendable () async throws -> T
    ) async -> Result<T, Error> {
        do {
            return .success(try await call())
        } catch {
            return .failure(error)
        }
    }

    /// Erfolg uebernehmen; ein 404 heisst „gibt es noch nicht" - die Karte
    /// fehlt. Fehlender Zugang landet im Banner. Alles andere laesst den
    /// letzten Stand stehen, statt eine Karte bei jedem Wackler zu leeren.
    private static func take<T>(_ result: Result<T, Error>, previous: T?, backend: Backend,
                                problems: inout [Backend]) -> T? {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            if case APIError.notAuthorised = error {
                if !problems.contains(backend) { problems.append(backend) }
                return nil
            }
            if case APIError.http(404, _) = error { return nil }
            return previous
        }
    }
}
