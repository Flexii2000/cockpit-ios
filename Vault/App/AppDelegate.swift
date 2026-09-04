import UIKit
import UserNotifications

/// Push-Kennung entgegennehmen und einen Tipp auf „Neue Note …" zu den Noten
/// fuehren.
final class AppDelegate: NSObject, UIApplicationDelegate {

    private let notifications = NotificationDelegate(onOpen: { kind in
        guard kind == "grade" else { return }
        Task { @MainActor in Router.shared.show(.grades) }
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
        Notifications.store(deviceToken: deviceToken.map { String(format: "%02x", $0) }.joined())
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push-Anmeldung fehlgeschlagen: \(error.localizedDescription)")
    }
}
