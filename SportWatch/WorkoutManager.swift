import HealthKit
import WatchKit

/// Ein Training auf der Uhr - zwei Arten (Felix, 14. und 23.10.):
///
/// * **Krafttraining** aus dem Gym-Tab: das iPhone startet es (`startWatchApp`), die Uhr misst
///   Puls und kcal und spiegelt die Session aufs iPhone. Das iPhone schickt den Plan (das
///   aktuelle Geraet, alle des Tages); „Satz erledigt“ und „dieses Geraet“ gehen mit einer
///   Kennung zurueck und werden wiederholt, bis das iPhone quittiert - abgehakt wird dort.
/// * **Padel**: startet auf der Uhr, ohne iPhone. Gezaehlt wird hier (`PadelScore`); am Ende
///   geht das Ergebnis an den Padel-Dienst, der es bei Playtomic eintraegt.
///
/// Beide landen am Ende als Training in Health - beim Padel vor allem wegen der kcal.
@MainActor
@Observable
final class WorkoutManager {

    static let shared = WorkoutManager()

    enum Kind: String, Codable { case gym, padel }

    /// Was gerade laeuft - `nil`: nichts.
    private(set) var kind: Kind?
    private(set) var startDate: Date?
    private(set) var heartRate: Double?
    private(set) var activeKcal: Double?

    /// Krafttraining: was das iPhone zuletzt geschickt hat.
    private(set) var plan: WorkoutPlan?
    /// Krafttraining: an der Uhr gerade abgehakt, das iPhone hat es noch nicht bestaetigt.
    private(set) var localLastSetAt: Date?

    /// Padel: der Spielstand samt Verlauf zum Zuruecknehmen.
    private(set) var padel: PadelMatch?
    /// Padel: das Ergebnis des zuletzt beendeten Matches - fuer die Startseite.
    private(set) var lastReport: PadelMatchReport? = PadelMatch.lastReport()

    var isRunning: Bool { kind != nil }

    /// Wann zuletzt ein Satz fertig war - an der Uhr oder am iPhone.
    var lastSetAt: Date? {
        [plan?.lastSetAt, localLastSetAt].compactMap { $0 }.max()
    }

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private let relay = WatchWorkoutRelay()
    /// Botschaften ans iPhone, deren Quittung noch fehlt: Kennung → Botschaft.
    @ObservationIgnored private var unacked: [String: (message: WorkoutMessage, tries: Int)] = [:]
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var pauseAlert: Task<Void, Never>?
    @ObservationIgnored private var lastMetricsSent = Date.distantPast

    /// Nach so langer Pause meldet sich die Uhr einmal (Felix, 23.10.).
    static let pauseAlertAfter: TimeInterval = 90

    private init() {
        relay.onStatistics = { heartRate, kcal in
            Task { @MainActor in WorkoutManager.shared.update(heartRate: heartRate, kcal: kcal) }
        }
        relay.onMessage = { data in
            Task { @MainActor in WorkoutManager.shared.receive(data) }
        }
        relay.onEnded = {
            Task { @MainActor in WorkoutManager.shared.reset() }
        }
    }

    /// Beim ersten Oeffnen der App - mitten im Start eines Trainings soll kein Dialog stehen.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned),
                                        HKQuantityType(.heartRate)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        try? await store.requestAuthorization(toShare: share, read: read)
    }

    // MARK: - Starten

    /// Krafttraining - vom iPhone geweckt, gespiegelt.
    func startGym(with configuration: HKWorkoutConfiguration) async {
        guard session == nil else { return }
        guard await begin(configuration, mirrored: true) else { return }
        kind = .gym
    }

    /// Padel - auf der Uhr gestartet, nicht gespiegelt.
    func startPadel(rule: PadelDeuceRule, firstServer: PadelSide) async {
        guard session == nil else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .paddleSports
        configuration.locationType = .indoor
        guard await begin(configuration, mirrored: false) else { return }
        let match = PadelMatch(rule: rule, firstServer: firstServer, startedAt: startDate ?? Date())
        padel = match
        match.save()
        kind = .padel
    }

    private func begin(_ configuration: HKWorkoutConfiguration, mirrored: Bool) async -> Bool {
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = relay
            builder.delegate = relay
            self.session = session
            self.builder = builder
            if mirrored {
                // Ohne iPhone in der Naehe laeuft das Training trotzdem - nur ohne Spiegel.
                try? await session.startMirroringToCompanionDevice()
            }
            let start = Date()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            startDate = start
            return true
        } catch {
            reset()
            return false
        }
    }

    /// Nach einem Absturz mitten im Training: watchOS startet die App neu und gibt die Session
    /// zurueck - Padel samt Spielstand, Krafttraining bis das iPhone den Plan neu schickt.
    func recover() async {
        guard session == nil, let recovered = try? await store.recoverActiveWorkoutSession() else { return }
        let builder = recovered.associatedWorkoutBuilder()
        recovered.delegate = relay
        builder.delegate = relay
        session = recovered
        self.builder = builder
        startDate = recovered.startDate
        if let match = PadelMatch.load() {
            padel = match
            kind = .padel
        } else {
            kind = .gym
        }
    }

    // MARK: - Krafttraining

    /// Ein Satz des aktuellen Geraets ist fertig - mit Spanne mit den Wiederholungen von der
    /// Krone, sonst ohne (dann gilt am iPhone der Plan).
    func setDone(reps: Int? = nil) {
        guard let current = plan?.current else { return }
        let id = UUID().uuidString
        sendReliably(id: id, .setDone(id: id, exerciseId: current.exerciseId, reps: reps))
        localLastSetAt = Date()
        schedulePauseAlert()
        WKInterfaceDevice.current().play(.success)
    }

    /// Ein anderes Geraet ist jetzt dran (Felix, 23.10.: wenn eins besetzt ist).
    func choose(_ exerciseId: String) {
        guard exerciseId != plan?.current?.exerciseId else { return }
        let id = UUID().uuidString
        sendReliably(id: id, .choose(id: id, exerciseId: exerciseId))
        WKInterfaceDevice.current().play(.click)
    }

    func receive(_ data: Data) {
        guard let message = WorkoutMessage.decode(data) else { return }
        switch message {
        case .plan(let fresh):
            plan = fresh
            if let confirmed = fresh.lastSetAt, let local = localLastSetAt, confirmed >= local.addingTimeInterval(-5) {
                localLastSetAt = nil
            }
            schedulePauseAlert()
        case .ack(let id):
            unacked[id] = nil
        case .end:
            Task { await end(fromPhone: true) }
        case .metrics, .setDone, .choose:
            break
        }
    }

    // MARK: - Padel

    func point(for side: PadelSide) {
        guard var match = padel else { return }
        let before = match.score
        match.point(for: side)
        guard match.score != before else { return }
        padel = match
        match.save()
        let device = WKInterfaceDevice.current()
        if match.score.sets.count > before.sets.count {
            device.play(.notification)
        } else if match.score.games != before.games {
            device.play(.success)
        } else {
            device.play(.click)
        }
    }

    func undoPoint() {
        guard var match = padel, match.undo() else { return }
        padel = match
        match.save()
        WKInterfaceDevice.current().play(.retry)
    }

    /// Ball antippen: im aufschlagenden Team schlaegt der andere Spieler auf.
    func switchServingPlayer() {
        guard var match = padel else { return }
        match.switchServingPlayer()
        padel = match
        match.save()
        WKInterfaceDevice.current().play(.click)
    }

    // MARK: - Beenden

    /// Beenden - auf der Uhr getippt oder vom iPhone verlangt. Padel gibt sein Ergebnis ab.
    func end(fromPhone: Bool = false) async {
        guard let session, let builder else { return }
        if kind == .gym && !fromPhone { send(.end) }
        let now = Date()
        let match = padel
        session.stopActivity(with: now)
        session.end()
        do {
            try await builder.endCollection(at: now)
            _ = try await builder.finishWorkout()
        } catch {
            // Ohne Speichern fehlt das Training nur in Health - Saetze bzw. Ergebnis sind trotzdem da.
        }
        if let match {
            report(match.report(endedAt: now))
        }
        reset()
    }

    /// Ein gueltiges Ergebnis geht an den Padel-Dienst - direkt und uebers iPhone; der Dienst
    /// nimmt es nur einmal an (Kennung).
    private func report(_ report: PadelMatchReport) {
        PadelMatch.clear()
        PadelMatch.saveLast(report)
        lastReport = report
        guard report.isValid else { return }
        PadelReportOutbox.shared.add(report)
        WatchSession.shared.sendPadelReport(report)
        Task { await PadelReportOutbox.shared.deliver(cookie: WatchSession.shared.cookie) }
    }

    // MARK: - Intern

    private func update(heartRate: Double?, kcal: Double?) {
        if let heartRate { self.heartRate = heartRate }
        if let kcal { activeKcal = kcal }
        guard kind == .gym else { return }
        // Alle drei Sekunden reicht dem iPhone - jede Botschaft kostet Funk.
        let now = Date()
        guard now.timeIntervalSince(lastMetricsSent) >= 3 else { return }
        lastMetricsSent = now
        send(.metrics(WorkoutMetrics(heartRate: self.heartRate, activeKcal: activeKcal, at: now)))
    }

    private func send(_ message: WorkoutMessage) {
        guard let data = message.encoded() else { return }
        if let session {
            Task { try? await session.sendToRemoteWorkoutSession(data: data) }
        }
    }

    /// Schicken und wiederholen, bis das iPhone quittiert.
    private func sendReliably(id: String, _ message: WorkoutMessage) {
        unacked[id] = (message, 0)
        send(message)
        scheduleRetry()
    }

    /// Alle drei Sekunden, was noch nicht quittiert ist; nach fuenf Versuchen ueber
    /// WatchConnectivity - das kommt auch an, wenn das iPhone schlaeft.
    private func scheduleRetry() {
        guard retryTask == nil else { return }
        retryTask = Task {
            while !unacked.isEmpty {
                try? await Task.sleep(for: .seconds(3))
                for (id, entry) in unacked {
                    if entry.tries >= 5 {
                        if let data = entry.message.encoded() { WatchSession.shared.sendWorkout(data) }
                        unacked[id] = nil
                    } else {
                        unacked[id] = (entry.message, entry.tries + 1)
                        send(entry.message)
                    }
                }
            }
            retryTask = nil
        }
    }

    /// Einmal kurz vibrieren, wenn die Pause seit dem letzten Satz 90 Sekunden erreicht.
    private func schedulePauseAlert() {
        pauseAlert?.cancel()
        guard kind == .gym, let last = lastSetAt, plan?.current != nil else { return }
        let due = last.addingTimeInterval(Self.pauseAlertAfter)
        guard due > Date() else { return }
        pauseAlert = Task {
            try? await Task.sleep(for: .seconds(due.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            WKInterfaceDevice.current().play(.notification)
        }
    }

    private func reset() {
        session = nil
        builder = nil
        kind = nil
        startDate = nil
        heartRate = nil
        activeKcal = nil
        plan = nil
        localLastSetAt = nil
        padel = nil
        pauseAlert?.cancel()
        pauseAlert = nil
    }

    #if DEBUG
    /// Fuer Aufnahmen im Uhren-Simulator (`COCKPIT_WATCH_DEMO`) - dort gibt es kein
    /// gespiegeltes Training und keine Messung.
    func showDemo(_ which: String) {
        if which == "home" {
            // Der Start ohne den Health-Dialog, den der Simulator nicht wegklicken kann.
            lastReport = PadelMatchReport(id: "demo", startedAt: Date().addingTimeInterval(-5_400),
                                          endedAt: Date().addingTimeInterval(-600), rule: .golden,
                                          sets: [PadelSetScore(us: 6, them: 4), PadelSetScore(us: 6, them: 2)])
            return
        }
        startDate = Date().addingTimeInterval(-754)
        heartRate = 128
        activeKcal = 143
        if which.hasPrefix("padel") {
            var match = PadelMatch(rule: .golden, firstServer: .us, startedAt: startDate ?? Date())
            func game(_ side: PadelSide) { for _ in 0..<4 { match.point(for: side) } }
            // 6:4, im zweiten Satz 3:2 und 40:40 - beim Golden Point entscheidet der naechste.
            for side: PadelSide in [.us, .them, .us, .them, .us, .them, .us, .them, .us, .us] { game(side) }
            for side: PadelSide in [.us, .them, .us, .them, .us] { game(side) }
            for side: PadelSide in [.us, .us, .us, .them, .them, .them] { match.point(for: side) }
            padel = match
            kind = .padel
        } else {
            plan = WorkoutPlan(
                current: WorkoutCurrent(exerciseId: "e-demo-a", name: "Gerät A", note: "Sitz 4", set: 2, sets: 3,
                                        reps: 10, repsMin: 8, weightKg: 40),
                stations: [WorkoutStation(exerciseId: "e-demo-a", name: "Gerät A", done: 1, sets: 3),
                           WorkoutStation(exerciseId: "e-demo-b", name: "Gerät B", done: 0, sets: 3),
                           WorkoutStation(exerciseId: "e-demo-c", name: "Gerät C", done: 2, sets: 2)],
                lastSetAt: Date().addingTimeInterval(-63))
            kind = .gym
        }
    }
    #endif
}

/// Ein laufendes Padel-Match: der Stand und der Weg dorthin, damit ein versehentlicher
/// Punkt zurueckgeht. Gemerkt, damit ein Neustart der Uhr-App ihn nicht verliert.
struct PadelMatch: Codable, Equatable, Sendable {

    let id: String
    let startedAt: Date
    private(set) var score: PadelScore
    private(set) var history: [PadelScore] = []

    init(rule: PadelDeuceRule, firstServer: PadelSide, startedAt: Date) {
        id = UUID().uuidString
        self.startedAt = startedAt
        score = PadelScore(rule: rule, firstServer: firstServer)
    }

    mutating func point(for side: PadelSide) {
        apply { $0.point(for: side) }
    }

    /// Wie ein Punkt im Verlauf - „Zurueck“ nimmt auch ein versehentliches Antippen des Balls zurueck.
    mutating func switchServingPlayer() {
        apply { $0.switchServingPlayer() }
    }

    private mutating func apply(_ change: (inout PadelScore) -> Void) {
        let before = score
        change(&score)
        guard score != before else { return }
        history.append(before)
        // Zuruecknehmen braucht man fuer die letzten Punkte, nicht fuer das ganze Match.
        if history.count > 200 { history.removeFirst(history.count - 200) }
    }

    /// - Returns: ob es einen Punkt zum Zuruecknehmen gab.
    mutating func undo() -> Bool {
        guard let previous = history.popLast() else { return false }
        score = previous
        return true
    }

    func report(endedAt: Date) -> PadelMatchReport {
        PadelMatchReport(id: id, startedAt: startedAt, endedAt: endedAt, rule: score.rule, sets: score.sets)
    }

    // MARK: - Gemerkt

    private static let runningKey = "padel.match.running"
    private static let lastKey = "padel.match.last"

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.runningKey) }
    }

    static func load() -> PadelMatch? {
        UserDefaults.standard.data(forKey: runningKey).flatMap { try? JSONDecoder().decode(PadelMatch.self, from: $0) }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: runningKey)
    }

    static func saveLast(_ report: PadelMatchReport) {
        if let data = try? JSONEncoder().encode(report) { UserDefaults.standard.set(data, forKey: lastKey) }
    }

    static func lastReport() -> PadelMatchReport? {
        UserDefaults.standard.data(forKey: lastKey).flatMap { try? JSONDecoder().decode(PadelMatchReport.self, from: $0) }
    }
}

/// Delegat von Session und Builder - HealthKit ruft auf einer eigenen
/// Warteschlange, deshalb nur Werte weiterreichen.
final class WatchWorkoutRelay: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate,
                               @unchecked Sendable {

    nonisolated(unsafe) var onStatistics: (@Sendable (Double?, Double?) -> Void)?
    nonisolated(unsafe) var onMessage: (@Sendable (Data) -> Void)?
    nonisolated(unsafe) var onEnded: (@Sendable () -> Void)?

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .ended { onEnded?() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        for item in data { onMessage?(item) }
    }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        let heartRate = collectedTypes.contains(HKQuantityType(.heartRate))
            ? workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: perMinute)
            : nil
        let kcal = collectedTypes.contains(HKQuantityType(.activeEnergyBurned))
            ? workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            : nil
        onStatistics?(heartRate, kcal)
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
