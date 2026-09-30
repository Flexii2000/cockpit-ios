import SwiftUI
import UIKit
import UserNotifications

/// Die Push-Kennung beim Dienst anmelden (`POST /devices`, Vertrag §3.9).
enum PushRegistration {

    struct DeviceRequest: Encodable {
        let token: String
        let platform: String
    }

    /// Nach dem Einfuegen eines Links: jetzt ist der Moment, nach der
    /// Erlaubnis zu fragen - Stupser und Beweisfotos sind der halbe Sinn.
    @MainActor
    static func afterSignIn() async {
        _ = await Notifications.requestPermission()
        await registerStoredDevice()
    }

    /// Bei jedem Start: iOS vergibt die Kennung gelegentlich neu.
    @MainActor
    static func registerStoredDevice() async {
        #if DEBUG
        // Wie in den anderen Apps: sonst meldet jeder Testlauf eine
        // Simulator-Kennung beim Dienst an.
        if ProcessInfo.processInfo.environment["COCKPIT_NO_PUSH"] == "1" { return }
        #endif
        guard Session.shared.isSignedIn, let token = Notifications.deviceToken else { return }
        try? await Session.shared.api().sendIgnoringResponse(
            "POST", "/devices", body: DeviceRequest(token: token, platform: "ios"))
    }
}

/// Push-Kennung entgegennehmen und einen Tipp auf eine Meldung dorthin
/// fuehren, wohin ihr `link` zeigt (Vertrag §4).
final class AppDelegate: NSObject, UIApplicationDelegate {

    private let notifications = CohabitNotificationDelegate()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Hier und nicht in einer `.task`: iOS reicht den Tipp auf eine
        // Meldung gleich nach dem Start durch.
        UNUserNotificationCenter.current().delegate = notifications
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Notifications.store(deviceToken: hex)
        Task { await PushRegistration.registerStoredDevice() }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push-Anmeldung fehlgeschlagen: \(error.localizedDescription)")
    }
}

/// Wie `NotificationDelegate` in Core - aber mit dem Link statt nur der Art.
/// Beide Rueckrufe als Completion-Handler, nicht `async`: die `async`-Fassung
/// laeuft auf einem Hintergrund-Executor, und UIKit bricht in der
/// Fertig-Meldung mit einer Assertion ab (siehe CLAUDE.md).
final class CohabitNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Neue Nachrichten und Haken sollen die offenen Bildschirme auffrischen.
        Task { @MainActor in DataBus.shared.changed() }
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Nur die Zeichenkette hinueberreichen - die Meldung ist nicht versendbar.
        let link = response.notification.request.content.userInfo["link"] as? String
        if let link, let url = URL(string: link) {
            Task { @MainActor in Router.shared.open(url) }
        } else {
            Task { @MainActor in Router.shared.open(.today) }
        }
        completionHandler()
    }
}
