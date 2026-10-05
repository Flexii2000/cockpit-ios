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
    /// Bekommt `link` aus der Nutzlast, wenn eine dabei ist - bisher nur bei
    /// Fokus (Feature Requests ueber das To-Do). Wer ihn nicht uebergibt,
    /// uebergeht den Link.
    private let onLink: (@Sendable (URL) -> Void)?

    init(onOpen: @escaping @Sendable (String?) -> Void,
         onLink: (@Sendable (URL) -> Void)? = nil) {
        self.onOpen = onOpen
        self.onLink = onLink
    }

    /// Nur http(s): was in der Nutzlast steht, kommt vom Server, und ein
    /// anderes Schema oeffnete womoeglich eine fremde App.
    static func link(in userInfo: [AnyHashable: Any]) -> URL? {
        guard let raw = userInfo["link"] as? String,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host() != nil
        else { return nil }
        return url
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
        // Nur die Art (und den Link) hinueberreichen: die Meldung selbst ist
        // nicht versendbar, eine Zeichenkette schon.
        let userInfo = response.notification.request.content.userInfo
        onOpen(userInfo["kind"] as? String)
        if let onLink, let link = Self.link(in: userInfo) {
            onLink(link)
        }
        completionHandler()
    }
}
