import Foundation

/// Was die Energie-Karte im Dashboard zeichnet (Vertrag §5, Felix 09.10.:
/// „Balken + Woche") - Laengen, Hoehen, Farbrollen und Beschriftungen als
/// Werte.
///
/// Bewusst ohne SwiftUI: die Karte steht als Erstes im Bild, und ihre
/// Sonderfaelle (nichts gegessen, Ueberschuss, Tag ohne Wert, Prognose,
/// leere Woche) lassen sich so pruefen, ohne sie im Simulator nachzustellen -
/// der bekommt keine Health-Daten. Die View setzt nur noch um.
struct EnergyCardModel: Equatable {

    /// Gross oben: das Wort in Textfarbe, der Betrag in Defizit- bzw.
    /// Ueberschuss-Farbe.
    struct Headline: Equatable {
        /// „Defizit" oder „Überschuss" - nach dem gerundeten Wert.
        let word: String
        /// „≈ 690 kcal"
        let amount: String
        let isSurplus: Bool
    }

    /// Der Bilanzbalken. Alle Lagen sind Anteile seiner Laenge, und die ist
    /// max(Verbrauch, gegessen) - so reicht immer eins von beiden ans Ende.
    struct BalanceBar: Equatable {
        /// Von links: gegessen, hoechstens bis zum Verbrauch - kcal-Farbe.
        let eaten: Double
        /// Die Luecke von „gegessen" bis zum Verbrauch - Defizit-Farbe.
        let gap: Double
        /// Was ueber den Verbrauch hinaus gegessen wurde - Ueberschuss-Farbe.
        let overflow: Double
        /// Wo die Marke des Verbrauchs steht.
        let mark: Double
        /// „gegessen 2.150", links darunter.
        let eatenLabel: String
        /// „Verbrauch ≈ 2.840", rechts darunter.
        let expenditureLabel: String
    }

    /// Ein Tag der Woche.
    struct WeekBar: Equatable, Identifiable {
        let date: CalendarDate
        /// „Mo" … „So".
        let label: String
        /// Hoehe als Anteil der ganzen Hoehe. `nil` ist ein Tag ohne Wert:
        /// kein Balken. Ein Tag mit 0 hat 0 und wird trotzdem gezeichnet -
        /// als duenner Strich (`barLength`).
        let height: Double?
        /// Nach unten in Ueberschuss-Farbe statt nach oben in Defizit-Farbe.
        let isSurplus: Bool

        var id: CalendarDate { date }
    }

    /// Die sieben vollen Tage D−7 … D−1 an einer Nulllinie, dazu „⌀ 7 T" ueber
    /// dieselben Tage. Heute steht im Bilanzbalken (Felix, 09.10.).
    struct Week: Equatable {
        let bars: [WeekBar]
        /// Lage der Nulllinie, von oben gemessen: 1 ist unten (kein
        /// Ueberschuss in der Woche), 0 oben (kein Defizit), sonst im
        /// Verhaeltnis groesstes Defizit : groesster Ueberschuss.
        let zeroLine: Double
        /// `deficit7` der Summary: „460 kcal", „−120 kcal", ohne Wert „–".
        let average: String
    }

    /// `nil` ohne Defizit heute - dann fehlen Kopfzeile und Balken.
    let headline: Headline?
    let bar: BalanceBar?
    /// `nil`, wenn kein Tag der Woche einen Wert hat.
    let week: Week?
}

extension EnergyCardModel {

    /// - Parameters:
    ///   - summary: `GET /api/energy/summary` - der Tag heute und `deficit7`.
    ///   - week: `GET /api/energy?from=D−7&to=D` - heute nur fuer Kopfzeile und
    ///     Balken, falls die Summary fehlt.
    /// - Returns: `nil` ohne Defizit heute und ohne Wert in der Woche - dann
    ///   fehlt die Karte (§5 Punkt 5).
    init?(summary: EnergySummary?, week: [EnergyDay], today: CalendarDate) {
        // Heute aus der Summary. Faellt nur sie aus, steht derselbe Tag auch
        // in der Woche - jede Abfrage des Dashboards faellt fuer sich aus.
        let current = summary?.today ?? week.first { $0.date == today }
        let headline = current.flatMap(Self.headline)
        let bar = current.flatMap(Self.balanceBar)
        let days = Self.week(week, today: today, average: summary?.deficit7)
        guard headline != nil || days != nil else { return nil }
        self.init(headline: headline, bar: bar, week: days)
    }

    static func headline(_ day: EnergyDay) -> Headline? {
        EnergyFormat.balance(day).map { Headline(word: $0.word, amount: $0.amount, isSurplus: $0.isSurplus) }
    }

    /// Nur mit einem Defizit heute (§5 Punkt 3) - und damit mit Verbrauch:
    /// ohne ihn rechnet der Dienst keins.
    static func balanceBar(_ day: EnergyDay) -> BalanceBar? {
        guard day.deficitKcal != nil, let expenditure = day.expenditureKcal,
              let expenditureLabel = EnergyFormat.expenditureShort(day) else { return nil }
        // Ohne Eintrag ist bisher nichts gegessen - so rechnet der Dienst.
        let eaten = max(day.intakeKcal ?? 0, 0)
        let length = max(expenditure, eaten)
        guard length > 0 else { return nil }
        return BalanceBar(eaten: min(eaten, expenditure) / length,
                          gap: max(expenditure - eaten, 0) / length,
                          overflow: max(eaten - expenditure, 0) / length,
                          mark: expenditure / length,
                          eatenLabel: EnergyFormat.eaten(day),
                          expenditureLabel: expenditureLabel)
    }

    /// Die sieben vollen Tage bis gestern an **einer** Skala fuer beide
    /// Richtungen: der groesste Betrag jeder Richtung reicht an ihren Rand.
    /// Heute bleibt draussen - die Prognose waere morgens fast der ganze
    /// Verbrauch und stauchte die uebrigen Tage.
    /// - Parameter average: `deficit7` der Summary - dieselben sieben Tage.
    static func week(_ days: [EnergyDay], today: CalendarDate, average: Double?) -> Week? {
        let dates = (-7 ... -1).map { today.adding(days: $0) }
        let byDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { _, newer in newer })
        // Gerundet wie die Zahlen: was auf 0 rundet, ist kein Ueberschuss -
        // dieselbe Regel wie beim Wort in der Kopfzeile.
        let values = dates.map { byDate[$0]?.deficitKcal?.rounded() }
        guard values.contains(where: { $0 != nil }) else { return nil }
        let present = values.compactMap { $0 }
        let largestDeficit = present.map { max($0, 0) }.max() ?? 0
        let largestSurplus = present.map { max(-$0, 0) }.max() ?? 0
        let span = largestDeficit + largestSurplus
        let bars = zip(dates, values).map { date, value in
            WeekBar(date: date,
                    label: weekdayLabel(date),
                    height: value.map { span > 0 ? abs($0) / span : 0 },
                    isSurplus: (value ?? 0) < 0)
        }
        return Week(bars: bars,
                    zeroLine: span > 0 ? largestDeficit / span : 1,
                    average: average.map(EnergyFormat.kcal) ?? "–")
    }

    /// Wie lang ein Balken gezeichnet wird: mindestens ein duenner Strich -
    /// sonst saehe ein Tag mit 0 aus wie einer ohne Wert (Android: 2 dp).
    static func barLength(_ share: Double, in height: Double) -> Double {
        max(share * height, minimumBarLength)
    }

    static let minimumBarLength: Double = 2

    /// „Mo" … „So".
    static func weekdayLabel(_ date: CalendarDate) -> String {
        // Der Wochentag haengt nur am Kalendertag - in UTC gerechnet, damit
        // keine Zeitzone ihn auf den Vortag schiebt.
        let utc = TimeZone(identifier: "UTC") ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let weekday = calendar.component(.weekday, from: date.startOfDay(in: utc))
        return ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"][(weekday + 6) % 7]
    }
}
