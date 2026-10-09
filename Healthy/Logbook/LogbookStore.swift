import Foundation

/// Haelt, was die Logbook-Seite zeigt: Verhaltensweisen, den gewaehlten Tag
/// samt Eingabe und die Effekte. Gerechnet wird im Weight Tracker; hier wird
/// eingetragen und gezeigt.
@MainActor
@Observable
final class LogbookStore {

    private let api = LogbookAPI()

    private(set) var overview: LogbookOverview?
    private(set) var insights: LogbookInsights?
    /// Der Zeitraum der Effekte in Tagen (30, 90, 180, 365).
    private(set) var period = LogbookAPI.defaultPeriod

    /// Der Tag der Eingabe - von gestern bis heute−14, Vorgabe gestern.
    private(set) var day = CalendarDate.today().adding(days: -1)
    /// Was fuer diesen Tag angetippt ist, je Verhaltensweise.
    var entries: [String: LogbookEntry] = [:]
    /// Tage, deren Speichern im Postausgang wartet.
    private(set) var queued: [CalendarDate: [String: Double]] = LogbookMemory.load()

    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var error: String?
    private(set) var accessProblem = false

    enum DayState { case open, saved, queued }

    /// Gespeichert (Haken), im Postausgang (Uhr) oder offen.
    var dayState: DayState {
        if queued[day] != nil { return .queued }
        return overview?.day(day) != nil ? .saved : .open
    }

    /// Gestern - der juengste Tag der Eingabe. Heute gehoert noch nicht dazu:
    /// eingetragen wird, was der Tag war, wenn er vorbei ist.
    var latestDay: CalendarDate { today.adding(days: -1) }
    /// Der aelteste Tag, den der Dienst noch annimmt.
    var earliestDay: CalendarDate { today.adding(days: -(overview?.backfillDays ?? 14)) }

    private var today: CalendarDate { CalendarDate.today() }

    /// Ob gespeichert werden kann: jede angetippte Menge muss eine Menge sein.
    var canSave: Bool {
        guard let overview, !overview.active.isEmpty, !isSaving else { return false }
        return LogbookDraft.values(entries, behaviors: overview.active) != nil
    }

    // MARK: - Laden

    func load() async {
        isLoading = true
        defer { isLoading = false }
        #if DEBUG
        if DashboardDemo.isOn {
            overview = overview ?? DashboardDemo.logbookOverview()
            insights = DashboardDemo.logbookInsights(days: period)
            show(day)
            return
        }
        #endif
        // Ist der Postausgang leer, wartet kein Tag mehr.
        if await Outbox.shared.count == 0 {
            LogbookMemory.clear()
        }
        queued = LogbookMemory.load()
        do {
            overview = try await api.overview()
            clearError()
        } catch {
            report(error)
        }
        show(day)
        await loadInsights()
    }

    /// Faellt das aus, fehlen nur die Effekte - die Eingabe geht weiter.
    func loadInsights() async {
        #if DEBUG
        if DashboardDemo.isOn {
            insights = DashboardDemo.logbookInsights(days: period)
            return
        }
        #endif
        if let fresh = try? await api.insights(days: period) {
            insights = fresh
        }
    }

    func select(period: Int) async {
        self.period = period
        await loadInsights()
    }

    // MARK: - Tag

    /// Zeigt einen Tag: wie er gespeichert ist (oder im Postausgang wartet),
    /// sonst alles aus.
    func show(_ date: CalendarDate) {
        day = min(max(date, earliestDay), latestDay)
        guard let overview else {
            entries = [:]
            return
        }
        entries = LogbookDraft.entries(for: overview.active,
                                       values: queued[day] ?? overview.day(day)?.values)
    }

    func step(_ days: Int) {
        show(day.adding(days: days))
    }

    /// Speichert den Tag. Ohne Netz in den Postausgang - das zeigt die Uhr.
    func save() async {
        guard let overview, let values = LogbookDraft.values(entries, behaviors: overview.active) else { return }
        isSaving = true
        defer { isSaving = false }
        let date = day
        #if DEBUG
        if DashboardDemo.isOn {
            store(LogbookDay(date: date, savedAt: Date(), values: values))
            return
        }
        #endif
        do {
            store(try await api.saveDay(date, values: values))
            clearError()
        } catch APIError.queued {
            LogbookMemory.remember(date, values: values)
            queued = LogbookMemory.load()
            clearError()
        } catch {
            report(error)
            return
        }
        if let current = self.overview { await LogbookReminder.schedule(current) }
    }

    /// Uebernimmt den gespeicherten Tag in den Stand, ohne neu zu laden.
    private func store(_ saved: LogbookDay) {
        guard let overview else { return }
        let days = overview.days.filter { $0.date != saved.date } + [saved]
        self.overview = LogbookOverview(behaviors: overview.behaviors, backfillDays: overview.backfillDays,
                                        backfillFrom: overview.backfillFrom, today: overview.today,
                                        days: days.sorted { $0.date < $1.date })
    }

    // MARK: - Verhaltensweisen

    /// Legt eine an. Die erste fragt nach der Erlaubnis fuer die Erinnerung -
    /// jetzt ist klar, wofuer.
    func addBehavior(name: String, unit: String?) async -> Bool {
        let hadNone = overview?.active.isEmpty ?? true
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        let cleanUnit = unit?.trimmingCharacters(in: .whitespaces)
        let finalUnit = cleanUnit?.isEmpty == false ? cleanUnit : nil
        #if DEBUG
        if DashboardDemo.isOn {
            let behavior = Behavior(id: "b-demo-\(UUID().uuidString.prefix(8).lowercased())", name: cleanName,
                                    unit: finalUnit, createdAt: Date(), archived: false)
            return demoChange { $0 + [behavior] }
        }
        #endif
        let saved = await change {
            let behavior = try await self.api.addBehavior(name: cleanName, unit: finalUnit)
            return { $0 + [behavior] }
        }
        if saved, hadNone {
            await Notifications.requestPermission()
            if let overview { await LogbookReminder.schedule(overview) }
        }
        return saved
    }

    func rename(_ behavior: Behavior, to name: String) async -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        #if DEBUG
        if DashboardDemo.isOn {
            return demoChange { $0.map { $0.id == behavior.id ? Behavior(id: $0.id, name: cleanName, unit: $0.unit,
                                                                         createdAt: $0.createdAt,
                                                                         archived: $0.archived) : $0 } }
        }
        #endif
        return await change {
            let updated = try await self.api.updateBehavior(id: behavior.id, name: cleanName)
            return { $0.map { $0.id == updated.id ? updated : $0 } }
        }
    }

    /// Archivierte zaehlen nicht mehr beim Speichern, ihre Werte bleiben -
    /// wer nur nicht mehr eintragen will, verliert so nichts.
    func setArchived(_ behavior: Behavior, _ archived: Bool) async -> Bool {
        #if DEBUG
        if DashboardDemo.isOn {
            return demoChange { $0.map { $0.id == behavior.id ? Behavior(id: $0.id, name: $0.name, unit: $0.unit,
                                                                         createdAt: $0.createdAt,
                                                                         archived: archived) : $0 } }
        }
        #endif
        return await change {
            let updated = try await self.api.updateBehavior(id: behavior.id, archived: archived)
            return { $0.map { $0.id == updated.id ? updated : $0 } }
        }
    }

    /// Loeschen nimmt die Werte an allen Tagen mit.
    func delete(_ behavior: Behavior) async -> Bool {
        #if DEBUG
        if DashboardDemo.isOn {
            return demoChange { $0.filter { $0.id != behavior.id } }
        }
        #endif
        return await change {
            try await self.api.deleteBehavior(id: behavior.id)
            return { $0.filter { $0.id != behavior.id } }
        }
    }

    /// Eine Aenderung an den Verhaltensweisen: erst beim Dienst, dann im
    /// Stand, dann die Eingabe des Tages neu - eine neue steht dort aus, eine
    /// archivierte verschwindet. Die Effekte rechnet der Dienst danach neu.
    private func change(_ call: () async throws -> ([Behavior]) -> [Behavior]) async -> Bool {
        guard overview != nil else { return false }
        let apply: ([Behavior]) -> [Behavior]
        do {
            apply = try await call()
            clearError()
        } catch {
            report(error)
            return false
        }
        guard let current = overview else { return false }
        replace(current, behaviors: apply(current.behaviors))
        await loadInsights()
        return true
    }

    #if DEBUG
    /// Im Vorfuehrmodus nur im Speicher - nichts davon erreicht den Dienst.
    private func demoChange(_ apply: ([Behavior]) -> [Behavior]) -> Bool {
        guard let current = overview else { return false }
        replace(current, behaviors: apply(current.behaviors))
        return true
    }
    #endif

    private func replace(_ current: LogbookOverview, behaviors: [Behavior]) {
        overview = LogbookOverview(behaviors: behaviors, backfillDays: current.backfillDays,
                                   backfillFrom: current.backfillFrom, today: current.today, days: current.days)
        // Was schon angetippt ist, bleibt angetippt.
        let previous = entries
        show(day)
        for (id, entry) in previous where entries[id] != nil { entries[id] = entry }
    }

    // MARK: - Fehler

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
