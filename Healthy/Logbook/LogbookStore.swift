import Foundation

/// Das Logbook im Dashboard (Vertrag §4.2): Verhaltensweisen, der gewaehlte Tag
/// und die Effekte. **Jeder Tipp speichert** - es gibt keinen Speichern-Knopf,
/// und was nicht beantwortet ist, bleibt offen statt „nein“.
///
/// Eine Zeile zeigt den Stand des Dienstes, darueber was in der Warteschlange
/// wartet (`PendingChanges`, Fall `.logbook`), darueber was am Zaehler gerade
/// getippt wird (`LogbookDays.value`). Ohne Netz steht ein Wert mit Uhr da und
/// geht spaeter raus; lehnt der Dienst ab, springt die Zeile auf seinen Stand
/// zurueck, und eine Meldung nennt Verhalten und Tag (`PendingSync`).
@MainActor
@Observable
final class LogbookStore {

    private let api = LogbookAPI()
    private var queue: PendingChanges { PendingChanges.shared }

    /// Der Stand des Dienstes - ohne das, was noch wartet.
    private(set) var overview: LogbookOverview?
    /// Die Nummer der Anfrage, aus der `overview` stammt: ein Abruf, der vor
    /// einem Wert losging und nach dessen Antwort ankommt, ersetzt ihn nicht.
    @ObservationIgnored private var overviewSequence = 0
    private(set) var insights: LogbookInsights?
    /// Der Zeitraum der Effekte in Tagen (30, 90, 180, 365), gemerkt.
    private(set) var period = LogbookPeriod.load()
    /// Die Effekte rechnet der Dienst ueber Monate - nach einem Tipp aendern sie
    /// sich nicht merklich. Deshalb hoechstens alle 15 Minuten neu.
    @ObservationIgnored private var insightsFetchedAt: Date?

    /// Der Tag der Eingabe, von heute bis zum Anfang der Nachtragsfrist.
    private(set) var day = CalendarDate.today().adding(days: -1)
    /// Was am Zaehler getippt ist und noch auf die Ruhe wartet, je `LogbookChange.key`.
    private(set) var typed: [String: Double?] = [:]
    @ObservationIgnored private var settling: [String: Task<Void, Never>] = [:]

    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var error: String?
    private(set) var accessProblem = false

    static let insightsMaxAge: TimeInterval = 15 * 60
    /// So lange wartet der Zaehler, bis er schickt.
    static let settleDelay: Duration = .milliseconds(500)

    init() {
        queue.observe(.weight) { [weak self] event in self?.handle(event) }
    }

    var today: CalendarDate { .today() }
    var yesterday: CalendarDate { today.adding(days: -1) }
    /// Der aelteste Tag, den der Dienst noch annimmt.
    var earliestDay: CalendarDate { today.adding(days: -(overview?.backfillDays ?? 14)) }

    /// Was fuer das Logbook in der Warteschlange wartet.
    var pending: [LogbookChange] { queue.changes(for: .weight).compactMap(\.logbook) }

    /// Der Wert einer Zeile am gewaehlten Tag; `nil` heisst offen.
    func value(_ behavior: Behavior) -> Double? {
        LogbookDays.value(of: behavior.id, on: day, overview: overview, pending: pending, typed: typed)
    }

    /// Die Uhr an der Zeile: der Wert wartet auf Netz.
    func isWaiting(_ behavior: Behavior) -> Bool {
        queue.showsWaiting(LogbookChange.key(day, behavior.id), on: .weight)
    }

    /// Der Punkt an „Gestern“.
    var isYesterdayOpen: Bool {
        guard let overview else { return false }
        return LogbookDays.isOpen(yesterday, overview: overview, pending: pending)
    }

    // MARK: - Laden

    func load(forceInsights: Bool = false) async {
        isLoading = overview == nil
        defer {
            isLoading = false
            hasLoaded = true
        }
        #if DEBUG
        if DashboardDemo.isOn {
            if overview == nil {
                overview = DashboardDemo.logbookOverview()
                followToday()
            }
            insights = DashboardDemo.logbookInsights(days: period)
            return
        }
        #endif
        // Rest der alten Logbook-Seite (bis 12.10.): Tage, die im Postausgang
        // warteten. Was dort noch liegt, schickt der Postausgang selbst.
        UserDefaults.standard.removeObject(forKey: "logbook.queuedDays")
        // Ein Abruf neben einem laufenden Schreiben holte womoeglich einen Stand
        // ohne den gerade geschriebenen Wert.
        await queue.waitUntilIdle(.weight, timeout: .seconds(3))
        let sequence = queue.nextSequence()
        do {
            let fresh = try await api.overview()
            let first = overview == nil
            if sequence > overviewSequence {
                overview = fresh
                overviewSequence = sequence
            }
            clearError()
            if first { followToday() }
            await scheduleReminder()
        } catch {
            report(error)
        }
        await loadInsights(force: forceInsights)
    }

    /// Faellt das aus, fehlen nur die Effekte - die Eingabe geht weiter.
    func loadInsights(force: Bool = false) async {
        #if DEBUG
        if DashboardDemo.isOn {
            insights = DashboardDemo.logbookInsights(days: period)
            return
        }
        #endif
        if !force, insights?.days == period, let at = insightsFetchedAt,
           Date().timeIntervalSince(at) < Self.insightsMaxAge {
            return
        }
        if let fresh = try? await api.insights(days: period) {
            insights = fresh
            insightsFetchedAt = Date()
        }
    }

    func select(period: Int) async {
        self.period = period
        LogbookPeriod.save(period)
        await loadInsights(force: true)
    }

    // MARK: - Tag

    /// Gestern, solange gestern offen ist, sonst heute - wenn das Dashboard
    /// erscheint, die App zurueckkommt oder Mitternacht vorbei ist. Der Tipp auf
    /// die Erinnerung zeigt immer gestern.
    func followToday(reminder: Bool = false) {
        day = reminder ? yesterday : LogbookDays.preferredDay(today: today, overview: overview, pending: pending)
    }

    func show(_ date: CalendarDate) {
        day = LogbookDays.clamp(date, today: today, backfillDays: overview?.backfillDays ?? 14)
    }

    func step(_ days: Int) {
        show(day.adding(days: days))
    }

    // MARK: - Antworten (jeder Tipp speichert)

    /// Ja oder Nein - sofort. Ein Tipp auf die gewaehlte Antwort macht die Zeile offen.
    func answer(_ behavior: Behavior, yes: Bool) {
        write(behavior, LogbookDays.answered(value(behavior), yes: yes), settle: false)
    }

    /// Gedrueckt halten → „Zuruecksetzen“: wieder offen.
    func reset(_ behavior: Behavior) {
        write(behavior, nil, settle: false)
    }

    /// − und +: geschickt wird nach einer halben Sekunde Ruhe - fuenfmal + ist ein
    /// Aufruf, nicht fuenf.
    func step(_ behavior: Behavior, by delta: Int) {
        write(behavior, LogbookDays.stepped(value(behavior), by: delta), settle: true)
    }

    /// Die Eingabe fuer grosse Werte und Kommawerte; leer macht die Zeile offen.
    /// - Returns: `false`, wenn der Dienst die Zahl nicht naehme.
    @discardableResult
    func enter(_ behavior: Behavior, text: String) -> Bool {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            write(behavior, nil, settle: false)
            return true
        }
        guard let amount = LogbookFormat.parseAmount(text) else { return false }
        write(behavior, amount, settle: false)
        return true
    }

    private func write(_ behavior: Behavior, _ value: Double?, settle: Bool) {
        let date = day
        let key = LogbookChange.key(date, behavior.id)
        settling[key]?.cancel()
        settling[key] = nil
        guard settle else {
            typed.removeValue(forKey: key)
            send(date, behavior, value)
            return
        }
        typed[key] = .some(value)
        settling[key] = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self else { return }
            self.settling[key] = nil
            // Erst in die Warteschlange, dann aus `typed` - dazwischen zeigte die
            // Zeile sonst kurz den alten Wert.
            self.send(date, behavior, value)
            self.typed.removeValue(forKey: key)
        }
    }

    private func send(_ date: CalendarDate, _ behavior: Behavior, _ value: Double?) {
        let key = LogbookChange.key(date, behavior.id)
        // Steht es beim Dienst schon so da und wartet nichts: kein Aufruf.
        if !queue.isWaiting(key, on: .weight), overview?.day(date)?.values[behavior.id] == value { return }
        #if DEBUG
        if DashboardDemo.isOn {
            // Im Vorfuehrmodus nur im Speicher - nichts davon erreicht den Dienst.
            guard let overview else { return }
            var values = overview.day(date)?.values ?? [:]
            values[behavior.id] = value
            self.overview = overview.replacing(LogbookDay(date: date, savedAt: Date(), values: values))
            return
        }
        #endif
        queue.enqueue(.logbook(.setValue(date: date, behaviorId: behavior.id, value: value)), label: behavior.name)
        Task { await scheduleReminder() }
    }

    private func handle(_ event: PendingEvent) {
        switch event {
        case .delivered(let data, let sequence):
            // Der Dienst antwortet mit dem ganzen Tag. Was danach noch wartet, liegt
            // ohnehin darueber; ein aelterer Abruf ersetzt ihn nicht mehr.
            guard let saved = try? APIClient.decoder().decode(LogbookDay.self, from: data),
                  let current = overview else { return }
            overview = current.replacing(saved)
            overviewSequence = max(overviewSequence, sequence)
        case .rejected:
            // Etwa eine Verhaltensweise, die ein anderes Geraet geloescht hat.
            Task { await load() }
        case .drained:
            Task { await scheduleReminder() }
        }
    }

    private func scheduleReminder() async {
        #if DEBUG
        if DashboardDemo.isOn { return }
        #endif
        if let overview { await LogbookReminder.schedule(overview) }
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
            await scheduleReminder()
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

    /// Eine archivierte steht nicht mehr im Logbook, ihre Werte bleiben - wer nur
    /// nicht mehr eintragen will, verliert so nichts.
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

    /// Eine Aenderung an den Verhaltensweisen: erst beim Dienst, dann im Stand.
    /// Die Effekte rechnet der Dienst danach neu.
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
        overview = current.with(behaviors: apply(current.behaviors))
        await scheduleReminder()
        await loadInsights(force: true)
        return true
    }

    #if DEBUG
    private func demoChange(_ apply: ([Behavior]) -> [Behavior]) -> Bool {
        guard let current = overview else { return false }
        overview = current.with(behaviors: apply(current.behaviors))
        return true
    }
    #endif

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
