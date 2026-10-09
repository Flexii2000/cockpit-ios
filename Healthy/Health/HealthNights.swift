import Foundation

/// Der Hauptschlaf eines Aufwachtags: eine Phase genau einer Quelle.
struct MainSleep: Sendable, Equatable {
    let date: CalendarDate
    let start: Date
    let end: Date
    /// Die Segmente der gewaehlten Quelle in der Phase - Schlaf und Wach.
    let segments: [SleepSegment]
}

/// Aus Schlafsegmenten und Messwerten werden Naechte - genau nach den Regeln
/// im Vertrag (`weight-app/docs/HEALTHY-CONTRACT.md` §2.2), die fuer iOS und
/// Android gleich sind. Weicht eine App ab, haetten dieselben Naechte auf zwei
/// Telefonen verschiedene Recovery-Werte.
///
/// Rein, ohne HealthKit: die Abfragen macht `HealthReader`, den Dirigenten
/// `HealthSync`. Die Herzfrequenz im Schlaf ist die eine Groesse, die erst nach
/// der Phase gefragt werden kann - sie kommt deshalb als fertige Zahl herein.
enum HealthNights {

    /// Segmente mit hoechstens so viel Abstand gehoeren zu einer Phase - eine
    /// Wachphase in der Nacht trennt sie nicht, ein Mittagsschlaf schon.
    static let maxGap: TimeInterval = 90 * 60
    /// HRV misst die Uhr oft kurz nach dem Aufwachen; die zaehlt noch zur Nacht.
    static let hrvTail: TimeInterval = 30 * 60
    /// Mehr nimmt der Dienst nicht an - eine ganze Anfrage scheiterte sonst an
    /// einer einzigen kaputten Nacht.
    static let maxMinutes = 1440

    /// Eine zusammenhaengende Schlafphase einer Quelle.
    struct Phase: Sendable, Equatable {
        let start: Date
        let end: Date
        let asleepSeconds: TimeInterval
    }

    /// Wer eine Phase geschrieben hat. Dieselbe App kann von iPhone und Uhr
    /// schreiben - dann sind das zwei Quellen.
    private struct SourceKey: Hashable, Comparable {
        let source: String
        let isWatch: Bool

        static func < (lhs: SourceKey, rhs: SourceKey) -> Bool {
            (lhs.source, lhs.isWatch ? 1 : 0) < (rhs.source, rhs.isWatch ? 1 : 0)
        }
    }

    // MARK: - Schritte 1 bis 3: welche Phase ist die Nacht?

    /// Die Hauptschlafphase je Aufwachtag.
    ///
    /// Je Quelle getrennt werden die Schlafsegmente zu Phasen gelegt und fuer
    /// jeden Tag D die Phase mit den meisten Schlafminuten gesucht, die **vor
    /// 12:00 an D beginnt und zwischen 03:00 und 16:00 an D endet**. Hat die
    /// Uhr so eine Phase, gilt nur die Uhr; sonst die Quelle, deren Phase die
    /// meisten Schlafminuten hat. Zwei Quellen werden nie vereinigt - iPhone
    /// und Uhr schreiben dieselbe Nacht, und zusammengelegt zaehlte sie doppelt.
    static func mainSleeps(_ segments: [SleepSegment], days: [CalendarDate],
                           timeZone: TimeZone = .current) -> [MainSleep] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let bySource = Dictionary(grouping: segments) { SourceKey(source: $0.source, isWatch: $0.isWatch) }
        let phasesBySource = bySource.mapValues { phases($0.filter(\.stage.isAsleep)) }
        let sources = phasesBySource.keys.sorted()

        return days.compactMap { day in
            let start = day.startOfDay(in: timeZone)
            guard let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: start),
                  let earliestEnd = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: start),
                  let latestEnd = calendar.date(bySettingHour: 16, minute: 0, second: 0, of: start)
            else { return nil }

            var candidates: [(key: SourceKey, phase: Phase)] = []
            for key in sources {
                let fitting = (phasesBySource[key] ?? []).filter {
                    $0.start < noon && $0.end >= earliestEnd && $0.end <= latestEnd
                }
                if let best = mostAsleep(fitting) { candidates.append((key, best)) }
            }
            let fromWatch = candidates.filter(\.key.isWatch)
            let pool = fromWatch.isEmpty ? candidates : fromWatch
            // Bei Gleichstand die erste in der sortierten Reihenfolge - so
            // ergibt derselbe Bestand immer dieselbe Nacht.
            guard let chosen = pool.max(by: { $0.phase.asleepSeconds < $1.phase.asleepSeconds
                                              || ($0.phase.asleepSeconds == $1.phase.asleepSeconds
                                                  && $0.key > $1.key) })
            else { return nil }

            let inPhase = (bySource[chosen.key] ?? []).filter {
                $0.stage != .inBed && $0.start < chosen.phase.end && $0.end > chosen.phase.start
            }
            return MainSleep(date: day, start: chosen.phase.start, end: chosen.phase.end, segments: inPhase)
        }
    }

    /// Schlafsegmente einer Quelle zu Phasen: was hoechstens `maxGap`
    /// auseinanderliegt (oder sich ueberlappt), gehoert zusammen.
    static func phases(_ sleep: [SleepSegment]) -> [Phase] {
        var groups: [[SleepSegment]] = []
        var groupEnd: Date?
        for segment in sleep.sorted(by: { $0.start < $1.start }) where segment.end > segment.start {
            if let end = groupEnd, segment.start.timeIntervalSince(end) <= maxGap {
                groups[groups.count - 1].append(segment)
                groupEnd = max(end, segment.end)
            } else {
                groups.append([segment])
                groupEnd = segment.end
            }
        }
        return groups.compactMap { group in
            guard let start = group.map(\.start).min(), let end = group.map(\.end).max() else { return nil }
            return Phase(start: start, end: end, asleepSeconds: unionSeconds(group, within: start...end))
        }
    }

    private static func mostAsleep(_ phases: [Phase]) -> Phase? {
        phases.max { $0.asleepSeconds < $1.asleepSeconds || ($0.asleepSeconds == $1.asleepSeconds && $0.start > $1.start) }
    }

    // MARK: - Schritte 4 bis 9: was in der Nacht steht

    /// Die Nacht zu einer Hauptschlafphase.
    ///
    /// - Parameters:
    ///   - inBed: Segmente „im Bett" **jeder** Quelle - das iPhone schreibt
    ///     sie nach dem Schlafplan, die Uhr seit watchOS 9 auch; vereinigt
    ///     zaehlt nichts doppelt.
    ///   - hrvRmssd: `nil` vor iOS 27 - dann kennt Health die Methode nicht.
    ///   - sleepingHeartRate: das zeitgewichtete Mittel ueber die Phase
    ///     (`HealthReader.average`).
    /// - Returns: `nil`, wenn die Phase nicht taugt (leer, laenger als ein Tag).
    static func night(_ main: MainSleep, inBed: [SleepSegment], hrvSdnn: [HealthReading],
                      hrvRmssd: [HealthReading]?, respiratory: [HealthReading],
                      sleepingHeartRate: Double?) -> Night? {
        let window = main.start...main.end
        let sleep = main.segments.filter(\.stage.isAsleep)
        let asleep = minutes(unionSeconds(sleep, within: window))
        guard main.end > main.start, asleep > 0, asleep <= maxMinutes else { return nil }

        // Stadien nur, wenn die Quelle in dieser Nacht welche kennt - sonst
        // waeren Nullen eine Behauptung ueber eine Nacht ohne Stadien.
        let staged = sleep.contains { [.core, .deep, .rem].contains($0.stage) }
        func stage(_ stage: SleepSegment.Stage) -> Int? {
            staged ? minutes(unionSeconds(sleep.filter { $0.stage == stage }, within: window)) : nil
        }
        let awakeSegments = main.segments.filter { $0.stage == .awake }
        let awake = staged || !awakeSegments.isEmpty
            ? minutes(unionSeconds(awakeSegments, within: window)) : nil

        let bed = inBed.filter { $0.stage == .inBed && $0.start < main.end && $0.end > main.start }
        let bedMinutes = bed.isEmpty ? nil : minutes(unionSeconds(bed, within: nil))

        let sdnn = hrv(hrvSdnn, main)
        let rmssd = hrvRmssd.flatMap { hrv($0, main) }

        return Night(date: main.date, sleepStart: main.start, sleepEnd: main.end,
                     asleepMinutes: asleep,
                     inBedMinutes: bedMinutes.flatMap { $0 <= maxMinutes ? $0 : nil },
                     awakeMinutes: awake,
                     deepMinutes: stage(.deep), remMinutes: stage(.rem), coreMinutes: stage(.core),
                     hrvSdnnMs: sdnn?.value, hrvSdnnSamples: sdnn?.count,
                     hrvRmssdMs: rmssd?.value, hrvRmssdSamples: rmssd?.count,
                     sleepingHeartRate: sleepingHeartRate.flatMap { plausible(round1($0), 20...220) },
                     respiratoryRate: respiratoryRate(respiratory, main),
                     source: "ios")
    }

    /// HRV einer Nacht: Messungen, die in [Schlafbeginn, Schlafende + 30 min]
    /// beginnen, Werte > 0, die der Uhr bevorzugt. Geometrisches Mittel - HRV
    /// ist schief verteilt, und die Recovery rechnet ohnehin auf der ln-Skala.
    static func hrv(_ readings: [HealthReading], _ main: MainSleep) -> (value: Double, count: Int)? {
        let end = main.end.addingTimeInterval(hrvTail)
        let inWindow = readings.filter { $0.start >= main.start && $0.start <= end && $0.value > 0 }
        let fromWatch = inWindow.filter(\.isWatch)
        let chosen = fromWatch.isEmpty ? inWindow : fromWatch
        guard let mean = geometricMean(chosen.map(\.value)),
              let value = plausible(round1(mean), 1...400) else { return nil }
        return (value, chosen.count)
    }

    /// Das Mittel der Atemfrequenz-Messungen, die in der Phase beginnen.
    static func respiratoryRate(_ readings: [HealthReading], _ main: MainSleep) -> Double? {
        let values = readings.filter { $0.start >= main.start && $0.start <= main.end && $0.value > 0 }
            .map(\.value)
        guard !values.isEmpty else { return nil }
        return plausible(round1(values.reduce(0, +) / Double(values.count)), 3...60)
    }

    /// `exp(Mittel(ln x))`; `nil` ohne Werte.
    static func geometricMean(_ values: [Double]) -> Double? {
        let positive = values.filter { $0 > 0 }
        guard !positive.isEmpty else { return nil }
        return exp(positive.map { log($0) }.reduce(0, +) / Double(positive.count))
    }

    // MARK: - Rechnerei

    /// Die Dauer der Vereinigung - ueberlappende Segmente zaehlen einmal.
    /// Mit `window` nur der Teil darin.
    static func unionSeconds(_ segments: [SleepSegment], within window: ClosedRange<Date>?) -> TimeInterval {
        let intervals = segments.compactMap { segment -> (Date, Date)? in
            let start = window.map { max(segment.start, $0.lowerBound) } ?? segment.start
            let end = window.map { min(segment.end, $0.upperBound) } ?? segment.end
            return end > start ? (start, end) : nil
        }.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for interval in intervals {
            if let open = current, interval.0 <= open.1 {
                current = (open.0, max(open.1, interval.1))
            } else {
                if let open = current { total += open.1.timeIntervalSince(open.0) }
                current = interval
            }
        }
        if let open = current { total += open.1.timeIntervalSince(open.0) }
        return total
    }

    /// Minuten ganz, wie im Vertrag.
    private static func minutes(_ seconds: TimeInterval) -> Int {
        Int((seconds / 60).rounded())
    }

    /// Eine Nachkommastelle, wie im Vertrag.
    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    /// Was der Dienst als unplausibel ablehnt, fehlt lieber - sonst scheiterte
    /// die ganze Anfrage an einer Messung.
    private static func plausible(_ value: Double, _ range: ClosedRange<Double>) -> Double? {
        range.contains(value) ? value : nil
    }
}
