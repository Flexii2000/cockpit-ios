import HealthKit
import WatchKit

/// Das Krafttraining auf der Uhr (Felix, 14.10.): misst Puls und kcal, spiegelt
/// die Session aufs iPhone und speichert am Ende das Training in Health.
///
/// Das iPhone schickt, welches Geraet dran ist; „Satz erledigt“ geht mit einer
/// Kennung zurueck und wird wiederholt, bis das iPhone quittiert - abgehakt wird
/// dort (nur das iPhone schreibt zum Dienst).
@MainActor
@Observable
final class WorkoutManager {

    static let shared = WorkoutManager()

    private(set) var isRunning = false
    private(set) var startDate: Date?
    private(set) var heartRate: Double?
    private(set) var activeKcal: Double?
    /// Was das iPhone als aktuelles Geraet geschickt hat.
    private(set) var current: WorkoutCurrent?
    /// Das iPhone meldet: alle Saetze erledigt.
    private(set) var everythingDone = false

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private let relay = WatchWorkoutRelay()
    /// „Satz erledigt“, deren Quittung noch fehlt: Kennung → Botschaft.
    @ObservationIgnored private var unacked: [String: (message: WorkoutMessage, tries: Int)] = [:]
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var lastMetricsSent = Date.distantPast

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

    /// Beim ersten Oeffnen der App - mitten im Start eines Trainings soll kein
    /// Dialog stehen.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned),
                                        HKQuantityType(.heartRate)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        try? await store.requestAuthorization(toShare: share, read: read)
    }

    func start(with configuration: HKWorkoutConfiguration) async {
        guard session == nil else { return }
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = relay
            builder.delegate = relay
            self.session = session
            self.builder = builder
            // Ohne iPhone in der Naehe laeuft das Training trotzdem - nur ohne Spiegel.
            try? await session.startMirroringToCompanionDevice()
            let start = Date()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            startDate = start
            isRunning = true
        } catch {
            reset()
        }
    }

    /// Ein Satz des aktuellen Geraets ist fertig - mit Spanne mit den
    /// Wiederholungen von der Krone, sonst ohne (dann gilt am iPhone der Plan).
    func setDone(reps: Int? = nil) {
        guard let current else { return }
        let id = UUID().uuidString
        let message = WorkoutMessage.setDone(id: id, exerciseId: current.exerciseId, reps: reps)
        unacked[id] = (message, 0)
        send(message)
        WKInterfaceDevice.current().play(.success)
        scheduleRetry()
    }

    /// Beenden - auf der Uhr getippt oder vom iPhone verlangt.
    func end(fromPhone: Bool = false) async {
        guard let session, let builder else { return }
        if !fromPhone { send(.end) }
        let now = Date()
        session.stopActivity(with: now)
        session.end()
        do {
            try await builder.endCollection(at: now)
            _ = try await builder.finishWorkout()
        } catch {
            // Ohne Speichern bleibt das Training nur aus Health weg - der Gym-Tab hat die Saetze.
        }
        reset()
    }

    func receive(_ data: Data) {
        guard let message = WorkoutMessage.decode(data) else { return }
        switch message {
        case .current(let fresh):
            current = fresh
            everythingDone = fresh == nil
        case .ack(let id):
            unacked[id] = nil
        case .end:
            Task { await end(fromPhone: true) }
        case .metrics, .setDone:
            break
        }
    }

    // MARK: - Intern

    private func update(heartRate: Double?, kcal: Double?) {
        if let heartRate { self.heartRate = heartRate }
        if let kcal { activeKcal = kcal }
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

    /// Alle drei Sekunden, was noch nicht quittiert ist; nach fuenf Versuchen
    /// ueber WatchConnectivity - das kommt auch an, wenn das iPhone schlaeft.
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

    private func reset() {
        session = nil
        builder = nil
        isRunning = false
        startDate = nil
        heartRate = nil
        activeKcal = nil
        current = nil
        everythingDone = false
    }

    #if DEBUG
    /// Fuer Aufnahmen im Uhren-Simulator (`COCKPIT_WATCH_DEMO=workout`) - dort gibt
    /// es kein gespiegeltes Training.
    func showDemo() {
        isRunning = true
        startDate = Date().addingTimeInterval(-754)
        heartRate = 128
        activeKcal = 143
        current = WorkoutCurrent(exerciseId: "e-demo-a", name: "Gerät A", note: "Sitz 4", set: 2, sets: 3,
                                 reps: 10, repsMin: 8, weightKg: 40)
    }
    #endif
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
