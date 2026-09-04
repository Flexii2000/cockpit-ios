import UserNotifications

/// Was mit einer Benachrichtigung passiert - anzeigen, und beim Antippen
/// der App sagen, worum es ging.
///
/// Beide Rueckrufe als Completion-Handler-Variante, NICHT als `async`. Die
/// `async`-Fassung laeuft als `nonisolated` auf einem Hintergrund-Executor,
/// und die Fertig-Meldung, die Swift daraus fuer UIKit baut, kommt vom
/// falschen Thread: UIKit erledigt darin die Zustandssicherung der App und
/// bricht mit einer Assertion ab - jeder Tipp beendete die App (gefunden mit
/// tools/pushtest.sh, 03.09.2026).
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    /// Bekommt `kind` aus der Nutzlast (`"grade"` beim Notendienst, sonst
    /// nil) und entscheidet, welcher Tab sich oeffnet.
    private let onOpen: @Sendable (String?) -> Void

    init(onOpen: @escaping @Sendable (String?) -> Void) {
        self.onOpen = onOpen
    }

    /// Auch anzeigen, wenn die App gerade offen ist - sonst verschluckt iOS
    /// die Meldung im Vordergrund.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Nur die Art hinueberreichen: die Meldung selbst ist nicht
        // versendbar, eine Zeichenkette schon.
        onOpen(response.notification.request.content.userInfo["kind"] as? String)
        completionHandler()
    }
}
