import Foundation
import WatchConnectivity

/// Der Draht zur Uhr-App von Sport ueber WatchConnectivity (23.10.):
///
/// * der Privat-Token, damit die Uhr ein Padel-Ergebnis selbst beim Padel-Dienst abliefern
///   kann (wie Healthy ihn fuer die kcal-Komplikation schickt, docs/ENTSCHEIDUNGEN.md 14.10.)
/// * Ergebnisse, die die Uhr nicht selbst losgeworden ist - die liefert dann das iPhone ab
/// * der Rueckfall fuer Trainings-Botschaften, wenn die gespiegelte Session gerade nicht zustellt
@MainActor
final class SportWatchLink {

    static let shared = SportWatchLink()

    private let relay = SportWatchLinkRelay()

    private init() {}

    private var session: WCSession? {
        guard WCSession.isSupported() else { return nil }
        return WCSession.default
    }

    /// Beim Start der App (`AppDelegate`) - die Uhr kann jederzeit etwas schicken.
    func activate() {
        guard let session else { return }
        relay.onActivated = {
            Task { @MainActor in SportWatchLink.shared.sendContext() }
        }
        relay.onWorkoutMessage = { data in
            Task { @MainActor in WorkoutMirror.shared.receiveFallback(data) }
        }
        relay.onPadelReport = { data in
            Task { @MainActor in
                guard let report = try? APIClient.decoder().decode(PadelMatchReport.self, from: data) else { return }
                PadelReportOutbox.shared.add(report)
                await PadelReportOutbox.shared.deliver(cookie: nil)
            }
        }
        session.delegate = relay
        session.activate()
    }

    /// Der Token als Kontext - der gilt, bis ein neuer kommt.
    func sendContext() {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let token = Keychain.read(Keychain.privateTokenKey), !token.isEmpty else { return }
        try? session.updateApplicationContext([SportWatchKeys.privateToken: token])
    }

    /// Rueckfall fuer Trainings-Botschaften an die Uhr, solange die gespiegelte Session nicht steht.
    func sendWorkout(_ data: Data) {
        guard let session, session.activationState == .activated, session.isWatchAppInstalled else { return }
        session.transferUserInfo([SportWatchKeys.workoutMessage: data])
    }
}

/// Der Delegat von `WCSession` - WatchConnectivity ruft ihn auf einer eigenen
/// Warteschlange, deshalb nur Werte weiterreichen.
final class SportWatchLinkRelay: NSObject, WCSessionDelegate, @unchecked Sendable {

    nonisolated(unsafe) var onActivated: (@Sendable () -> Void)?
    nonisolated(unsafe) var onWorkoutMessage: (@Sendable (Data) -> Void)?
    nonisolated(unsafe) var onPadelReport: (@Sendable (Data) -> Void)?

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        if activationState == .activated { onActivated?() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Nach einem Uhrenwechsel: neu anmelden, sonst bleibt der Draht tot.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        // Uhr-App gerade installiert: der Token hinterher.
        if session.isWatchAppInstalled { onActivated?() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if let data = userInfo[SportWatchKeys.workoutMessage] as? Data { onWorkoutMessage?(data) }
        if let data = userInfo[SportWatchKeys.padelReport] as? Data { onPadelReport?(data) }
    }
}
