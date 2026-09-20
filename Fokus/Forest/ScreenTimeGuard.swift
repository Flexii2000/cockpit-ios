import DeviceActivity
import FamilyControls
import ManagedSettings
import Foundation

/// Die Sperre: waehrend einer Session sind alle Apps bis auf die erlaubten
/// gesperrt. Drei Apple-Bausteine, ein Zweck:
///
/// * **FamilyControls** fragt einmal die Erlaubnis („Bildschirmzeit") ab.
/// * **ManagedSettings** legt den Schild auf alle App-Kategorien - bis auf die
///   Ausnahmen aus dem Whitelist-Blatt.
/// * **DeviceActivity** ruft am Ende der Session die Erweiterung
///   `FokusMonitor` - die nimmt den Schild weg, auch wenn die App laengst
///   beendet ist. Die App raeumt zusaetzlich selbst auf, sobald sie nach dem
///   Ende wieder laeuft: doppelt haelt besser, und der Rueckruf der
///   Erweiterung kommt laut Apple „zeitnah", nicht auf die Sekunde.
///
/// Der Store ist der Vorgabe-Store ohne Namen - genau den teilt sich die App
/// mit ihren Erweiterungen (so macht es auch Apples Beispiel), und
/// `FokusMonitor` leert ihn am Ende komplett.
@MainActor
final class ScreenTimeGuard {

    /// Der Name der Ueberwachung. Steht genauso in FokusMonitor - die
    /// Erweiterung uebersetzt keine App-Datei, deshalb zweimal.
    static let activity = DeviceActivityName("fokus.session")

    private let store = ManagedSettingsStore()
    private let center = DeviceActivityCenter()

    /// Im Simulator gibt es keine Bildschirmzeit - der Schalter laesst den
    /// Ablauf trotzdem durchspielen, fuer Screenshots und die Oberflaeche.
    var isDisabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["COCKPIT_NO_SCREENTIME"] == "1"
        #else
        return false
        #endif
    }

    var isAuthorised: Bool {
        isDisabled || AuthorizationCenter.shared.authorizationStatus == .approved
    }

    /// Fragt nach, wenn noch nicht entschieden. Wirft, wenn Felix ablehnt -
    /// dann gibt es keine Session, denn ohne Sperre ist es kein Fokus.
    func authorise() async throws {
        if isDisabled { return }
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    /// Schild drauf und das Ende bei DeviceActivity anmelden.
    ///
    /// Reihenfolge mit Absicht: erst der Schild - der gilt sofort und ist der
    /// Kern der Sache. Schlaegt danach die Anmeldung des Endes fehl, bleibt
    /// die Session trotzdem gueltig; dann raeumt eben die App selbst auf,
    /// sobald sie wieder laeuft (siehe ForestStore.reconcile).
    func shield(except allowed: FamilyActivitySelection, until session: ActiveSession) throws {
        if isDisabled { return }
        store.shield.applicationCategories = .all(except: allowed.applicationTokens)
        store.shield.webDomainCategories = .all(except: allowed.webDomainTokens)
        // Einzelne Apps aus dem Blatt zusaetzlich freilassen - `applications`
        // sperrt sonst nichts, die Kategorien haben schon alles abgedeckt.
        store.shield.applications = nil
        store.shield.webDomains = nil

        let calendar = Calendar.current
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(parts, from: session.start),
            intervalEnd: calendar.dateComponents(parts, from: session.end),
            repeats: false)
        try center.startMonitoring(Self.activity, during: schedule)
    }

    /// Schild weg. Idempotent - darf so oft aufgerufen werden, wie es Wege
    /// zum Ende gibt (Erweiterung, Timer in der App, naechster Start).
    func lift() {
        if isDisabled { return }
        store.clearAllSettings()
        center.stopMonitoring([Self.activity])
    }
}
