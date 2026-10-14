import Foundation
import WatchConnectivity
import WidgetKit

/// Die Uhr-Seite von `WatchLink`: nimmt Token und kcal-Stand vom iPhone an,
/// legt sie in den Schluesselbund der Uhr und laesst die Komplikation neu
/// zeichnen. Dazu der Rueckfallweg fuer Trainings-Botschaften.
@MainActor
final class WatchSession {

    static let shared = WatchSession()

    private let relay = WatchSessionRelay()

    private init() {}

    func activate() {
        guard WCSession.isSupported() else { return }
        relay.onToken = { token in
            Task { @MainActor in
                if ComplicationStore.save(token: token) { WidgetCenter.shared.reloadAllTimelines() }
            }
        }
        relay.onSnapshot = { data in
            Task { @MainActor in
                guard let snapshot = try? JSONDecoder().decode(ComplicationSnapshot.self, from: data) else { return }
                if ComplicationStore.save(snapshot: snapshot) { WidgetCenter.shared.reloadAllTimelines() }
            }
        }
        relay.onWorkout = { data in
            Task { @MainActor in WorkoutManager.shared.receive(data) }
        }
        let session = WCSession.default
        session.delegate = relay
        session.activate()
        // Was schon als Kontext da ist, gilt sofort.
        relay.take(context: session.receivedApplicationContext)
    }

    /// Fuer `.backgroundTask(.watchConnectivity)`: erst zurueckkehren, wenn
    /// nichts mehr ansteht - sonst friert watchOS die App mitten im Empfang ein.
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
        WCSession.default.transferUserInfo([WatchKeys.workoutMessage: data])
    }
}

/// Der Delegat - WatchConnectivity ruft ihn auf einer eigenen Warteschlange.
final class WatchSessionRelay: NSObject, WCSessionDelegate, @unchecked Sendable {

    nonisolated(unsafe) var onToken: (@Sendable (String) -> Void)?
    nonisolated(unsafe) var onSnapshot: (@Sendable (Data) -> Void)?
    nonisolated(unsafe) var onWorkout: (@Sendable (Data) -> Void)?

    nonisolated func take(context: [String: Any]) {
        if let token = context[WatchKeys.privateToken] as? String, !token.isEmpty { onToken?(token) }
        if let data = context[WatchKeys.snapshot] as? Data { onSnapshot?(data) }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        take(context: session.receivedApplicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        take(context: applicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo[WatchKeys.snapshot] as? Data { onSnapshot?(data) }
        if let data = userInfo[WatchKeys.workoutMessage] as? Data { onWorkout?(data) }
    }
}
