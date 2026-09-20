import UIKit
import UserNotifications

/// Push-Kennung entgegennehmen (fuer Erinnerungen des To-Do-Dienstes) und
/// einen Tipp auf eine Meldung zum passenden Tab fuehren.
final class AppDelegate: NSObject, UIApplicationDelegate {

    private let notifications = NotificationDelegate(onOpen: { kind in
        // „todo": Erinnerung des To-Do-Dienstes. „forest": „Baum gepflanzt"
        // am Ende einer Fokus-Session - der Tipp fuehrt in den Wald, und die
        // App raeumt dort die Session auf (Baum melden, „Fokus aus").
        switch kind {
        case "todo":   Task { @MainActor in Router.shared.show(.todo) }
        case "forest": Task { @MainActor in Router.shared.show(.forest) }
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
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Notifications.store(deviceToken: hex)
        // Sofort anmelden - der Endpunkt liegt nur hinter dem Privat-Cookie,
        // nicht hinter einer Anmeldung wie bei den Noten.
        Task { try? await TodoAPI().registerDevice(token: hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push-Anmeldung fehlgeschlagen: \(error.localizedDescription)")
    }
}
