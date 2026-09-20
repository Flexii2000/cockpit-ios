import DeviceActivity
import ManagedSettings

/// Nimmt am Ende einer Fokus-Session den Schild weg - auch wenn die App
/// laengst beendet ist. iOS startet diese Erweiterung selbst, wenn das bei
/// `DeviceActivityCenter.startMonitoring` angemeldete Intervall endet.
///
/// Mehr tut sie nicht. Den Baum meldet die App, sobald sie wieder laeuft
/// (`ForestStore.reconcile`): die Erweiterung hat weder Zugang zum Keychain
/// der App noch einen Grund, ins Netz zu gehen.
///
/// Der Name des Intervalls (`fokus.session`) steht genauso in
/// `Fokus/Forest/ScreenTimeGuard.swift` - die Erweiterung uebersetzt keine
/// App-Datei, deshalb an zwei Stellen. Der Store ist der Vorgabe-Store ohne
/// Namen, denselben teilt sich die App mit ihren Erweiterungen.
final class FocusSessionMonitor: DeviceActivityMonitor {

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        ManagedSettingsStore().clearAllSettings()
    }
}
