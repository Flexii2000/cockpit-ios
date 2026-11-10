import Foundation

/// Was die Strain-Karte im Dashboard zeichnet (Vertrag §5, Felix 10.11.:
/// „0–21 mit Zielmarke“) - Texte, Anteile und Farbrollen als Werte.
///
/// Bewusst ohne SwiftUI, wie `EnergyCardModel`: die Sonderfaelle (heute noch
/// kein Puls, beim Kalibrieren kein Ziel, ueber dem Ziel, Woche mit Luecken)
/// lassen sich so pruefen, ohne sie im Simulator nachzustellen - der bekommt
/// keine Health-Daten. Gerechnet hat der Dienst; hier wird nur eingeteilt.
struct StrainCardModel: Equatable {

    /// Der Balken von heute, 0 bis 21. Alle Lagen sind Anteile seiner Laenge.
    struct Bar: Equatable {
        /// Bis wohin er gefuellt ist - 0, solange heute noch kein Histogramm da
        /// ist (`NO_DATA`): der Balken ist dann leer, die Marke steht trotzdem.
        let fill: Double
        /// Wo die Zielmarke steht; `nil` beim Kalibrieren - dann gibt es weder
        /// Marke noch einen Teil „über Ziel“.
        let target: Double?

        /// Der Teil in der Strain-Farbe: bis zum Strain, hoechstens bis zur Marke.
        var base: Double { target.map { min(fill, $0) } ?? fill }

        /// Der Teil hinter der Marke - in der Farbe „über Ziel“.
        var over: Double { target.map { max(fill - $0, 0) } ?? 0 }
    }

    /// Ein Tag der Woche.
    struct WeekBar: Equatable, Identifiable {
        let date: CalendarDate
        /// „Mo“ … „So“.
        let label: String
        /// Hoehe als Anteil der ganzen Hoehe (Strain ÷ 21). `nil` ist ein Tag
        /// ohne Wert: kein Balken.
        let height: Double?
        /// Heute steht blasser da - der Tag laeuft noch.
        let isToday: Bool

        var id: CalendarDate { date }
    }

    /// Gross: „12,4“ - `nil` ohne Strain heute, die Karte zeigt dann „–“.
    let value: String?
    /// Rechts daneben: „Ziel 14,1“ - fehlt beim Kalibrieren. Das Ziel gehoert
    /// zum Morgen des Tages und steht schon da, bevor der erste Puls kommt.
    let target: String?
    /// `nil` nur, wenn es weder einen Strain noch ein Ziel gibt.
    let bar: Bar?
    /// D−6 … D; `nil`, wenn kein Tag der Woche einen Wert hat.
    let week: [WeekBar]?
}

extension StrainCardModel {

    /// - Parameters:
    ///   - today: `GET /api/strain/today`. Faellt nur diese Abfrage aus, steht
    ///     derselbe Tag auch in der Woche - jede Abfrage des Dashboards faellt
    ///     fuer sich aus.
    ///   - week: `GET /api/strain?from=D−6&to=D`.
    /// - Returns: `nil`, wenn weder heute noch die Woche einen Strain hat -
    ///   dann fehlt die Karte.
    init?(today: StrainDay?, week: [StrainDay], on date: CalendarDate) {
        let byDate = Dictionary(week.map { ($0.date, $0) }, uniquingKeysWith: { _, newer in newer })
        let day = today ?? byDate[date]
        let strain = day?.strain
        let bars = (0...6).reversed().map { offset -> WeekBar in
            let each = date.adding(days: -offset)
            let value = each == date ? strain ?? byDate[each]?.strain : byDate[each]?.strain
            return WeekBar(date: each, label: EnergyCardModel.weekdayLabel(each),
                           height: value.map(StrainFormat.fraction), isToday: each == date)
        }
        let hasWeek = bars.contains { $0.height != nil }
        guard strain != nil || hasWeek else { return nil }
        let target = day?.targetStrain
        self.init(value: strain.map(StrainFormat.value),
                  target: target.map(StrainFormat.target),
                  // Ohne Histogramm heute ein leerer Balken mit der Marke -
                  // sobald es ein Ziel gibt.
                  bar: strain != nil || target != nil
                      ? Bar(fill: strain.map(StrainFormat.fraction) ?? 0, target: target.map(StrainFormat.fraction))
                      : nil,
                  week: hasWeek ? bars : nil)
    }

    /// Wie lang ein Wochenbalken gezeichnet wird: mindestens ein duenner
    /// Strich - sonst saehe ein ruhiger Tag aus wie einer ohne Uhr.
    static func barLength(_ share: Double, in height: Double) -> Double {
        max(share * height, EnergyCardModel.minimumBarLength)
    }
}
