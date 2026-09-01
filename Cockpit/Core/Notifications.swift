import Foundation
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
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        case .denied:
            return false
        default:
            return true
        }
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
