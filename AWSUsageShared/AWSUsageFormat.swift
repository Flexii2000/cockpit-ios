import Foundation

/// Deutsche Schreibweise für die AWS-Zahlen - „19,01 $“, „38 %“, „0,2394 $/h“.
///
/// Fest auf `de_DE` statt der Geräte-Einstellung: Vault und die Menüleiste
/// sollen dieselbe Zahl gleich schreiben, und die Tests brauchen eine feste
/// Schreibweise. Zwischen Zahl und Einheit ein geschütztes Leerzeichen, damit
/// „$“ nie allein in die nächste Zeile rutscht.
enum AWSUsageFormat {

    static let locale = Locale(identifier: "de_DE")
    private static let nbsp = "\u{00A0}"

    /// „19,01 $“ - immer zwei Nachkommastellen.
    static func dollars(_ value: Double) -> String {
        number(value, min: 2, max: 2) + nbsp + "$"
    }

    /// Das Budget: „50 $“, mit Nachkommastellen nur, wenn es welche hat („62,50 $“).
    static func limit(_ value: Double) -> String {
        let cents = (value * 100).rounded()
        let whole = cents.truncatingRemainder(dividingBy: 100) == 0
        return number(value, min: whole ? 0 : 2, max: whole ? 0 : 2) + nbsp + "$"
    }

    /// „1,86 $/h“, „0,2394 $/h“ - zwei bis vier Nachkommastellen, wie der Dienst sie
    /// liefert; ohne Preis „– $/h“, damit man in der Zeile noch sieht, was fehlt.
    static func perHour(_ value: Double?) -> String {
        guard let value else { return "–" + nbsp + "$/h" }
        return number(value, min: 2, max: 4) + nbsp + "$/h"
    }

    /// „38 %“ - ganze Prozent wie in der Claude Usage Bar; ohne Wert „–“.
    static func percent(_ value: Double?) -> String {
        guard let value else { return "–" }
        return number(value, min: 0, max: 0) + nbsp + "%"
    }

    /// Was in der Menüleiste steht: „38 % · 19,01 $“, ohne Daten „–“.
    static func menuBarTitle(_ usage: AWSUsage?) -> String {
        guard let usage else { return "–" }
        guard let percent = usage.percent else { return dollars(usage.spent) }
        return "\(Self.percent(percent)) · \(dollars(usage.spent))"
    }

    /// „November 2026“ aus „2026-11“; was nicht passt, bleibt, wie es kam.
    static func monthTitle(_ month: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let number = Int(parts[1]),
              (1...12).contains(number) else { return month }
        let names = DateFormatter()
        names.locale = locale
        return "\(names.standaloneMonthSymbols[number - 1]) \(year)"
    }

    /// Ein Zeitpunkt für den Stand: „15:00“ heute, „gestern 15:00“, sonst „31.10. 15:00“.
    static func time(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let clock = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened)
            .locale(locale))
        if calendar.isDate(date, inSameDayAs: now) { return clock }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "gestern \(clock)"
        }
        let day = calendar.component(.day, from: date)
        let month = calendar.component(.month, from: date)
        return String(format: "%02d.%02d. ", day, month) + clock
    }

    /// Laufzeit einer Instanz: „35 min“, „2:03 h“, „3 T 4 h“.
    static func runtime(from start: Date, to end: Date = Date()) -> String {
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        if minutes < 60 { return "\(minutes)\(nbsp)min" }
        let hours = minutes / 60
        if hours < 48 { return String(format: "%d:%02d", hours, minutes % 60) + nbsp + "h" }
        return "\(hours / 24)\(nbsp)T \(hours % 24)\(nbsp)h"
    }

    /// „Spot“ / „On-Demand“.
    static func lifecycle(_ instance: AWSInstance) -> String {
        instance.isSpot ? "Spot" : "On-Demand"
    }

    // MARK: - Spot

    /// Die Schätzung: „0 frei“, „≈ 4 frei“, an der obersten Stufe „8+ frei“.
    static func spotCount(_ estimate: Int, max: Int) -> String {
        if estimate <= 0 { return "0" + nbsp + "frei" }
        if estimate >= max { return "\(estimate)+" + nbsp + "frei" }
        return "≈" + nbsp + "\(estimate)" + nbsp + "frei"
    }

    /// „2a 9/10 · 2c 7/10“ - die Zonen kurz, die Region steht im Kopf; ohne Zonen „–“.
    static func spotZones(_ zones: [AWSSpotZone]) -> String {
        guard !zones.isEmpty else { return "–" }
        return zones.map { "\(zoneShort($0.zone))\(nbsp)\($0.score)/10" }.joined(separator: " · ")
    }

    /// „2a“ aus „eu-west-2a“.
    static func zoneShort(_ zone: String) -> String {
        zone.split(separator: "-").last.map(String.init) ?? zone
    }

    /// „London“ statt „eu-west-2“ für die Regionen, in denen etwas läuft.
    static func regionName(_ region: String) -> String {
        switch region {
        case "eu-west-2": "London"
        case "eu-central-1": "Frankfurt"
        default: region
        }
    }

    /// Liest eine Eingabe fürs Budget: „60“, „60,5“, „60.50“, „60 $“. `nil`, wenn
    /// sie nicht zwischen 0 (ausschließlich) und 10.000 liegt - so prüft auch der Dienst.
    static func parseLimit(_ text: String) -> Double? {
        var cleaned = text.replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: nbsp, with: "")
        // „1.250,50“: Punkt als Tausender, Komma als Dezimal.
        if cleaned.contains(",") {
            cleaned = cleaned.replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
        }
        guard let value = Double(cleaned), value > 0, value <= 10_000 else { return nil }
        return (value * 100).rounded() / 100
    }

    /// Das Budget fürs Eingabefeld: „50“ oder „62,5“ - ohne „$“, damit man gleich tippen kann.
    static func limitInput(_ value: Double) -> String {
        // Ohne Tausenderpunkt: „1.250“ läse `parseLimit` sonst als 1,25.
        value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(locale))
    }

    private static func number(_ value: Double, min: Int, max: Int) -> String {
        value.formatted(.number.precision(.fractionLength(min...max)).locale(locale))
    }
}
