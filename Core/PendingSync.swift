import Foundation
import Network

/// Wann die Warteschlange (`PendingChanges`) und der alte Postausgang nachsenden:
/// beim Start, zurueck im Vordergrund und sobald wieder Netz da ist. Dazu kommt,
/// was die Warteschlange selbst tut - sofort nach dem Eintragen, nach jeder
/// Antwort eines Dienstes und nach einem Fehlschlag mit wachsendem Abstand.
///
/// Kein Hintergrund-Senden: Fokus und Einkaufsliste schicken beim naechsten
/// Oeffnen oder sobald das Netz zurueck ist, waehrend die App vorn ist.
@MainActor
enum PendingSync {

    private static var monitor: NWPathMonitor?
    private static var lastKick: ContinuousClock.Instant?

    /// Einmal je App, nachdem die Cookies gesetzt sind - vorher kaeme jedes
    /// Nachsenden als „kein Zugang“ zurueck.
    static func start() {
        PendingChanges.shared.onNotice = { text, isInfo in
            NoticeCenter.shared.show(text, isInfo: isInfo)
        }
        NoticeWindow.install()
        if monitor == nil {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                guard path.status == .satisfied else { return }
                Task { @MainActor in networkReturned() }
            }
            monitor.start(queue: DispatchQueue(label: "com.fherrmann.pending-sync"))
            self.monitor = monitor
        }
        Task { await sendEverything() }
    }

    /// `scenePhase` der App: im Vordergrund von vorn versuchen, sonst ruhen.
    static func foreground(_ active: Bool) {
        PendingChanges.shared.isForeground = active
        guard active else { return }
        NoticeWindow.install()
        PendingChanges.shared.resetBackoff()
        Task { await sendEverything() }
    }

    /// Das Netz meldet sich oft mehrmals kurz hintereinander - einmal je Sekunde reicht.
    private static func networkReturned() {
        let now = ContinuousClock.now
        if let lastKick, now - lastKick < .seconds(1) { return }
        lastKick = now
        PendingChanges.shared.resetBackoff()
        Task {
            // Kurz warten: direkt nach dem Wechsel ins Netz scheitert die erste
            // Anfrage oft noch an DNS.
            try? await Task.sleep(for: .seconds(1))
            await sendEverything()
        }
    }

    private static func sendEverything() async {
        await PendingChanges.shared.replayAll()
        await Outbox.shared.replay()
    }
}
