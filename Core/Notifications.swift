import Foundation
import UIKit
import UserNotifications

/// Lokale Benachrichtigungen - kein Server, kein APNs.
///
/// Sie erreichen den Nutzer, solange die App noch laeuft oder gerade erst in
/// den Hintergrund gegangen ist. Liegt das Handy laenger gesperrt, friert iOS
/// die App ein und die Meldung kommt erst beim naechsten Oeffnen; dafuer
/// braeuchte es echtes Push und damit einen Dienst auf dem Server.
enum Notifications {

    /// Fragt einmalig nach Erlaubnis. Ein „nein" ist kein Fehler - dann gibt
    /// es eben keine Meldung, und der Vorschlag wartet in der App.
    @discardableResult
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            #if DEBUG
            // COCKPIT_ASK_PUSH=1 fragt trotz COCKPIT_NO_PUSH nach der
            // Erlaubnis - ohne sie zeigt der Simulator keine Benachrichtigung,
            // und tools/pushtest.sh haette nichts anzutippen. Angemeldet wird
            // deshalb noch lange nicht: die Kennung bliebe sonst wieder in
            // data/devices.json des food-Backends liegen.
            let environment = ProcessInfo.processInfo.environment
            let noPush = environment["COCKPIT_NO_PUSH"] == "1"
            if noPush, environment["COCKPIT_ASK_PUSH"] != "1" { return false }
            #endif
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            #if DEBUG
            if noPush { return granted }
            #endif
            if granted {
                // Erst ab hier darf ueberhaupt etwas zugestellt werden - also
                // auch erst ab hier beim Push-Dienst anmelden.
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
            return granted
        case .denied:
            return false
        default:
            return true
        }
    }

    /// Meldet das Geraet bei Apple an, wenn die Erlaubnis schon vorliegt.
    ///
    /// Bei jedem Start: iOS vergibt die Kennung gelegentlich neu, und eine
    /// veraltete faellt sonst erst auf, wenn eine Benachrichtigung ins Leere
    /// geht. Bewusst **ohne** Nachfrage - die kommt im Zusammenhang, wenn die
    /// erste Schnellerfassung laeuft.
    static func registerForPushIfAllowed() async {
        #if DEBUG
        // Simulator-Kennungen sind seit iOS 16 echt und landen in
        // data/devices.json auf dem Server. Ohne diesen Schalter meldet jeder
        // Testlauf eine neue an - Woche fuer Woche mehr, und bemerkt wuerde es
        // nur an der wachsenden Datei.
        if ProcessInfo.processInfo.environment["COCKPIT_NO_PUSH"] == "1" { return }
        #endif
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    }

    // MARK: - Die Kennung dieses Geraets

    /// Wo die zuletzt von Apple vergebene Push-Kennung liegt.
    ///
    /// Sie wird gemerkt, weil **zwei** Dienste sie brauchen und zu
    /// verschiedenen Zeitpunkten: der Kalorienzaehler nimmt sie beim Start
    /// entgegen, die Notenuebersicht erst, wenn eine Sitzung steht - ihr
    /// Endpunkt liegt hinter der Anmeldung. Kein Keychain: das ist kein
    /// Geheimnis, sondern eine Adresse, die Apple ohnehin kennt.
    private static let deviceTokenKey = "push.deviceToken"

    static var deviceToken: String? {
        UserDefaults.standard.string(forKey: deviceTokenKey)
    }

    static func store(deviceToken: String) {
        UserDefaults.standard.set(deviceToken, forKey: deviceTokenKey)
    }

    static func post(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Ohne Ausloeser wird sofort zugestellt.
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
