import Foundation
import UserNotifications

/// Die Erinnerung um 21:30 - eine lokale Mitteilung vom iPhone, kein Server
/// (Felix, 04.10.).
///
/// Nicht als taeglich wiederholte Mitteilung: von der laesst sich ein einzelner
/// Tag nicht abbestellen, und an einem beantworteten Abend soll nichts kommen.
/// Stattdessen je Tag eine eigene fuer die naechsten Wochen, neu verteilt bei
/// jeder Antwort und bei jedem Wechsel in den Vordergrund.
///
/// Der Text nennt keine Frage - er steht auf dem Sperrbildschirm.
enum EvaluationReminder {

    static let hour = 21
    static let minute = 30
    /// Wie weit im Voraus. iOS haelt hoechstens 64 Mitteilungen je App bereit;
    /// 30 lassen den anderen genug Platz und reichen fuer einen Monat ohne Oeffnen.
    static let horizonDays = 30
    static let identifierPrefix = "evaluation-"
    /// Woran der Benachrichtigungs-Delegat erkennt, welcher Tab aufgehen soll.
    static let kind = "evaluation"

    /// Die Tage, an denen um 21:30 eine Erinnerung kommen soll.
    static func days(for data: EvaluationData, now: Date, calendar: Calendar = .current) -> [CalendarDate] {
        guard !data.questions.isEmpty else { return [] }
        let today = CalendarDate(date: now, in: calendar.timeZone)
        let reminderToday = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        return (0..<horizonDays).compactMap { offset in
            let day = today.adding(days: offset)
            if offset == 0, now >= reminderToday || data.isComplete(on: day) { return nil }
            return day
        }
    }

    static func identifier(for day: CalendarDate) -> String { identifierPrefix + day.iso }

    /// Verteilt die Erinnerungen neu. Ohne Erlaubnis bleibt es still.
    static func schedule(_ data: EvaluationData, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        // Ist heute beantwortet, darf eine schon zugestellte Erinnerung weg.
        let today = CalendarDate(date: now)
        if data.isComplete(on: today) {
            center.removeDeliveredNotifications(withIdentifiers: [identifier(for: today)])
        }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        for day in days(for: data, now: now) {
            let content = UNMutableNotificationContent()
            content.title = "Evaluation"
            content.body = "Noch offen"
            content.sound = .default
            content.userInfo = ["kind": kind]
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(year: day.year, month: day.month, day: day.day,
                                             hour: hour, minute: minute),
                repeats: false)
            try? await center.add(UNNotificationRequest(identifier: identifier(for: day),
                                                        content: content, trigger: trigger))
        }
    }

    /// Beim Wechsel in den Vordergrund: die Datei lesen, ohne etwas anzuzeigen,
    /// und die Erinnerungen nachziehen - sonst laufen sie nach 30 Tagen aus, wenn
    /// der Tab so lange nicht offen war. Ist die Datei nicht lesbar (etwa weil
    /// das iPhone noch gesperrt ist), bleibt alles, wie es ist.
    static func refresh() async {
        let data: EvaluationData
        do {
            guard let stored = try EvaluationStore.read(EvaluationStore.defaultFile) else { return }
            data = stored
        } catch {
            return
        }
        await schedule(data)
    }
}
