import DeviceActivity
import ManagedSettings
import UserNotifications
import WidgetKit

/// Haelt den Schild einer Fokus-Session, auch wenn die App laengst beendet
/// ist. iOS startet diese Erweiterung selbst, wenn das bei
/// `DeviceActivityCenter.startMonitoring` angemeldete Intervall beginnt oder
/// endet.
///
/// **Anfang:** den Schild (neu) legen. Die App legt ihn beim Pflanzen selbst;
/// hier kommt er noch einmal - und vor allem nach einem Neustart des Handys,
/// denn den ueberlebt der Schild nicht, das Intervall aber schon: iOS ruft
/// `intervalDidStart` dann erneut. Session und erlaubte Apps stehen in der
/// App-Gruppe (`FocusHandoff`).
///
/// **Ende:** Schild weg, und die Meldung zum Ende der Session (feste Kennung,
/// von der App vorgeplant) durch „Apps wieder frei" ersetzen - steht das in
/// der Mitteilung, ist die Erweiterung gelaufen. Den Baum meldet die App,
/// sobald sie wieder laeuft (`ForestStore.reconcile`): die Erweiterung hat
/// weder Zugang zum Keychain der App noch einen Grund, ins Netz zu gehen.
///
/// Der Store ist der Vorgabe-Store ohne Namen, denselben teilt sich die App
/// mit ihren Erweiterungen.
final class FocusSessionMonitor: DeviceActivityMonitor {

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard let session = FocusHandoff.loadSession(), !session.isOver() else { return }
        FocusHandoff.applyShield(except: Whitelist.load(), to: ManagedSettingsStore())
    }

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
            UNNotificationRequest(identifier: FocusHandoff.endNotificationID, content: content, trigger: nil))
        // Die Kachel zeigt sonst „0:00", bis die App das naechste Mal laeuft.
        WidgetCenter.shared.reloadTimelines(ofKind: "FocusCountdown")
    }
}
