import DeviceActivity
import ManagedSettings
import UserNotifications

/// Nimmt am Ende einer Fokus-Session den Schild weg - auch wenn die App
/// laengst beendet ist. iOS startet diese Erweiterung selbst, wenn das bei
/// `DeviceActivityCenter.startMonitoring` angemeldete Intervall endet.
///
/// Danach sagt sie es: die Meldung zum Ende der Session (feste Kennung
/// `forest.end`, von der App vorgeplant) wird durch „Apps wieder frei"
/// ersetzt. Steht das in der Mitteilung, ist die Erweiterung gelaufen; steht
/// weiter „Baum gepflanzt", war nur die App da. Mehr tut sie nicht. Den Baum
/// meldet die App, sobald sie wieder laeuft (`ForestStore.reconcile`): die
/// Erweiterung hat weder Zugang zum Keychain der App noch einen Grund, ins
/// Netz zu gehen.
///
/// Der Name des Intervalls (`fokus.session`) und die Kennung der Meldung
/// stehen genauso in `Fokus/Forest/` - die Erweiterung uebersetzt keine
/// App-Datei, deshalb an zwei Stellen. Der Store ist der Vorgabe-Store ohne
/// Namen, denselben teilt sich die App mit ihren Erweiterungen.
final class FocusSessionMonitor: DeviceActivityMonitor {

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        ManagedSettingsStore().clearAllSettings()

        let content = UNMutableNotificationContent()
        content.title = "Apps wieder frei"
        content.body = "Die Session ist vorbei."
        content.sound = .default
        content.userInfo = ["kind": "forest"]
        content.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "forest.end", content: content, trigger: nil))
    }
}
