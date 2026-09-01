import Foundation

/// Wie eine Schnellerfassung ausgegangen ist. `Result` scheidet aus, weil
/// dessen Fehlerfall ein `Error` sein muss - hier ist es schlicht ein Satz,
/// den der Server oder die Wartezeit geliefert hat.
enum QuickCaptureOutcome: Sendable {
    case ready(QuickCapturePreview)
    case failed(String)
}

@MainActor
@Observable
final class FoodStore {

    private let api = FoodAPI()
    private let weightApi = WeightAPI()

    private(set) var date: CalendarDate = FoodStore.initialDate
    private(set) var day: DaySummary?
    private(set) var dishes: [Dish] = []
    private(set) var history: [DayTotal] = []
    /// Die Gewichtskurve unter den kcal - dieselbe Zusammenschau wie in der
    /// Weboberflaeche. In der App braucht es dafuer kein CORS: die
    /// Same-Origin-Policy gilt nur im Browser.
    private(set) var weightPoints: [WeightPoint] = []
    /// Die Schnellerfassung ist serverseitig abschaltbar. Dann wird sie gar
    /// nicht erst angeboten, statt einen Knopf zu zeigen, der scheitert.
    private(set) var quickCaptureAvailable = false

    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var accessProblem = false

    var historyDays = 30
    /// Das Fenster, das der Verlauf zeigt - unabhaengig davon, fuer welche
    /// Tage es ueberhaupt Eintraege gibt. Das Diagramm braucht das: leitete es
    /// seine Achse aus den Daten ab, waere sie bei zwei erfassten Tagen zwei
    /// Tage breit, und der Zeitraum-Umschalter aenderte sichtbar nichts.
    private(set) var historyFrom: CalendarDate = .today()
    private(set) var historyTo: CalendarDate = .today()

    /// Mit welchem Tag die App aufmacht. Im Debug-Build vorgebbar, damit sich
    /// auch ein leerer Tag ansehen laesst - auf einem vollen Tag liegt der
    /// Verlauf unterhalb des Bildschirms.
    private static var initialDate: CalendarDate {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["COCKPIT_DAY"],
           let day = CalendarDate(iso: raw) {
            return day
        }
        #endif
        return .today()
    }

    var isToday: Bool { date == CalendarDate.today() }

    /// Eintraege des Tages nach Mahlzeiten.
    ///
    /// Die vier Mahlzeiten stehen immer da, auch leer - jede hat ihren eigenen
    /// „+", der das Eingabeblatt schon auf sie stellt. Der Abschnitt „Ohne
    /// Zuordnung" taucht nur auf, solange es Eintraege aus der Zeit vor der
    /// Aufteilung gibt, und verschwindet danach von selbst.
    var mealSections: [MealSection] {
        guard let day else { return [] }
        var sections = Meal.allCases.map { meal in
            MealSection(meal: meal, entries: day.entries.filter { $0.meal == meal })
        }
        let unassigned = day.entries.filter { $0.meal == nil }
        if !unassigned.isEmpty {
            sections.append(MealSection(meal: nil, entries: unassigned))
        }
        return sections
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let day = api.day(date)
            async let dishes = api.dishes()
            async let features = api.features()
            self.day = try await day
            self.dishes = try await dishes.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            self.quickCaptureAvailable = try await features.quickCapture
            clearError()
        } catch {
            report(error)
        }
        await loadHistory()
    }

    func loadHistory() async {
        let to = CalendarDate.today()
        guard let fromDate = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: -(historyDays - 1), to: to.startOfDay())
        else { return }
        let parts = Calendar(identifier: .gregorian)
            .dateComponents([.year, .month, .day], from: fromDate)
        let from = CalendarDate(year: parts.year ?? to.year,
                                month: parts.month ?? to.month,
                                day: parts.day ?? to.day)
        historyFrom = from
        historyTo = to
        do {
            history = try await api.daily(from: from, to: to)
        } catch {
            // Der Verlauf ist Beiwerk: faellt er aus, soll deshalb nicht der
            // ganze Tag als kaputt dastehen.
            history = []
        }
        // Dasselbe fuer die Gewichtskurve - fehlt sie, fehlt nur sie.
        weightPoints = (try? await weightApi.points(.last90)) ?? []
    }

    func show(_ date: CalendarDate) async {
        self.date = date
        do {
            day = try await api.day(date)
            clearError()
        } catch {
            report(error)
        }
    }

    func step(days: Int) async {
        guard let shifted = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: days, to: date.startOfDay()) else { return }
        let parts = Calendar(identifier: .gregorian)
            .dateComponents([.year, .month, .day], from: shifted)
        await show(CalendarDate(year: parts.year ?? date.year,
                                month: parts.month ?? date.month,
                                day: parts.day ?? date.day))
    }

    func addEntry(dishId: String?, dish: DishRequest?, grams: Double, meal: Meal?) async -> Bool {
        do {
            day = try await api.addEntry(NewEntryRequest(date: date, dishId: dishId,
                                                         dish: dish, grams: grams, meal: meal))
            // Ein neu angelegtes Gericht gehoert sofort in die Merkliste.
            if dish != nil { dishes = try await api.dishes()
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending } }
            clearError()
            await loadHistory()
            return true
        } catch {
            report(error)
            return false
        }
    }

    func deleteEntry(_ entry: FoodEntry) async {
        do {
            day = try await api.deleteEntry(id: entry.id)
            clearError()
            await loadHistory()
        } catch {
            report(error)
        }
    }

    func createDish(_ request: DishRequest) async -> Bool {
        do {
            let dish = try await api.createDish(request)
            dishes = (dishes + [dish])
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            clearError()
            return true
        } catch {
            report(error)
            return false
        }
    }

    func updateDish(id: String, _ request: DishRequest) async -> Bool {
        do {
            let updated = try await api.updateDish(id: id, request)
            dishes = dishes.map { $0.id == id ? updated : $0 }
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            clearError()
            return true
        } catch {
            report(error)
            return false
        }
    }

    func deleteDish(_ dish: Dish) async {
        do {
            try await api.deleteDish(id: dish.id)
            dishes.removeAll { $0.id == dish.id }
            clearError()
        } catch {
            report(error)
        }
    }

    func updateTargets(_ request: TargetsRequest) async -> Bool {
        do {
            _ = try await api.updateTargets(request)
            // Die Ziele stecken in der Tagesantwort - die muss also neu geholt
            // werden, sonst zeigen die Tachos weiter die alten Marken.
            day = try await api.day(date)
            clearError()
            return true
        } catch {
            report(error)
            return false
        }
    }

    // MARK: - Schnellerfassung

    /// Schickt den Text weg und wartet, bis der Server fertig ist.
    ///
    /// Der Auftrag laeuft als Claude-Session und dauert bis zu einer Minute;
    /// gefragt wird alle zwei Sekunden nach. Nach `timeout` wird aufgegeben -
    /// serverseitig ist bei 180 s Schluss, danach kommt ohnehin nichts mehr.
    func runQuickCapture(text: String, meal: Meal?,
                         timeout: TimeInterval = 190) async -> QuickCaptureOutcome {
        do {
            var job = try await api.startQuickCapture(
                QuickCaptureRequest(date: date, text: text, meal: meal))
            let deadline = Date().addingTimeInterval(timeout)
            while job.isRunning {
                if Date() > deadline {
                    return .failed("Die Auswertung hat zu lange gedauert.")
                }
                try await Task.sleep(for: .seconds(2))
                job = try await api.quickCaptureStatus(id: job.id)
            }
            if let preview = job.preview, job.status == QuickCaptureJob.done {
                return .ready(preview)
            }
            return .failed(job.error ?? "Die Auswertung ist fehlgeschlagen.")
        } catch {
            report(error)
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Fehler

    private func clearError() {
        error = nil
        accessProblem = false
    }

    private func report(_ error: Error) {
        if case APIError.notAuthorised = error {
            accessProblem = true
            self.error = "Kein Zugang zum Kalorienzähler."
        } else {
            accessProblem = false
            self.error = error.localizedDescription
        }
    }
}
