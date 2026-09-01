import Foundation

/// Haelt alles, was der Gewicht-Tab anzeigt, und spricht mit dem Backend.
///
/// Bewusst kein Zwischenspeicher auf der Platte: die Daten sind winzig und
/// kommen in Millisekunden - ein Cache waere ein zweiter Stand mit eigener
/// Konfliktlogik (siehe docs/ENTSCHEIDUNGEN.md).
@MainActor
@Observable
final class WeightStore {

    private let api = WeightAPI()
    private let foodApi = FoodAPI()

    private(set) var summary: WeightSummary?
    private(set) var points: [WeightPoint] = []
    private(set) var vacations: [Vacation] = []
    private(set) var extraWidgets: [WeightWidget] = []
    /// Die Tageskalorien zum sichtbaren Zeitraum - dieselbe Zusammenschau wie
    /// in der Weboberflaeche. Faellt der Kalorienzaehler aus, fehlt nur diese
    /// Kurve; das Gewicht steht davon unabhaengig da.
    private(set) var kcalByDay: [DayValue] = []
    private(set) var kcalTarget: Double?

    private(set) var isLoading = false
    private(set) var error: String?
    /// Zugangsproblem statt beliebigem Fehler: dann hilft ein Hinweis auf den
    /// Zugang-Tab mehr als eine Fehlermeldung.
    private(set) var accessProblem = false

    var range: WeightRange = WeightStore.initialRange

    /// Womit der Gewicht-Tab aufmacht. Im Debug-Build vorgebbar, damit sich
    /// jeder Zeitraum aufnehmen laesst - tippen kann der Simulator nicht.
    private static var initialRange: WeightRange {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["COCKPIT_RANGE"],
           let range = WeightRange(rawValue: raw) {
            return range
        }
        #endif
        return .last90
    }
    var visibleSeries: Set<WeightSeries> = WeightSeries.defaultVisible

    /// Alle Kacheln in der Reihenfolge, in der sie erscheinen.
    var widgets: [WeightWidget] { WeightWidget.base + extraWidgets }

    /// Kacheln, die man noch dazunehmen kann.
    var addableWidgets: [WeightWidget] {
        WeightWidget.allCases.filter { !widgets.contains($0) }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // Vier unabhaengige Abfragen - nacheinander waere hier nur langsamer.
            async let summary = api.summary()
            async let points = api.points(range)
            async let vacations = api.vacations()
            async let dashboard = api.dashboard()

            self.summary = try await summary
            self.points = try await points
            self.vacations = try await vacations
            self.extraWidgets = Self.sanitize(try await dashboard.widgets)
            clearError()
        } catch {
            report(error)
        }
        await loadKcal()
    }

    /// Die kcal sind Beiwerk: ist der Kalorienzaehler nicht erreichbar, fehlt
    /// die Kurve - der Gewicht-Tab deshalb als kaputt zu melden waere falsch.
    private func loadKcal() async {
        guard let first = points.first?.date, let last = points.last?.date else {
            kcalByDay = []
            return
        }
        let totals = (try? await foodApi.daily(from: first, to: last)) ?? []
        kcalByDay = totals.map { DayValue(date: $0.date, value: $0.consumed.kcal) }
        if kcalTarget == nil {
            kcalTarget = (try? await foodApi.targets())?.kcal
        }
    }

    func select(_ range: WeightRange) async {
        self.range = range
        // Serien, die es in diesem Zeitraum nicht gibt, abwaehlen - sonst
        // bliebe ein Haken stehen, zu dem keine Linie gehoert.
        visibleSeries.formIntersection(range.availableSeries)
        do {
            points = try await api.points(range)
            clearError()
        } catch {
            report(error)
        }
        await loadKcal()
    }

    func add(date: CalendarDate, weightKg: Double) async -> Bool {
        do {
            summary = try await api.add(date: date, weightKg: weightKg)
            points = try await api.points(range)
            clearError()
            return true
        } catch {
            report(error)
            return false
        }
    }

    func updateTarget(_ weightKg: Double) async -> Bool {
        do {
            summary = try await api.updateTarget(weightKg)
            // Die Zielkurve haengt am Ziel: die Punkte muessen mit.
            points = try await api.points(range)
            clearError()
            return true
        } catch {
            report(error)
            return false
        }
    }

    func addWidget(_ widget: WeightWidget) async {
        guard !widgets.contains(widget) else { return }
        await saveWidgets(extraWidgets + [widget])
    }

    func removeWidget(_ widget: WeightWidget) async {
        guard !WeightWidget.base.contains(widget) else { return }
        await saveWidgets(extraWidgets.filter { $0 != widget })
    }

    private func saveWidgets(_ next: [WeightWidget]) async {
        // Erst anzeigen, dann speichern: das Umsortieren soll sich sofort
        // anfuehlen, und schlaegt das Speichern fehl, sagt es die Meldung.
        let previous = extraWidgets
        extraWidgets = next
        do {
            let saved = try await api.saveDashboard(next.map(\.rawValue))
            extraWidgets = Self.sanitize(saved.widgets)
            clearError()
        } catch {
            extraWidgets = previous
            report(error)
        }
    }

    /// Nimmt nur bekannte Zusatz-Kacheln an. So fallen Altlasten aus
    /// `dashboard.json` (umbenannt, entfernt, von Hand eingetragener Unsinn)
    /// beim naechsten Speichern von selbst raus.
    private static func sanitize(_ keys: [String]) -> [WeightWidget] {
        var seen = Set<WeightWidget>()
        return keys.compactMap { key in
            guard let widget = WeightWidget(rawValue: key),
                  !WeightWidget.base.contains(widget),
                  seen.insert(widget).inserted else { return nil }
            return widget
        }
    }

    private func clearError() {
        error = nil
        accessProblem = false
    }

    private func report(_ error: Error) {
        if case APIError.notAuthorised = error {
            accessProblem = true
            self.error = "Kein Zugang zum Weight Tracker."
        } else {
            accessProblem = false
            self.error = error.localizedDescription
        }
    }
}
