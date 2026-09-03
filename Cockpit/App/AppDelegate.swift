import HealthKit
import UIKit
import UserNotifications

/// Nur fuer das, was beim Start passieren muss, bevor die Oberflaeche steht.
///
/// HealthKit stellt seine Weckrufe nur zu, wenn zu diesem Zeitpunkt eine
/// Beobachtung eingetragen ist. Wird die App im Hintergrund geweckt, gibt es
/// gar keine Oberflaeche - eine `.task` an einer View liefe dann nie.
///
/// Dazu die Benachrichtigungen: welcher Tab sich oeffnet, wenn jemand eine
/// antippt.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        HealthSync.shared.startObserving()
        // Muss hier stehen und nicht in einer `.task`: iOS reicht den Tipp auf
        // eine Benachrichtigung gleich nach dem Start durch. Steht der
        // Empfaenger dann noch nicht, ist die Meldung verloren.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// iOS liefert die Push-Kennung als rohe Bytes; der Server erwartet sie
    /// hexadezimal - so schreibt Apple sie auch in seinen eigenen Werkzeugen.
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Notifications.store(deviceToken: hex)
        Task { try? await FoodAPI().registerDevice(token: hex) }
        // Die Notenuebersicht meldet die Kennung selbst an, sobald sie eine
        // Sitzung hat - ihr Endpunkt liegt hinter der Anmeldung, und die
        // steht beim Start noch nicht.
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Kein Grund, den Start zu stoeren: ohne Push fragt die App weiter
        // selbst nach, solange sie laeuft.
        print("Push-Anmeldung fehlgeschlagen: \(error.localizedDescription)")
    }

    // MARK: - Benachrichtigungen

    /// Beide Rueckrufe als Completion-Handler-Variante, NICHT als `async`.
    ///
    /// Der Grund ist ein Absturz, den der Simulator-Test gefunden hat: die
    /// `async`-Fassung laeuft als `nonisolated` auf einem Hintergrund-Executor,
    /// und die Fertig-Meldung, die Swift daraus fuer UIKit baut, kommt damit
    /// vom falschen Thread. UIKit erledigt darin die Zustandssicherung der App
    /// und bricht mit einer Assertion ab - jeder Tipp auf eine Meldung
    /// beendete die App. Mit dem Completion-Handler wird er auf dem Thread
    /// gerufen, auf dem der Rueckruf kam. `nonisolated`, weil die Klasse
    /// ueber `UIApplicationDelegate` an den Hauptakteur gebunden ist und die
    /// Meldung selbst nicht versendbar ist; der Hauptakteur kommt nur fuer das
    /// Umschalten des Tabs ins Spiel.

    /// Auch anzeigen, wenn die App gerade offen ist. Ohne das verschluckt iOS
    /// die Meldung im Vordergrund - eine neue Note kaeme nie an, waehrend man
    /// in der App haengt.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Ein Tipp auf die Meldung fuehrt dorthin, wovon sie handelt.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Die Art hier herausziehen und nur sie hinueberreichen: die Meldung
        // selbst ist nicht versendbar, eine Zeichenkette schon.
        let kind = response.notification.request.content.userInfo["kind"] as? String
        if kind == "grade" {
            Task { @MainActor in Router.shared.show(.grades) }
        }
        completionHandler()
    }
}
