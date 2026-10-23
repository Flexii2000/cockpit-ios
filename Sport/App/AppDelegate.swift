import UIKit

/// Nur fuer das, was beim Start passieren muss, bevor die Oberflaeche steht.
///
/// Startet die Uhr ein Krafttraining, weckt iOS die App im Hintergrund - ohne Oberflaeche,
/// eine `.task` an einer View liefe dann nie.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Der Handler fuer die gespiegelte Session muss dann schon stehen.
        WorkoutMirror.shared.install()
        SportWatchLink.shared.activate()
        return true
    }
}
