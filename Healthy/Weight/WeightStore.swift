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
    private let energyApi = EnergyAPI()

    private(set) var summary: WeightSummary?
    private(set) var points: [WeightPoint] = []
    /// Zeitraeume (Baender) und einzelne Tage (Linien) im Diagramm.
    private(set) var highlights: [Highlight] = []
    /// Der Chip „Zeitraeume" unter dem Diagramm. Gilt fuer jeden Zeitraum,
    /// anders als die Serien - Urlaub ist in 30 Tagen derselbe wie in einem Jahr.
    var showsHighlights = HighlightVisibility.load() {
        didSet { HighlightVisibility.save(showsHighlights) }
    }

    /// Was das Diagramm zeichnet. Die Liste im Blatt „Zeitraeume" bleibt
    /// vollstaendig, auch wenn hier nichts steht.
    var chartHighlights: [Highlight] {
        showsHighlights ? highlights : []
    }
    /// Die vollstaendige, geordnete Liste. Frueher standen hier nur die
    /// Zusaetze und vier Kacheln waren fest verdrahtet.
    private(set) var widgets: [WeightWidget] = []
    /// Die Tageskalorien zum sichtbaren Zeitraum - dieselbe Zusammenschau wie
    /// in der Weboberflaeche. Faellt der Kalorienzaehler aus, fehlt nur diese
    /// Kurve; das Gewicht steht davon unabhaengig da.
    private(set) var kcalByDay: [DayValue] = []
    /// Das 7-Tage-Mittel dazu, fertig gerechnet vom Kalorienzaehler.
    private(set) var kcalAverage: [DayAverage] = []
    private(set) var kcalTarget: Double?
    /// Fuer die drei Energie-Kacheln. Wie die kcal Beiwerk: ohne sie zeigen
    /// diese Kacheln „–", der Tab ist deshalb nicht kaputt.
    private(set) var energySummary: EnergySummary?
    /// „Verbrauch ⌀" zum sichtbaren Zeitraum - hier nur angeboten.
    private(set) var expenditureAverage: [DayAverage] = []
    /// „Defizit ⌀" ebenso - aus denselben Energietagen.
    private(set) var deficitAverage: [DayAverage] = []

    private(set) var stepsToday: Int?
    /// Bis das Backend geantwortet hat. Ohne Vorgabe zeigte die Karte im
    /// ersten Bild „von 0".
    private(set) var stepsGoal = 10_000

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
    /// Die sichtbaren Serien, je Sichtweise gemerkt: „Alles" hat ein eigenes
    /// Angebot (30-Tage- statt 7-Tage-Mittel) und darum eine eigene Auswahl -
    /// sonst tauschte jeder Wechsel des Zeitraums die Haken aus.
    private var windowVisible: Set<WeightSeries> = WeightStore.initialVisible(WeightSeries.defaultVisible)
    private var allTimeVisible: Set<WeightSeries> = WeightStore.initialVisible(WeightRange.allTime.defaultVisible)

    /// Im Debug-Build zuschaltbar (`COCKPIT_SERIES=deficit,expenditure`):
    /// „Defizit ⌀" und „Verbrauch ⌀" sind hier nur angeboten, und tippen kann
    /// der Simulator nicht.
    private static func initialVisible(_ defaults: Set<WeightSeries>) -> Set<WeightSeries> {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["COCKPIT_SERIES"] {
            return defaults.union(raw.split(separator: ",").compactMap { WeightSeries(rawValue: String($0)) })
        }
        #endif
        return defaults
    }

    var visibleSeries: Set<WeightSeries> {
        get { range == .allTime ? allTimeVisible : windowVisible }
        set {
            if range == .allTime { allTimeVisible = newValue } else { windowVisible = newValue }
        }
    }

    /// Kacheln, die man noch dazunehmen kann.
    var addableWidgets: [WeightWidget] {
        WeightWidget.allCases.filter { !shownWidgets.contains($0) }
    }

    /// Was oben steht: die gespeicherte Liste. Im Vorfuehrmodus
    /// (`COCKPIT_DASHBOARD_DEMO`) dazu die drei Energie-Kacheln, ohne sie zu
    /// speichern - sonst waeren sie in keinem Bild zu sehen, ohne Felix'
    /// Auswahl beim Dienst zu aendern.
    var shownWidgets: [WeightWidget] {
        #if DEBUG
        if DashboardDemo.isOn {
            return widgets + [WeightWidget.deficit7, .expenditure7, .calibration].filter { !widgets.contains($0) }
        }
        #endif
        return widgets
    }

    /// Was eine Kachel sehen darf.
    func tileInput(_ summary: WeightSummary) -> TileInput {
        TileInput(weight: summary, energy: energySummary)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        #if DEBUG
        if DashboardDemo.isOn {
            showDemo()
            return
        }
        #endif
        do {
            // Vier unabhaengige Abfragen - nacheinander waere hier nur langsamer.
            async let summary = api.summary()
            async let points = api.points(range)
            async let highlights = api.highlights()
            async let dashboard = api.dashboard()

            self.summary = try await summary
            self.points = Self.trim(try await points, to: range)
            self.highlights = try await highlights
            self.widgets = Self.sanitize(try await dashboard.widgets)
            clearError()
        } catch {
            report(error)
        }
        await loadEnergySummary()
        await loadKcal()
        await loadSteps()
    }

    /// Wie die kcal: faellt das aus (aelterer Dienst ohne Energie, keine Uhr),
    /// zeigen nur die drei Kacheln „–".
    private func loadEnergySummary() async {
        energySummary = try? await energyApi.summary()
    }

    /// Wie die kcal: faellt das hier aus, fehlt die Karte - den Gewicht-Tab
    /// deshalb als kaputt zu melden waere falsch.
    private func loadSteps() async {
        if let goal = try? await api.stepsGoal() { stepsGoal = goal.stepsPerDay }
        // Erst Health: das ist die laufende Zahl. Der Bestand auf dem Server
        // ist hoechstens so aktuell wie der letzte Abgleich - er ist der
        // Rueckfall, nicht die Quelle.
        if let live = await HealthSync.shared.todaySteps() {
            stepsToday = live
        } else {
            let heute = CalendarDate.today()
            stepsToday = (try? await api.steps(from: heute, to: heute))?.first?.steps
        }
    }

    func updateStepsGoal(_ stepsPerDay: Int) async -> Bool {
        guard !isDemo else { return true }
        do {
            stepsGoal = try await api.updateStepsGoal(stepsPerDay).stepsPerDay
            clearError()
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Die kcal sind Beiwerk: ist der Kalorienzaehler nicht erreichbar, fehlt
    /// die Kurve - der Gewicht-Tab deshalb als kaputt zu melden waere falsch.
    private func loadKcal() async {
        guard let first = points.first?.date, let last = points.last?.date else {
            kcalByDay = []
            kcalAverage = []
            return
        }
        async let totals = foodApi.daily(from: first, to: last)
        async let averages = foodApi.dailyAverage(from: first, to: last)
        kcalByDay = ((try? await totals) ?? []).map { DayValue(date: $0.date, value: $0.consumed.kcal) }
        kcalAverage = (try? await averages) ?? []
        if kcalTarget == nil {
            kcalTarget = (try? await foodApi.targets())?.kcal
        }
        await loadExpenditure(from: first, to: last)
    }

    /// Verbrauchs- und Defizitmittel zum Zeitraum. Nie nach heute (den Vorgriff der
    /// Zielkurve kennt der Dienst nicht), hoechstens 4.000 Tage - „Alles"
    /// reicht bis 2018 zurueck.
    private func loadExpenditure(from first: CalendarDate, to last: CalendarDate) async {
        let end = min(last, CalendarDate.today())
        guard first <= end else {
            expenditureAverage = []
            deficitAverage = []
            return
        }
        // Still: ohne Uhr, mit einem aelteren Dienst oder ohne Netz fehlen
        // nur die beiden Kurven.
        let start = EnergyAPI.clampedStart(from: first, to: end)
        let days = (try? await energyApi.days(from: start, to: end)) ?? []
        expenditureAverage = days.compactMap(\.expenditureAverage)
        deficitAverage = days.compactMap(\.deficitAverage)
    }

    func select(_ range: WeightRange) async {
        self.range = range
        // Serien, die es in diesem Zeitraum nicht gibt, abwaehlen - sonst
        // bliebe ein Haken stehen, zu dem keine Linie gehoert.
        visibleSeries.formIntersection(range.availableSeries)
        #if DEBUG
        if DashboardDemo.isOn {
            showDemoSeries()
            return
        }
        #endif
        do {
            points = Self.trim(try await api.points(range), to: range)
            clearError()
        } catch {
            report(error)
        }
        await loadKcal()
    }

    func add(date: CalendarDate, weightKg: Double) async -> Bool {
        guard !isDemo else { return true }
        do {
            summary = try await api.add(date: date, weightKg: weightKg, queueWhenOffline: true)
            points = Self.trim(try await api.points(range), to: range)
            clearError()
            return true
        } catch APIError.queued {
            // Liegt im Postausgang - das Blatt darf zugehen. Die Kacheln
            // zeigen den alten Stand weiter; die Leiste sagt, dass etwas wartet.
            clearError()
            return true
        } catch {
            report(error)
            return false
        }
    }

    func updateTarget(_ weightKg: Double) async -> Bool {
        guard !isDemo else { return true }
        do {
            summary = try await api.updateTarget(weightKg)
            // Die Zielkurve haengt am Ziel: die Punkte muessen mit.
            points = Self.trim(try await api.points(range), to: range)
            clearError()
            return true
        } catch {
            report(error)
            return false
        }
    }

    func addHighlight(_ request: NewHighlightRequest) async -> Bool {
        guard !isDemo else { return true }
        do {
            highlights = try await api.addHighlight(request)
            clearError()
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// Erst aus der Liste nehmen, dann loeschen: das Wischen soll sich sofort
    /// anfuehlen. Schlaegt es fehl, kommt der Eintrag zurueck, und die
    /// Meldung sagt, warum.
    func removeHighlight(_ highlight: Highlight) async {
        guard !isDemo else { return }
        let previous = highlights
        highlights.removeAll { $0.id == highlight.id }
        do {
            highlights = try await api.deleteHighlight(id: highlight.id)
            clearError()
        } catch {
            highlights = previous
            report(error)
        }
    }

    func addWidget(_ widget: WeightWidget) async {
        guard !widgets.contains(widget) else { return }
        await saveWidgets(widgets + [widget])
    }

    /// Jede Kachel laesst sich entfernen, auch die vier frueher festen - und
    /// auch alle auf einmal. Eine leere Anzeige ist ein gueltiger Zustand;
    /// hinzufuegen geht ueber das Menue, das immer da ist.
    func removeWidget(_ widget: WeightWidget) async {
        await saveWidgets(widgets.filter { $0 != widget })
    }

    private func saveWidgets(_ next: [WeightWidget]) async {
        guard !isDemo else { return }
        // Erst anzeigen, dann speichern: das Umsortieren soll sich sofort
        // anfuehlen, und schlaegt das Speichern fehl, sagt es die Meldung.
        let previous = widgets
        widgets = next
        do {
            let saved = try await api.saveDashboard(next.map(\.rawValue))
            widgets = Self.sanitize(saved.widgets)
            clearError()
        } catch {
            widgets = previous
            report(error)
        }
    }

    /// Schneidet eine Reihe auf das Fenster des Zeitraums zu.
    ///
    /// Nur fuer Zeitraeume ohne eigenen Endpunkt: „3 Jahre" holt die volle
    /// Reihe und behaelt davon die letzten 1095 Tage plus eine Woche Vorgriff -
    /// dieselbe Form, die der Jahres-Endpunkt serverseitig liefert.
    static func trim(_ points: [WeightPoint], to range: WeightRange) -> [WeightPoint] {
        guard let windowDays = range.windowDays else { return points }
        let today = CalendarDate.today()
        let calendar = Calendar(identifier: .gregorian)
        guard let from = calendar.date(byAdding: .day, value: -windowDays, to: today.startOfDay()),
              let to = calendar.date(byAdding: .day, value: WeightRange.lookAheadDays,
                                     to: today.startOfDay())
        else { return points }
        return points.filter {
            let day = $0.date.startOfDay()
            return day >= from && day <= to
        }
    }

    /// Nimmt nur bekannte Kacheln an. So fallen Altlasten aus
    /// `dashboard.json` (umbenannt, entfernt, von Hand eingetragener Unsinn)
    /// beim naechsten Speichern von selbst raus.
    private static func sanitize(_ keys: [String]) -> [WeightWidget] {
        var seen = Set<WeightWidget>()
        return keys.compactMap { key in
            guard let widget = WeightWidget(rawValue: key),
                  seen.insert(widget).inserted else { return nil }
            return widget
        }
    }

    /// Im Vorfuehrmodus (`COCKPIT_DASHBOARD_DEMO`) ist der Tab erfunden, und
    /// nichts geht an den Dienst - auch Speichern nicht.
    private var isDemo: Bool {
        #if DEBUG
        DashboardDemo.isOn
        #else
        false
        #endif
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

#if DEBUG
extension WeightStore {

    /// Der ganze Tab erfunden: Gewicht, Kacheln, kcal, Energie, Schritte. Nur
    /// im Speicher - kein Bild zeigt so echte Daten, obwohl `run-simulator.sh`
    /// die echten Token mitgibt.
    fileprivate func showDemo() {
        summary = DashboardDemo.weightSummary()
        highlights = []
        // Eine Kachel zu den drei der Energie (`shownWidgets`): so steht das
        // Diagramm noch ganz im ersten Bildschirm - scrollen kann simctl nicht.
        widgets = [.current]
        energySummary = DashboardDemo.energySummary()
        stepsGoal = 10_000
        stepsToday = DashboardDemo.steps
        showDemoSeries()
    }

    /// Die Reihen des gewaehlten Zeitraums - kcal und Energie passen zueinander,
    /// so stimmen Flaeche und „Defizit ⌀" ueberein.
    fileprivate func showDemoSeries() {
        points = Self.trim(DashboardDemo.weightPoints(range), to: range)
        clearError()
        guard let first = points.first?.date, let last = points.last?.date else { return }
        kcalByDay = DashboardDemo.foodTotals(from: first, to: last)
            .map { DayValue(date: $0.date, value: $0.consumed.kcal) }
        kcalAverage = DashboardDemo.foodAverages(from: first, to: last)
        kcalTarget = DashboardDemo.kcalTarget
        let days = DashboardDemo.energyDays(from: first, to: last)
        expenditureAverage = days.compactMap(\.expenditureAverage)
        deficitAverage = days.compactMap(\.deficitAverage)
    }
}
#endif
