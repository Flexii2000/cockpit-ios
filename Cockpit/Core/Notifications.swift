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
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
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
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
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
