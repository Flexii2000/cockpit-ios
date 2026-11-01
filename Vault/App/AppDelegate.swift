import UIKit
import UserNotifications

/// Push-Kennung entgegennehmen und einen Tipp auf „Neue Note …" zu den Noten,
/// einen auf eine Budget-Meldung (`"tab": "aws"`) zu den AWS-Kosten fuehren.
final class AppDelegate: NSObject, UIApplicationDelegate {

    private let notifications = NotificationDelegate(onOpen: { kind in
        switch kind {
        case "grade": Task { @MainActor in Router.shared.show(.grades) }
        case "aws": Task { @MainActor in Router.shared.show(.aws) }
        default: break
        }
    })

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = notifications
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Nur merken: angemeldet wird die Kennung beim Notendienst erst, wenn
        // eine Sitzung steht - der Endpunkt liegt hinter der Anmeldung.
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Notifications.store(deviceToken: token)
        // Der AWS-Dienst braucht keine Sitzung - die Kennung kann gleich hin. Nach
        // der ersten Erlaubnis kommt sie erst, wenn der Tab laengst geladen hat.
        Task { await AWSPush.registerIfNeeded(privateToken: Keychain.read(Keychain.privateTokenKey)) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push-Anmeldung fehlgeschlagen: \(error.localizedDescription)")
    }
}
