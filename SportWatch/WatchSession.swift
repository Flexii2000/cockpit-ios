import Foundation
import WatchConnectivity

/// Die Uhr-Seite von `SportWatchLink`: nimmt den Token vom iPhone an und legt ihn in den
/// Schluesselbund der Uhr, dazu die Rueckfallwege - Trainings-Botschaften und Padel-Ergebnisse
/// per `transferUserInfo`, falls die gespiegelte Session bzw. das Netz gerade fehlt.
@MainActor
final class WatchSession {

    static let shared = WatchSession()

    private let relay = WatchSessionRelay()

    private init() {}

    func activate() {
        guard WCSession.isSupported() else { return }
        relay.onToken = { token in
            Task { @MainActor in
                guard token != Keychain.read(Keychain.privateTokenKey) else { return }
                Keychain.save(token, for: Keychain.privateTokenKey)
                // Mit Token kann jetzt raus, was noch wartet.
                await PadelReportOutbox.shared.deliver(cookie: WatchSession.shared.cookie)
            }
        }
        relay.onWorkout = { data in
            Task { @MainActor in WorkoutManager.shared.receive(data) }
        }
        let session = WCSession.default
        session.delegate = relay
        session.activate()
        relay.take(context: session.receivedApplicationContext)
    }

    /// Der Cookie fuer den Padel-Dienst - die Uhr hat keinen Cookie-Speicher, den `Access` fuellt.
    var cookie: String? {
        Keychain.read(Keychain.privateTokenKey).flatMap { $0.isEmpty ? nil : "\(Keychain.privateTokenKey)=\($0)" }
    }

    /// Fuer `.backgroundTask(.watchConnectivity)`: erst zurueckkehren, wenn nichts mehr ansteht -
    /// sonst friert watchOS die App mitten im Empfang ein.
    func waitForPendingContent() async {
        if WCSession.default.activationState != .activated { activate() }
        for _ in 0..<20 {
            if !WCSession.default.hasContentPending { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Rueckfall, wenn die gespiegelte Session gerade nicht zustellt.
    func sendWorkout(_ data: Data) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo([SportWatchKeys.workoutMessage: data])
    }

    /// Das Ergebnis auch uebers iPhone - es liefert ab, falls die Uhr selbst nicht durchkommt.
    func sendPadelReport(_ report: PadelMatchReport) {
        guard WCSession.default.activationState == .activated,
              let data = try? APIClient.encoder().encode(report) else { return }
        WCSession.default.transferUserInfo([SportWatchKeys.padelReport: data])
    }
}

/// Der Delegat - WatchConnectivity ruft ihn auf einer eigenen Warteschlange.
final class WatchSessionRelay: NSObject, WCSessionDelegate, @unchecked Sendable {

    nonisolated(unsafe) var onToken: (@Sendable (String) -> Void)?
    nonisolated(unsafe) var onWorkout: (@Sendable (Data) -> Void)?

    nonisolated func take(context: [String: Any]) {
        if let token = context[SportWatchKeys.privateToken] as? String, !token.isEmpty { onToken?(token) }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        take(context: session.receivedApplicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        take(context: applicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo[SportWatchKeys.workoutMessage] as? Data { onWorkout?(data) }
    }
}
