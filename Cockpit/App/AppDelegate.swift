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

    /// Auch anzeigen, wenn die App gerade offen ist.
    ///
    /// Ohne das verschluckt iOS die Meldung im Vordergrund. Beim
    /// Kalorienzaehler faellt das nicht auf - dort fragt die App ohnehin
    /// nach. Eine neue Note dagegen kaeme nie an, waehrend man in der App
    /// haengt.
    ///
    /// `nonisolated`, weil dieser Delegat - anders als der der App - nicht an
    /// den Hauptfaden gebunden ist. Ohne das Schluesselwort verlangt Swift 6,
    /// dass `UNNotification` versendbar waere; sie ist es nicht.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Ein Tipp auf die Meldung fuehrt dorthin, wovon sie handelt.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Die Art hier herausziehen und nur sie hinueberreichen: die Meldung
        // selbst ist nicht versendbar, eine Zeichenkette schon.
        let kind = response.notification.request.content.userInfo["kind"] as? String
        guard kind == "grade" else { return }
        await MainActor.run { Router.shared.show(.grades) }
    }
}
