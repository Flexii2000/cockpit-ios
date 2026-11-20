import Foundation
import WatchConnectivity
import WidgetKit

/// Die Uhr-Seite von `WatchLink`: nimmt Token und kcal-Stand vom iPhone an,
/// legt sie in den Schluesselbund der Uhr und laesst die Komplikation neu
/// zeichnen.
@MainActor
final class WatchSession {

    static let shared = WatchSession()

    private let relay = WatchSessionRelay()

    private init() {}

    func activate() {
        guard WCSession.isSupported() else { return }
        relay.onAccess = { tokens in
            Task { @MainActor in
                if ComplicationStore.save(tokens) {
                    // Ein anderer Zugang heisst ein anderes Tagebuch: der alte
                    // Stand zaehlt nicht mehr.
                    ComplicationStore.clearSnapshot()
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
        relay.onSnapshot = { data in
            Task { @MainActor in
                guard let snapshot = try? JSONDecoder().decode(ComplicationSnapshot.self, from: data) else { return }
                if ComplicationStore.save(snapshot: snapshot) { WidgetCenter.shared.reloadAllTimelines() }
            }
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
}

/// Der Delegat - WatchConnectivity ruft ihn auf einer eigenen Warteschlange.
final class WatchSessionRelay: NSObject, WCSessionDelegate, @unchecked Sendable {

    /// Die Token des Kontexts, und ob er sie vollstaendig nennt.
    nonisolated(unsafe) var onAccess: (@Sendable (ComplicationStore.Tokens) -> Void)?
    nonisolated(unsafe) var onSnapshot: (@Sendable (Data) -> Void)?

    nonisolated func take(context: [String: Any]) {
        let owner = context[WatchKeys.privateToken] as? String
        let health = context[WatchKeys.healthToken] as? String
        let weight = context[WatchKeys.weightToken] as? String
        let replacesAll = context[WatchKeys.accessVersion] != nil
        // Erst ab Version 3 (20.11.) nennt das iPhone den Weight-Token - ein
        // Kontext von davor sagt ueber ihn nichts.
        let replacesWeight = (context[WatchKeys.accessVersion] as? Int ?? 0) >= 3
        // Ein leerer Kontext (noch nie etwas gekommen) sagt nichts.
        if owner != nil || health != nil || weight != nil || replacesAll {
            onAccess?(ComplicationStore.Tokens(owner: owner, health: health, weight: weight,
                                               replacesAll: replacesAll, replacesWeight: replacesWeight))
        }
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
    }
}
