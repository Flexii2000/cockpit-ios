import HealthKit
import UIKit
import UserNotifications

/// Nur fuer das, was beim Start passieren muss, bevor die Oberflaeche steht.
///
/// HealthKit stellt seine Weckrufe nur zu, wenn zu diesem Zeitpunkt eine
/// Beobachtung eingetragen ist. Wird die App im Hintergrund geweckt, gibt es
/// gar keine Oberflaeche - eine `.task` an einer View liefe dann nie.
final class AppDelegate: NSObject, UIApplicationDelegate {

    /// Beim Antippen nichts umschalten: Essen ist ohnehin der erste Tab, und
    /// die Schnellerfassung ist das Einzige, was sich hier meldet.
    private let notifications = NotificationDelegate(onOpen: { _ in })

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        HealthSync.shared.startObserving()
        // Muss hier stehen und nicht in einer `.task`: iOS reicht den Tipp auf
        // eine Benachrichtigung gleich nach dem Start durch.
        UNUserNotificationCenter.current().delegate = notifications
        return true
    }

    /// iOS liefert die Push-Kennung als rohe Bytes; der Server erwartet sie
    /// hexadezimal - so schreibt Apple sie auch in seinen eigenen Werkzeugen.
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Notifications.store(deviceToken: hex)
        Task { try? await FoodAPI().registerDevice(token: hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Kein Grund, den Start zu stoeren: ohne Push fragt die App weiter
        // selbst nach, solange sie laeuft.
        print("Push-Anmeldung fehlgeschlagen: \(error.localizedDescription)")
    }
}
