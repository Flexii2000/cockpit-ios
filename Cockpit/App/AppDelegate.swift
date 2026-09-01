import HealthKit
import UIKit

/// Nur fuer das, was beim Start passieren muss, bevor die Oberflaeche steht.
///
/// HealthKit stellt seine Weckrufe nur zu, wenn zu diesem Zeitpunkt eine
/// Beobachtung eingetragen ist. Wird die App im Hintergrund geweckt, gibt es
/// gar keine Oberflaeche - eine `.task` an einer View liefe dann nie.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        HealthSync.shared.startObserving()
        return true
    }

    /// iOS liefert die Push-Kennung als rohe Bytes; der Server erwartet sie
    /// hexadezimal - so schreibt Apple sie auch in seinen eigenen Werkzeugen.
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { try? await FoodAPI().registerDevice(token: hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Kein Grund, den Start zu stoeren: ohne Push fragt die App weiter
        // selbst nach, solange sie laeuft.
        print("Push-Anmeldung fehlgeschlagen: \(error.localizedDescription)")
    }
}
