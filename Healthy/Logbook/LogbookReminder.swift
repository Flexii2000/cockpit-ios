import Foundation
import UserNotifications

/// Die Erinnerung um 09:00 - „Logbook" / „gestern offen", eine lokale
/// Mitteilung vom iPhone, nur wenn am Vortag noch etwas offen ist (Felix,
/// 09.10.; seit 12.10. zaehlt jede Antwort fuer sich, Vertrag §4).
///
/// Wie bei der Evaluation (Fokus) nicht als taeglich wiederholte Mitteilung:
/// von der laesst sich ein einzelner Tag nicht abbestellen. Stattdessen je Tag
/// eine, neu verteilt nach jeder Antwort und bei jedem Wechsel in den
/// Vordergrund. Nur 14 Tage voraus: iOS haelt hoechstens 64 Mitteilungen je App
/// bereit (bis 14.10. belegte die Evaluation hier 30).
///
/// Der Text nennt keine Verhaltensweise - er steht auf dem Sperrbildschirm.
enum LogbookReminder {

    static let hour = 9
    static let minute = 0
    static let horizonDays = 14
    static let identifierPrefix = "logbook-"
    /// Woran der Benachrichtigungs-Delegat erkennt, wohin der Tipp fuehrt.
    static let kind = "logbook"

    /// Die Tage, an denen um 09:00 eine Erinnerung kommen soll - jeder, an dessen
    /// Vortag noch etwas offen ist. Heute nur, solange 09:00 noch kommt.
    static func days(complete: Set<CalendarDate>, now: Date, calendar: Calendar = .current) -> [CalendarDate] {
        let today = CalendarDate(date: now, in: calendar.timeZone)
        let reminderToday = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        return (0..<horizonDays).compactMap { offset in
            let day = today.adding(days: offset)
            if offset == 0, now >= reminderToday { return nil }
            if complete.contains(day.adding(days: -1)) { return nil }
            return day
        }
    }

    /// Die Kennung traegt den Tag, an dem sie kommt.
    static func identifier(for day: CalendarDate) -> String { identifierPrefix + day.iso }

    /// Verteilt die Erinnerungen neu. Ohne aktive Verhaltensweise gibt es
    /// nichts auszufuellen - dann keine. Ohne Erlaubnis bleibt es still.
    static func schedule(complete: Set<CalendarDate>, hasBehaviors: Bool, now: Date = Date()) async {
        #if DEBUG
        // Erfundene Tage duerfen keine echten Erinnerungen verschieben.
        if DashboardDemo.isOn { return }
        #endif
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        // Ist gestern beantwortet, darf die Erinnerung von heute frueh weg.
        let today = CalendarDate(date: now)
        if complete.contains(today.adding(days: -1)) {
            center.removeDeliveredNotifications(withIdentifiers: [identifier(for: today)])
        }
        guard hasBehaviors else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional else { return }

        for day in days(complete: complete, now: now) {
            let content = UNMutableNotificationContent()
            content.title = "Logbook"
            content.body = "gestern offen"
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

    /// Mit dem Stand des Dienstes und dem, was in der Warteschlange wartet - ein
    /// wartender Wert ist beantwortet, nur noch nicht beim Dienst.
    @MainActor
    static func schedule(_ overview: LogbookOverview, now: Date = Date()) async {
        let pending = PendingChanges.shared.changes(for: .weight).compactMap(\.logbook)
        await schedule(complete: LogbookDays.completeDays(overview, pending: pending),
                       hasBehaviors: !overview.active.isEmpty, now: now)
    }

    /// Beim Wechsel in den Vordergrund: den Stand holen (ohne Netz aus dem
    /// Cache) und die Erinnerungen nachziehen - sonst laufen sie nach 14 Tagen
    /// aus. Ist nichts zu bekommen, bleibt alles, wie es ist; kennt der Dienst
    /// kein Logbook (404), gibt es keine.
    @MainActor
    static func refresh() async {
        #if DEBUG
        if DashboardDemo.isOn { return }
        #endif
        do {
            await schedule(try await LogbookAPI().overview())
        } catch APIError.http(404, _) {
            await schedule(complete: [], hasBehaviors: false)
        } catch {
            return
        }
    }
}
