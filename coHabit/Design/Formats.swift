import Foundation
import SwiftUI

/// Datum und Uhrzeit - das Einzige, was die App selbst formatiert
/// (Vertrag §1.4). Alles andere kommt als fertiger Text vom Dienst.
enum Formats {

    private static let locale = Locale(identifier: "de_DE")

    private static func formatter(_ format: String, zone: TimeZone = .current) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter
    }

    /// „07:12"
    static func time(_ date: Date) -> String {
        formatter("HH:mm").string(from: date)
    }

    /// „30.09., 14:02" - fuer „Stand: …".
    static func stamp(_ date: Date) -> String {
        formatter("dd.MM., HH:mm").string(from: date)
    }

    /// „30.09.2026"
    static func date(_ day: CalendarDate) -> String {
        String(format: "%02d.%02d.%04d", day.day, day.month, day.year)
    }

    /// „30.09."
    static func shortDate(_ day: CalendarDate) -> String {
        String(format: "%02d.%02d.", day.day, day.month)
    }

    /// „Heute", „Gestern" oder „Mittwoch, 24. September" - die Tagesabschnitte
    /// in Timeline und Chat.
    static func dayTitle(_ day: CalendarDate, today: CalendarDate = .today()) -> String {
        if day == today { return "Heute" }
        if day == today.adding(days: -1) { return "Gestern" }
        let date = day.startOfDay()
        if day.year == today.year {
            return formatter("EEEE, d. MMMM").string(from: date)
        }
        return formatter("d. MMMM yyyy").string(from: date)
    }

    /// Wochentag kurz: „Mo", „Di" … - fuer das Wochenraster.
    static func weekdayShort(_ day: CalendarDate) -> String {
        let text = formatter("EEEEEE").string(from: day.startOfDay())
        return text.replacingOccurrences(of: ".", with: "")
    }

    /// „14:02" heute, sonst „29.09., 14:02".
    static func relativeStamp(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? time(date) : stamp(date)
    }
}

extension PersonView {
    /// „Du" fuer die angemeldete Person - so zeigen es die Entwuerfe in
    /// Ranglisten, Wochenraster und Avataren. Das Profil zeigt den echten Namen.
    func label(me: String?) -> String {
        id == me ? "Du" : displayName
    }
}

/// Wer angemeldet ist - fuer „Du" in Listen und Avataren.
private struct MeIdKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var meId: String? {
        get { self[MeIdKey.self] }
        set { self[MeIdKey.self] = newValue }
    }
}
