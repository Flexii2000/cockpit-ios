import Foundation
import WatchConnectivity

/// Der Draht zur Uhr ueber WatchConnectivity (14.10.): der Token fuer die
/// kcal-Komplikation und ihr Stand nach jeder Essensaenderung. Das Krafttraining
/// ist am 23.10. mit dem Gym-Tab nach Sport gezogen, samt eigener Uhr-App.
///
/// Die Uhr hat ihren eigenen Schluesselbund; an die geteilte Gruppe des iPhones
/// kommt sie nicht heran. Deshalb geht der Token einmal hier hinueber - der
/// Haupt-Token liegt damit auch auf der Uhr (docs/ENTSCHEIDUNGEN.md, 14.10.).
@MainActor
final class WatchLink {

    static let shared = WatchLink()

    private let relay = WatchLinkRelay()
    private var pendingSnapshot: ComplicationSnapshot?
    private var lastSent: ComplicationSnapshot?
    private var sendTask: Task<Void, Never>?

    private init() {}

    private var session: WCSession? {
        guard WCSession.isSupported() else { return nil }
        return WCSession.default
    }

    /// Beim Start der App (`AppDelegate`) - die Uhr kann jederzeit etwas schicken.
    func activate() {
        guard let session else { return }
        relay.onActivated = {
            Task { @MainActor in WatchLink.shared.sendContext() }
        }
        session.delegate = relay
        session.activate()
    }

    /// Der Stand der Komplikation, kurz gebuendelt: wer drei Eintraege
    /// hintereinander anlegt, verbraucht nicht drei der etwa fuenfzig
    /// Komplikations-Uebertragungen eines Tages.
    func send(snapshot: ComplicationSnapshot) {
        guard snapshot.consumedKcal != lastSent?.consumedKcal || snapshot.targetKcal != lastSent?.targetKcal
                || snapshot.date != lastSent?.date else { return }
        pendingSnapshot = snapshot
        sendTask?.cancel()
        sendTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    /// Der Token (und der letzte Stand) als Kontext - der gilt, bis ein neuer kommt.
    func sendContext() {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled
        else { return }
        var context: [String: Any] = [:]
        if let token = Keychain.read(Keychain.privateTokenKey), !token.isEmpty {
            context[WatchKeys.privateToken] = token
        }
        if let snapshot = lastSent ?? pendingSnapshot, let data = try? JSONEncoder().encode(snapshot) {
            context[WatchKeys.snapshot] = data
        }
        try? session.updateApplicationContext(context)
    }

    private func flush() {
        guard let snapshot = pendingSnapshot, let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        pendingSnapshot = nil
        lastSent = snapshot
        // Liegt die Komplikation auf dem Zifferblatt, weckt das die Uhr-App;
        // sonst reicht der Kontext, den sie beim naechsten Oeffnen liest.
        if session.isComplicationEnabled {
            session.transferCurrentComplicationUserInfo([WatchKeys.snapshot: data])
        }
        sendContext()
    }
}

/// Der Delegat von `WCSession` - WatchConnectivity ruft ihn auf einer eigenen
/// Warteschlange, deshalb nur Werte weiterreichen.
final class WatchLinkRelay: NSObject, WCSessionDelegate, @unchecked Sendable {

    nonisolated(unsafe) var onActivated: (@Sendable () -> Void)?

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
        // Uhr-App gerade installiert: Token und Stand hinterher.
        if session.isWatchAppInstalled { onActivated?() }
    }
}
