import HealthKit

/// Das Training auf der Uhr, gespiegelt aufs iPhone (Felix, 14.10.: Live-Werte
/// von der Apple Watch, das Training landet in Health).
///
/// „Training starten“ weckt die Uhr-App (`startWatchApp`); die Uhr fuehrt die
/// `HKWorkoutSession` samt Messung und spiegelt sie hierher. Das iPhone misst
/// selbst nichts (es hat keinen Pulssensor) - es bekommt Puls, kcal, „Satz
/// erledigt“ und „dieses Geraet“ als Botschaften (`WorkoutMessage`) und schickt
/// den Plan zurueck: das aktuelle Geraet und alle des Tages. Gespeichert wird das
/// Training von der Uhr. Seit 23.10. in Sport mit eigener Uhr-App (vorher Healthy).
@MainActor
@Observable
final class WorkoutMirror {

    static let shared = WorkoutMirror()

    /// Die letzten Werte der Uhr - `nil`, solange keine Uhr mitmacht.
    private(set) var metrics: WorkoutMetrics?

    /// Ein „Satz erledigt“ von der Uhr - der Gym-Tab hakt dann den naechsten
    /// offenen Satz dieses Geraets ab, mit Spanne mit den Wiederholungen von
    /// der Krone (`nil`: wie geplant).
    @ObservationIgnored var onSetDone: ((_ exerciseId: String, _ reps: Int?) -> Void)?
    /// An der Uhr ein anderes Geraet gewaehlt (eines ist besetzt).
    @ObservationIgnored var onChoose: ((_ exerciseId: String) -> Void)?
    /// Auf der Uhr beendet - dann endet das Training auch hier.
    @ObservationIgnored var onEnd: (() -> Void)?

    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var lastSent: WorkoutPlan?
    /// Schon abgehakte Botschaften der Uhr - sie wiederholt, bis die Quittung kommt.
    @ObservationIgnored private var handled: Set<String> = []

    @ObservationIgnored private let store = HKHealthStore()
    /// Nimmt die Rueckrufe von HealthKit entgegen (beliebige Warteschlange) und
    /// reicht sie hierher weiter. Muss gesetzt sein, bevor die erste Botschaft
    /// kommt - deshalb ein eigenes Objekt, das schon im Start-Handler bereitsteht.
    @ObservationIgnored private let relay = WorkoutRelay()

    private init() {}

    private var isAvailable: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["COCKPIT_NO_HEALTH"] == "1" { return false }
        #endif
        return HKHealthStore.isHealthDataAvailable()
    }

    /// Gleich beim Start der App (`AppDelegate`): startet die Uhr eine
    /// gespiegelte Session, weckt iOS die App im Hintergrund und ruft diesen
    /// Handler - ist er dann nicht gesetzt, geht die Session verloren.
    func install() {
        guard isAvailable else { return }
        let relay = relay
        relay.onMessage = { data in
            Task { @MainActor in WorkoutMirror.shared.receive(data) }
        }
        relay.onEnded = {
            Task { @MainActor in WorkoutMirror.shared.ended() }
        }
        store.workoutSessionMirroringStartHandler = { session in
            // Sofort, noch auf der Warteschlange von HealthKit: sonst gingen
            // die ersten Botschaften an niemanden.
            session.delegate = relay
            Task { @MainActor in WorkoutMirror.shared.attach(session) }
        }
    }

    /// Einmal, bevor das erste Training startet (der Gym-Tab erscheint): ohne die Erlaubnis
    /// fuer Trainings spiegelt HealthKit die Session der Uhr nicht hierher. Bis 23.10. fragte
    /// Healthy das beim Start mit.
    func requestAuthorization() async {
        guard isAvailable else { return }
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        try? await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: read)
    }

    /// „Training starten“: die Uhr-App mit einem Krafttraining wecken.
    func start() {
        guard isAvailable else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        store.startWatchApp(with: configuration) { _, _ in
            // Ohne Uhr oder ohne Uhr-App: dann laeuft das Training ohne Live-Werte.
        }
    }

    /// „Training beenden“: die Uhr beendet und speichert.
    func finish() {
        sendMessage(.end)
        metrics = nil
        lastSent = nil
        onSetDone = nil
        onChoose = nil
        onEnd = nil
    }

    /// Der Plan an die Uhr - nur, wenn er sich geaendert hat.
    func send(plan: WorkoutPlan) {
        guard lastSent != plan else { return }
        lastSent = plan
        sendMessage(.plan(plan))
    }

    // MARK: - Intern

    private func attach(_ session: HKWorkoutSession) {
        self.session = session
        // Was die Uhr zeigen soll, kennt sie noch nicht.
        if let lastSent { sendMessage(.plan(lastSent)) }
    }

    private func ended() {
        session = nil
        metrics = nil
    }

    private func receive(_ data: Data) {
        guard let message = WorkoutMessage.decode(data) else { return }
        switch message {
        case .metrics(let fresh):
            metrics = fresh
        case .setDone(let id, let exerciseId, let reps):
            if !handled.contains(id) {
                handled.insert(id)
                onSetDone?(exerciseId, reps)
            }
            sendMessage(.ack(id: id))
        case .choose(let id, let exerciseId):
            if !handled.contains(id) {
                handled.insert(id)
                onChoose?(exerciseId)
            }
            sendMessage(.ack(id: id))
        case .end:
            ended()
            let end = onEnd
            onSetDone = nil
            onChoose = nil
            onEnd = nil
            end?()
        case .plan, .ack:
            break
        }
    }

    /// Ueber die gespiegelte Session; ohne sie ueber WatchConnectivity.
    private func sendMessage(_ message: WorkoutMessage) {
        guard let data = message.encoded() else { return }
        if let session {
            Task { try? await session.sendToRemoteWorkoutSession(data: data) }
        } else {
            SportWatchLink.shared.sendWorkout(data)
        }
    }

    #if DEBUG
    /// Fuer Aufnahmen (`COCKPIT_GYM_WORKOUT`): Werte, wie sie von der Uhr kaemen.
    func showDemoMetrics() {
        metrics = WorkoutMetrics(heartRate: 128, activeKcal: 143, at: Date())
    }
    #endif

    /// Ein „Satz erledigt“, der ueber WatchConnectivity kam (`transferUserInfo`,
    /// wenn die Session gerade nicht zustellte).
    func receiveFallback(_ data: Data) {
        receive(data)
    }
}

/// Der Delegat der gespiegelten Session. HealthKit ruft ihn auf einer eigenen
/// Warteschlange - deshalb `nonisolated` und nur Werte weiterreichen (dieselbe
/// Falle wie beim Benachrichtigungs-Delegaten, CLAUDE.md).
final class WorkoutRelay: NSObject, HKWorkoutSessionDelegate, @unchecked Sendable {

    /// Einmal gesetzt in `WorkoutMirror.install`, bevor HealthKit ruft.
    nonisolated(unsafe) var onMessage: (@Sendable (Data) -> Void)?
    nonisolated(unsafe) var onEnded: (@Sendable () -> Void)?

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .ended { onEnded?() }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        for item in data { onMessage?(item) }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didDisconnectFromRemoteDeviceWithError error: (any Error)?) {
        onEnded?()
    }
}
