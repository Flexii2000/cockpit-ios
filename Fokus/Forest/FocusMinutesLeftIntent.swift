import AppIntents
import Foundation

/// „Fokus-Restminuten": eine Aktion fuer die Kurzbefehle-App, die sagt, wie
/// lange die laufende Session noch geht - 0, wenn keine laeuft.
///
/// Der Weg zum Fokus-Modus **ohne** Sprung in die Kurzbefehle-App: eine
/// Automation „Wenn Fokus geschlossen wird" laeuft seit iOS 17 still im
/// Hintergrund; ihr Kurzbefehl fragt hier die Restminuten ab und befristet
/// den Fokus-Modus damit. Die App selbst darf den Modus nicht schalten, und
/// einen Kurzbefehl kann sie nur mit sichtbarem Sprung starten - eine
/// Automation kann es fuer sie tun, sobald sie die Endzeit kennt.
/// Liest die Session aus der App-Gruppe (`FocusHandoff`), die App muss dafuer
/// nicht im Vordergrund sein.
struct FocusMinutesLeftIntent: AppIntent {

    static let title: LocalizedStringResource = "Fokus-Restminuten"
    static let description = IntentDescription(
        "Wie viele Minuten die laufende Fokus-Session noch hat. 0, wenn keine läuft.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let minutes = FocusHandoff.loadSession().map { session in
            max(0, Int(ceil(session.end.timeIntervalSinceNow / 60)))
        } ?? 0
        return .result(value: minutes)
    }
}

/// Macht die Aktion in der Kurzbefehle-App unter „Fokus" auffindbar.
struct FokusShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FocusMinutesLeftIntent(),
                    phrases: ["Fokus-Restminuten in \(.applicationName)"],
                    shortTitle: "Restminuten",
                    systemImageName: "tree")
    }
}
