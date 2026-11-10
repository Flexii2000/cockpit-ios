import Foundation

/// Das Mittel des Pulses in einer Kalenderminute - nur belegte Minuten gibt es
/// als Wert; eine Minute ohne Messung fehlt.
struct HeartMinute: Sendable, Equatable {
    /// Der Beginn der Minute.
    let start: Date
    let bpm: Double
}

/// Das Puls-Histogramm eines Tages aus Health - die Regeln aus dem Vertrag
/// (`weight-app/docs/HEALTHY-CONTRACT.md` §7.2), fuer iOS und Android gleich.
/// Rein, damit sie sich ohne Health pruefen lassen; gelesen wird in
/// `HealthReader.minuteAverages`.
///
/// Die App rechnet daraus nichts weiter: Last, Strain und Ziel entstehen im
/// Weight Tracker - so laesst sich die Formel aendern, ohne dass eine App neu
/// ausgerollt wird. Weicht diese Regel von der auf Android ab, rechnen die
/// beiden verschieden.
enum HealthHeart {

    /// Ein Minutenmittel darunter oder darueber gilt als nicht gemessen.
    static let validBpm = 25.0...250.0
    /// Die Breite eines Fachs in Schlaegen je Minute.
    static let binWidth = 5
    /// Das hoechste `fromBpm`, das der Dienst annimmt (§7.1).
    static let maxFromBpm = 220
    /// So lange gilt eine belegte Minute hoechstens - sie selbst und die
    /// unbelegten danach, bis zur naechsten belegten. Eine Uhr in Ruhe misst
    /// nur alle paar Minuten; laenger als das weiss niemand, wie der Puls war.
    static let hold: TimeInterval = 5 * 60
    /// Mehr nimmt der Dienst je Tag nicht an - ein Tag mit Zeitumstellung hat
    /// 25 Stunden.
    static let maxCoverageMinutes = 1500.0

    /// Bei jedem Abgleich: heute und gestern.
    static let recentDays = 2
    /// Das ganze Fenster D−13 … D - die aelteren Tage hoechstens alle sechs
    /// Stunden oder beim Ziehen.
    static let windowDays = 14
    static let windowInterval: TimeInterval = 6 * 3600
    /// Einmalig so weit zurueck, in Bloecken zu sieben Tagen, neueste zuerst.
    static let backfillDays = 425
    static let blockDays = 7

    /// Das Fach eines Pulses: das Vielfache von fuenf darunter.
    static func bin(_ bpm: Double) -> Int {
        Int((bpm / Double(binWidth)).rounded(.down)) * binWidth
    }

    /// Bis wohin fuer einen Tag gelesen wird: bis Mitternacht, heute bis
    /// jetzt. `nil`, wenn der Tag noch gar nicht begonnen hat.
    static func dayEnd(_ date: CalendarDate, now: Date, in timeZone: TimeZone = .current) -> Date? {
        let start = date.startOfDay(in: timeZone)
        guard start < now else { return nil }
        return min(date.adding(days: 1).startOfDay(in: timeZone), now)
    }

    /// Die Histogramme mehrerer Tage aus einer Abfrage. Tage ohne Abdeckung
    /// fehlen - sie werden nicht geschickt (§7.2 Punkt 5).
    static func days(_ dates: [CalendarDate], minutes: [HeartMinute], now: Date,
                     in timeZone: TimeZone = .current) -> [HeartDayUpload] {
        let sorted = minutes.sorted { $0.start < $1.start }
        return dates.sorted().compactMap { day($0, sorted: sorted, now: now, in: timeZone) }
    }

    /// Das Histogramm eines Tages:
    ///
    /// 1. Ein Minutenmittel unter 25 oder ueber 250 gilt als nicht gemessen.
    /// 2. Eine belegte Minute zaehlt fuer sich und fuer die unbelegten Minuten
    ///    danach bis zur naechsten belegten, zusammen hoechstens fuenf Minuten -
    ///    gekappt an der Mitternacht des Tages und an `now`.
    /// 3. Fach = floor(bpm / 5) · 5; `fromBpm` ist das kleinste belegte Fach,
    ///    `minutes` reicht bis zum groessten, auf eine Nachkommastelle gerundet.
    /// 4. `coverageMinutes` ist ihre Summe.
    ///
    /// - Parameter minutes: die belegten Minuten - auch die anderer Tage
    ///   duerfen dabei sein, sie zaehlen hier nicht.
    /// - Returns: `nil`, wenn der Tag keine Abdeckung hat.
    static func day(_ date: CalendarDate, minutes: [HeartMinute], now: Date,
                    in timeZone: TimeZone = .current) -> HeartDayUpload? {
        day(date, sorted: minutes.sorted { $0.start < $1.start }, now: now, in: timeZone)
    }

    private static func day(_ date: CalendarDate, sorted: [HeartMinute], now: Date,
                            in timeZone: TimeZone) -> HeartDayUpload? {
        let start = date.startOfDay(in: timeZone)
        guard let cut = dayEnd(date, now: now, in: timeZone) else { return nil }
        let measured = sorted.filter { validBpm.contains($0.bpm) && $0.start >= start && $0.start < cut }
        guard !measured.isEmpty else { return nil }

        var seconds: [Int: Double] = [:]
        for (index, minute) in measured.enumerated() {
            var end = min(minute.start.addingTimeInterval(hold), cut)
            if index + 1 < measured.count { end = min(end, measured[index + 1].start) }
            // Ganze Sekunden, wie auf Android - sonst rundete der angebrochene
            // Rest von heute auf den beiden Geraeten verschieden.
            let held = end.timeIntervalSince(minute.start).rounded(.down)
            if held > 0 { seconds[bin(minute.bpm), default: 0] += held }
        }
        // Erst runden, dann zuschneiden: ein Fach, das auf 0,0 rundet, ist
        // nicht belegt.
        let rounded = seconds.mapValues { round1($0 / 60) }.filter { $0.value > 0 }
        guard let lowest = rounded.keys.min(), let highest = rounded.keys.max() else { return nil }
        // Der Dienst nimmt `fromBpm` nur bis 220 an und liesse sonst die ganze
        // Anfrage scheitern - ein Tag, der nur aus Messfehlern weit oben
        // besteht, beginnt deshalb dort, mit leeren Faechern davor.
        let from = min(lowest, maxFromBpm)
        let bins = stride(from: from, through: highest, by: binWidth).map { rounded[$0] ?? 0 }
        // Die gerundeten Faecher koennen zusammen ein paar Zehntel ueber dem
        // Tag liegen; am 25-Stunden-Tag einer durchgehend getragenen Uhr
        // lehnte der Dienst sonst alles ab.
        let coverage = min(round1(bins.reduce(0, +)), maxCoverageMinutes)
        return HeartDayUpload(date: date, coverageMinutes: coverage, fromBpm: from, minutes: bins)
    }

    /// Eine Nachkommastelle - mehr ist Rauschen, und gleiche Tage sehen gleich
    /// aus.
    private static func round1(_ minutes: Double) -> Double {
        (minutes * 10).rounded() / 10
    }
}
