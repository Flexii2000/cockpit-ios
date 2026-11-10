import Foundation

/// Ein Balken im Verlauf: der Strain eines Tages.
struct StrainBarSample: Identifiable, Equatable, Sendable {
    let day: CalendarDate
    let date: Date
    let strain: Double
    /// Heute - der Tag laeuft noch und steht blasser da.
    let isPartial: Bool

    var id: Date { date }
}

/// Ein Punkt auf der Linie „Akut“: ein Tag mit Recovery, in der Farbe ihres
/// Bands.
struct StrainRecoveryDot: Identifiable, Equatable, Sendable {
    let date: Date
    let value: Double
    let band: RecoveryBand

    var id: Date { date }
}

/// Aufbereitung der beiden Diagramme im Strain-Fenster (Vertrag §5) - wie
/// `RecoveryChartData` neben der View, damit sie sich pruefen laesst. Die
/// Werte kommen fertig aus dem Dienst; hier wird nur in Balken, Laeufe und
/// Flaechen eingeteilt.
enum StrainChartData {

    /// „Strain“: je Tag mit Histogramm ein Balken. Tage ohne fehlen - dort
    /// laufen nur Ziel und Form weiter.
    static func bars(_ days: [StrainDay], in timeZone: TimeZone = .current) -> [StrainBarSample] {
        days.sorted { $0.date < $1.date }.compactMap { day in
            day.strain.map {
                StrainBarSample(day: day.date, date: day.date.startOfDay(in: timeZone), strain: $0,
                                isPartial: day.partial)
            }
        }
    }

    /// Das Ziel als Stufenlinie. Es gehoert zum Morgen des Tages und laeuft
    /// deshalb auch ueber Tage ohne Histogramm; nur wo es keins gibt (beim
    /// Kalibrieren), reisst die Linie ab.
    static func targetRuns(_ days: [StrainDay], in timeZone: TimeZone = .current) -> [ChartRun] {
        runs(days, key: "ziel", in: timeZone, value: \.targetStrain)
    }

    /// „Akut“ - das gewichtete Mittel der Last, 7 Tage.
    static func acuteRuns(_ days: [StrainDay], in timeZone: TimeZone = .current) -> [ChartRun] {
        runs(days, key: "akut", in: timeZone, value: \.acuteLoad)
    }

    /// „Gewohnt“ - das gewichtete Mittel der Last, 28 Tage.
    static func chronicRuns(_ days: [StrainDay], in timeZone: TimeZone = .current) -> [ChartRun] {
        runs(days, key: "gewohnt", in: timeZone, value: \.chronicLoad)
    }

    private static func runs(_ days: [StrainDay], key: String, in timeZone: TimeZone,
                             value: KeyPath<StrainDay, Double?>) -> [ChartRun] {
        DaySeries.runs(days.compactMap { day in day[keyPath: value].map { DayValue(date: day.date, value: $0) } },
                       key: key, in: timeZone)
    }

    /// Die Flaeche zwischen „Akut“ und „Gewohnt“, nach dem gefaerbt, was oben
    /// liegt; am Schnittpunkt wechselt die Farbe (`EnergyBand`).
    ///
    /// In den Stuecken ist `expenditure` „Akut“ und `intake` „Gewohnt“:
    /// `isDeficit` heisst hier also **Akut liegt darueber** - die Farbe „über
    /// Ziel“.
    static func formSegments(_ days: [StrainDay], in timeZone: TimeZone = .current) -> [BandSegment] {
        func averages(_ value: KeyPath<StrainDay, Double?>) -> [DayAverage] {
            days.compactMap { day in
                day[keyPath: value].map { DayAverage(date: day.date, kcal: $0, days: 1, complete: true) }
            }
        }
        return EnergyBand.segments(expenditure: averages(\.acuteLoad), intake: averages(\.chronicLoad),
                                   in: timeZone)
    }

    /// Je Tag mit Recovery ein Punkt auf der Akut-Linie.
    static func recoveryDots(_ days: [StrainDay], in timeZone: TimeZone = .current) -> [StrainRecoveryDot] {
        days.sorted { $0.date < $1.date }.compactMap { day in
            guard let band = day.recoveryBand, band != .unknown, let acute = day.acuteLoad else { return nil }
            return StrainRecoveryDot(date: day.date.startOfDay(in: timeZone), value: acute, band: band)
        }
    }

    /// Die y-Achse der Form-Kurve: von 0 bis knapp ueber den groessten Wert,
    /// auf runde 50 - so springt sie nicht mit jedem Tag.
    static func loadDomain(_ days: [StrainDay]) -> ClosedRange<Double> {
        let highest = days.flatMap { [$0.acuteLoad, $0.chronicLoad] }.compactMap { $0 }.max() ?? 0
        let top = max(100, ((highest * 1.05) / 50).rounded(.up) * 50)
        return 0...top
    }

    /// Die Tage, auf die sich eine Beruehrung zuordnen laesst: alle mit einem
    /// Wert in einem der beiden Diagramme.
    static func selectableDays(_ days: [StrainDay]) -> [CalendarDate] {
        days.filter { $0.strain != nil || $0.targetStrain != nil || $0.acuteLoad != nil || $0.chronicLoad != nil }
            .map(\.date).sorted()
    }

    /// Was die Sprechblase im Verlauf zeigt: `Strain 12,4`, `Ziel 14,1` - was
    /// es davon gibt.
    static func strainCallout(_ day: StrainDay) -> [(label: String, value: String)] {
        var lines: [(label: String, value: String)] = []
        if let strain = day.strain { lines.append(("Strain", StrainFormat.value(strain))) }
        if let target = day.targetStrain { lines.append(("Ziel", StrainFormat.value(target))) }
        return lines
    }

    /// Was die Sprechblase in der Form-Kurve zeigt: `Akut 118`, `Gewohnt 111`.
    static func formCallout(_ day: StrainDay) -> [(label: String, value: String)] {
        var lines: [(label: String, value: String)] = []
        if let acute = day.acuteLoad { lines.append(("Akut", StrainFormat.load(acute))) }
        if let chronic = day.chronicLoad { lines.append(("Gewohnt", StrainFormat.load(chronic))) }
        return lines
    }
}
