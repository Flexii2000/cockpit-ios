import Foundation

/// Ein Eintrag in „Geplant“: ein Tag mit einem Mitspieler - bei Serien alle Zeiten und Clubs
/// dieses Abends (Felix, 15.10.: „1 pro Tag“; seit 23.10. je Mitspieler).
struct PadelDay: Identifiable, Equatable, Sendable {
    let date: String
    let weekday: String
    let partner: String?
    let partnerColor: String?
    let occurrences: [PadelOccurrence]

    var id: String { "\(date)|\(partner ?? "")" }
    var isSingle: Bool { occurrences.count == 1 }
}

/// Was die Seite aus den Terminen macht - wie `app.js` des Dienstes, damit Seite und App
/// dasselbe sagen. Rechnen tut der Dienst; hier wird nur gruppiert und beschriftet.
enum PadelPlan {

    /// Termine, an denen sich noch etwas tut.
    static let open: Set<String> = ["PLANNED", "WATCHING", "BOOKING", "AWAITING_APPROVAL"]

    /// Von Felix oder dem Mitspieler ausgesetzt - nicht vom Dienst, weil schon gebucht ist.
    static func skippedByPerson(_ o: PadelOccurrence) -> Bool {
        o.status == "SKIPPED" && (o.note ?? "").hasPrefix("ausgesetzt von")
    }

    /// Die Tage, um die es noch geht: etwas ist offen, oder jemand hat ihn ausgesetzt. Ein
    /// Eintrag je Tag und Mitspieler, in der Reihenfolge der Termine.
    static func days(_ occurrences: [PadelOccurrence], now: Date) -> [PadelDay] {
        var order: [String] = []
        var groups: [String: [PadelOccurrence]] = [:]
        for o in occurrences {
            let key = "\(o.date)|\(o.partner ?? "")"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(o)
        }
        return order.compactMap { key in
            guard let group = groups[key], let first = group.first else { return nil }
            let relevant = group.contains { open.contains($0.status) || (skippedByPerson($0) && $0.watchUntil > now) }
            guard relevant else { return nil }
            return PadelDay(date: first.date, weekday: first.weekday, partner: first.partner,
                            partnerColor: first.partnerColor, occurrences: group)
        }
    }

    /// Die frueheste Anfangszeit.
    static func earliest(_ occurrences: [PadelOccurrence]) -> String {
        occurrences.map(\.start).min() ?? ""
    }

    /// Wie es bei einem Club an dem Tag steht - `key` vergleicht Clubs, `text` zeigt es.
    static func clubState(_ group: [PadelOccurrence]) -> (key: String, text: String, release: Date?) {
        if group.contains(where: { $0.status == "BOOKED" }) { return ("booked", "gebucht", nil) }
        if let first = group.filter({ $0.status == "PLANNED" }).map(\.releaseAt).min() {
            return ("planned \(first.timeIntervalSince1970)", "Freigabe " + PadelFormat.when(first), first)
        }
        if group.contains(where: { $0.status == "WATCHING" }) { return ("watching", "rückt nach", nil) }
        if let skipped = group.first(where: skippedByPerson) { return ("skipped", skipped.note ?? "", nil) }
        return ("done", "", nil)
    }

    /// Eine Zeile fuer einen Tag: bei gleichem Stand ohne Clubnamen, der Rueckfall nur, solange
    /// er gebraucht wird.
    static func summary(_ day: PadelDay) -> String {
        let all = day.occurrences
        if let urgent = all.first(where: { $0.status == "AWAITING_APPROVAL" }) ?? all.first(where: { $0.status == "BOOKING" }) {
            return status(urgent)
        }
        var clubs: [String] = []
        for o in all where !clubs.contains(o.club) { clubs.append(o.club) }
        let main = clubs.filter { club in all.contains { $0.club == club && !$0.fallback } }
        let states = main.map { club in (club, clubState(all.filter { $0.club == club && !$0.fallback })) }
            .filter { $0.1.key != "done" }
        var parts: [String]
        if states.count > 1, states.allSatisfy({ $0.1.key == states[0].1.key }) {
            parts = [states[0].1.text]
        } else {
            parts = states.map { states.count > 1 ? "\($0.0) \($0.1.text)" : $0.1.text }
        }
        for club in clubs where !main.contains(club) {
            let state = clubState(all.filter { $0.club == club })
            if let release = state.release {
                parts.append("Rückfall \(club) " + PadelFormat.when(release))
            } else if state.key == "watching" || state.key == "booked" {
                parts.append("Rückfall \(club) \(state.text)")
            }
        }
        return parts.joined(separator: " · ")
    }

    /// Wie ein Termin steht.
    static func status(_ o: PadelOccurrence) -> String {
        let note = o.note.map { " · \($0)" } ?? ""
        switch o.status {
        case "PLANNED": return "Freigabe " + PadelFormat.when(o.releaseAt, seconds: true)
        case "SKIPPED":
            if let raw = o.note, raw.hasPrefix("ausgesetzt") { return raw }
            return "ausgesetzt" + note
        case "BOOKING": return "Buchung läuft …"
        case "AWAITING_APPROVAL": return "Zahlung freigeben"
        case "WATCHING": return "rückt nach bis " + PadelFormat.when(o.watchUntil) + note
        case "BOOKED": return "gebucht · Platz \(o.court ?? "?")"
        case "MISSED": return "verpasst" + note
        case "CANCELLED": return "storniert" + note
        default: return o.status
        }
    }

    /// Die Termine des Tages und Mitspielers von `next` - fuer „Nächster Termin“.
    static func day(of next: PadelOccurrence, in occurrences: [PadelOccurrence]) -> [PadelOccurrence] {
        occurrences.filter { $0.date == next.date && $0.partner == next.partner }
    }

    /// Die Clubs, die zur selben Zeit wie `next` freigeben (bei Serien mitte und Padelon).
    static func together(_ next: PadelOccurrence, day: [PadelOccurrence]) -> [String] {
        var clubs: [String] = []
        for o in day where o.releaseAt == next.releaseAt {
            let label = o.fallback ? "Rückfall \(o.club)" : o.club
            if !clubs.contains(label) { clubs.append(label) }
        }
        return clubs
    }

    /// „Mo · 18:00 bis 21:30 · 90′“
    static func title(_ series: PadelSeries) -> String {
        var time = series.start
        if let latest = series.latestStart, latest != series.start { time += " bis \(latest)" }
        return "\(series.weekdayLabel) · \(time) · \(series.durationMinutes)′"
    }

    /// Unter einer Buchung: oeffentlich oder wie lange kostenlos stornierbar, dazu was noch fehlt.
    static func bookingLine(_ booking: PadelBooking) -> String {
        let state = booking.isPublic ? "öffentlich"
            : booking.cancellable ? "kostenlos stornierbar bis " + PadelFormat.when(booking.freeCancellationUntil)
            : "nicht mehr kostenlos stornierbar"
        return [state, booking.publishBlocker].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Formate in Berliner Zeit, wie auf der Seite.
enum PadelFormat {

    private static let zone = TimeZone(identifier: "Europe/Berlin") ?? .current
    private static let weekdays = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]

    /// „Fr 23.10. 19:00“, mit Sekunden „Fr 23.10. 19:00:00“.
    static func when(_ date: Date, seconds: Bool = false) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let p = calendar.dateComponents([.weekday, .day, .month, .hour, .minute, .second], from: date)
        let day = weekdays[((p.weekday ?? 1) - 1) % 7]
        let time = seconds
            ? String(format: "%02d:%02d:%02d", p.hour ?? 0, p.minute ?? 0, p.second ?? 0)
            : String(format: "%02d:%02d", p.hour ?? 0, p.minute ?? 0)
        return String(format: "%@ %02d.%02d. %@", day, p.day ?? 1, p.month ?? 1, time)
    }

    /// „Fr 06.11.“ aus „2026-11-06“ und „Fr“.
    static func dayLabel(_ isoDate: String, _ weekday: String) -> String {
        let parts = isoDate.split(separator: "-")
        guard parts.count == 3 else { return isoDate }
        return "\(weekday) \(parts[2]).\(parts[1]).".trimmingCharacters(in: .whitespaces)
    }

    /// „in 1 T 02:03:04“, unter einem Tag „in 02:03:04“, danach „läuft“.
    static func countdown(to target: Date, now: Date) -> String {
        let total = Int(target.timeIntervalSince(now))
        guard total > 0 else { return "läuft" }
        let days = total / 86_400
        let hms = String(format: "%02d:%02d:%02d", (total % 86_400) / 3600, (total % 3600) / 60, total % 60)
        return days > 0 ? "in \(days) T \(hms)" : "in \(hms)"
    }

    /// „16.88 EUR“ → „16,88 € p. P.“ (bei geteilter Zahlung der Anteil je Spieler).
    static func price(_ raw: String?, split: Bool) -> String? {
        guard let raw else { return nil }
        let number = raw.replacingOccurrences(of: " EUR", with: "")
        let text: String
        if let value = Double(number) {
            text = value.formatted(.number.precision(.fractionLength(value.rounded() == value ? 0 : 2))
                .locale(Locale(identifier: "de_DE"))) + " €"
        } else {
            text = raw
        }
        return split ? text + " p. P." : text
    }
}
