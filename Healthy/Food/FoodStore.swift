import Foundation
import UIKit
import WidgetKit

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
    /// Welche Gewichtskurven ueber dem Verlauf liegen - Mittel, Tageswerte,
    /// beides oder nichts. Standardmaessig **leer**: sie beantworten eine
    /// andere Frage als "wie viel habe ich gegessen", und wer sie sehen will,
    /// holt sie sich dazu.
    var weightOverlay: Set<WeightSeries> = []
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
            // Anstoss, keine Datenuebergabe: die Kachel holt sich selbst, was
            // sie braucht. Ein Reload aus der laufenden App zaehlt nicht gegen
            // das Aktualisierungsbudget von WidgetKit - das deckt den
            // haeufigsten Fall zum Nulltarif ab.
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.calories)
            return true
        } catch APIError.queued {
            // Liegt im Postausgang. Der Tag zeigt weiter den alten Stand -
            // nachrechnen tut hier nichts, dafuer ist der Dienst da.
            clearError()
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Berichtigt einen Eintrag. Wandert er auf einen anderen Tag, bleibt die
    /// Ansicht auf dem aktuellen - sonst spraenge sie dem Eintrag hinterher.
    func updateEntry(_ entry: FoodEntry, grams: Double, meal: Meal?, date: CalendarDate?) async -> Bool {
        do {
            let updatedDay = try await api.updateEntry(id: entry.id, grams: grams, meal: meal, date: date)
            if updatedDay.date == self.date {
                day = updatedDay
            } else {
                day = try await api.day(self.date)
            }
            clearError()
            await loadHistory()
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.calories)
            return true
        } catch APIError.queued {
            clearError()
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
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.calories)
        } catch APIError.queued {
            clearError()
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
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.calories)
            return true
        } catch {
            report(error)
            return false
        }
    }

    // MARK: - Schnellerfassung

    /// Ein laufender Auftrag. Er gehoert dem Store und nicht dem Blatt -
    /// sonst waere er mit dem Zuklappen weg, und genau das soll er ueberleben.
    struct RunningCapture: Sendable, Equatable {
        let id: String
        let text: String
        let meal: Meal?
        let startedAt: Date
    }

    private(set) var running: RunningCapture?
    /// Fertiger Vorschlag, der noch bestaetigt werden will.
    private(set) var pendingPreview: QuickCapturePreview?
    private(set) var captureError: String?
    private var captureTask: Task<Void, Never>?

    /// Merkt sich den Auftrag ueber einen App-Neustart hinweg. Der Server
    /// rechnet weiter, auch wenn die App weggeraeumt wird - ohne die Kennung
    /// waere das Ergebnis danach nicht mehr abholbar.
    private static let runningJobKey = "food.quickCapture.jobId"

    /// Schickt den Text weg und kehrt sofort zurueck. Das Nachfragen laeuft
    /// im Hintergrund; ist der Vorschlag da, meldet sich die App.
    func startQuickCapture(text: String, meal: Meal?) {
        captureTask?.cancel()
        captureError = nil
        pendingPreview = nil
        let day = date
        captureTask = Task { [weak self] in
            guard let self else { return }
            await Notifications.requestPermission()
            do {
                let job = try await api.startQuickCapture(
                    QuickCaptureRequest(date: day, text: text, meal: meal))
                running = RunningCapture(id: job.id, text: text, meal: meal,
                                         startedAt: Date())
                UserDefaults.standard.set(job.id, forKey: Self.runningJobKey)
                await follow(job)
            } catch {
                finish(with: error.localizedDescription)
            }
        }
    }

    /// Nimmt einen Auftrag wieder auf, der beim letzten Start noch lief.
    func resumeQuickCaptureIfNeeded() async {
        guard running == nil, pendingPreview == nil,
              let id = UserDefaults.standard.string(forKey: Self.runningJobKey),
              let job = try? await api.quickCaptureStatus(id: id) else { return }
        running = RunningCapture(id: id, text: "", meal: nil, startedAt: Date())
        await follow(job)
    }

    /// Fragt im Zwei-Sekunden-Takt nach, bis der Server fertig ist.
    private func follow(_ job: QuickCaptureJob) async {
        var current = job
        // Serverseitig ist bei 180 s Schluss; danach kommt nichts mehr.
        let deadline = Date().addingTimeInterval(190)
        while current.isRunning {
            if Date() > deadline {
                finish(with: "Die Auswertung hat zu lange gedauert.")
                return
            }
            do {
                try await Task.sleep(for: .seconds(2))
                current = try await api.quickCaptureStatus(id: current.id)
            } catch {
                if Task.isCancelled { return }
                finish(with: error.localizedDescription)
                return
            }
        }
        if let preview = current.preview, current.status == QuickCaptureJob.done {
            await finish(with: preview)
        } else {
            finish(with: current.error ?? "Die Auswertung ist fehlgeschlagen.")
        }
    }

    private func finish(with preview: QuickCapturePreview) async {
        running = nil
        pendingPreview = preview
        UserDefaults.standard.removeObject(forKey: Self.runningJobKey)
        // Ist die App im Bild, sieht man das Blatt ohnehin aufgehen - eine
        // Benachrichtigung obendrauf waere Laerm.
        if UIApplication.shared.applicationState != .active {
            await Notifications.post(title: "Vorschlag ist fertig",
                                     body: "\(preview.name) – antippen zum Übernehmen.")
        }
    }

    private func finish(with message: String) {
        running = nil
        captureError = message
        UserDefaults.standard.removeObject(forKey: Self.runningJobKey)
    }

    func discardPreview() {
        pendingPreview = nil
    }

    func clearCaptureError() {
        captureError = nil
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
