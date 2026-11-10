import Foundation

/// Der Wochenrueckblick als Text (Vertrag §5): sechs Felder, je mit einem Pfeil
/// gegen die Vorwoche. Gerechnet hat der Dienst; hier wird nur geschrieben und
/// verglichen, was dasteht.
///
/// Ohne SwiftUI, wie `EnergyCardModel` - die Faelle ohne Wert und die Pfeile
/// lassen sich so pruefen, ohne eine Woche nachzustellen.
struct WeekReviewCardModel: Equatable {

    /// Wohin der Wert gegen die Vorwoche ging. Eine Richtung, **keine Wertung**
    /// (Vertrag §5: in Textfarbe) - ob mehr kcal gut oder schlecht sind, haengt
    /// davon ab, was jemand vorhat.
    enum Arrow: Equatable {
        case up, down, same

        var systemImage: String {
            switch self {
            case .up:   "arrow.up"
            case .down: "arrow.down"
            case .same: "arrow.right"
            }
        }

        /// Fuer VoiceOver und die UI-Tests.
        var word: String {
            switch self {
            case .up:   "mehr"
            case .down: "weniger"
            case .same: "gleich"
            }
        }
    }

    /// Die Eiweiss-Tage: gruen (Ziel erreicht) und gelb (Erhalt erreicht).
    struct ProteinDays: Equatable {
        let green: Int
        let yellow: Int
    }

    struct Cell: Equatable, Identifiable {
        let title: String
        /// „–“ ohne Wert.
        let value: String
        let arrow: Arrow?
        /// Nur im Feld „Eiweiß-Tage“ - dort stehen statt `value` zwei Punkte mit Zahl.
        var protein: ProteinDays? = nil

        var id: String { title }
    }

    /// „02.11.–08.11.“
    let range: String
    let cells: [Cell]
}

extension WeekReviewCardModel {

    /// - Returns: `nil`, wenn die Woche keinen einzigen Wert hat - dann fehlt
    ///   die Karte (Vertrag §5).
    init?(_ review: WeekReview?) {
        guard let review else { return nil }
        let week = review.week
        let previous = review.previous
        let hasProtein = week.trackedDays > 0
        guard week.kcalAvg != nil || week.deficitAvg != nil || week.weightDeltaKg != nil || hasProtein
                || week.stepsAvg != nil || week.strainAvg != nil else { return nil }

        let cells = [
            Cell(title: "kcal ⌀",
                 value: week.kcalAvg.map(EnergyFormat.kcal) ?? "–",
                 arrow: Self.arrow(week.kcalAvg, previous?.kcalAvg, decimals: 0)),
            Cell(title: "Defizit ⌀",
                 value: week.deficitAvg.map(EnergyFormat.kcal) ?? "–",
                 arrow: Self.arrow(week.deficitAvg, previous?.deficitAvg, decimals: 0)),
            // Der Wert ist schon der Vergleich: das Mittel dieser Woche minus
            // das der Vorwoche. Der Pfeil zeigt dessen Richtung.
            Cell(title: "Gewicht",
                 value: week.weightDeltaKg.map { GermanNumber.string($0, decimals: 1, signed: true) + " kg" } ?? "–",
                 arrow: week.weightDeltaKg.flatMap { Self.arrow($0, 0, decimals: 1) }),
            Cell(title: "Eiweiß-Tage",
                 value: hasProtein ? "" : "–",
                 arrow: hasProtein && (previous?.trackedDays ?? 0) > 0
                     ? Self.arrow(Double(week.proteinGreenDays), previous.map { Double($0.proteinGreenDays) },
                                  decimals: 0)
                     : nil,
                 protein: hasProtein ? ProteinDays(green: week.proteinGreenDays, yellow: week.proteinYellowDays)
                     : nil),
            Cell(title: "Schritte ⌀",
                 value: week.stepsAvg.map { GermanNumber.string($0) } ?? "–",
                 arrow: Self.arrow(week.stepsAvg, previous?.stepsAvg, decimals: 0)),
            Cell(title: "Strain ⌀",
                 value: week.strainAvg.map { GermanNumber.string($0, decimals: 1) } ?? "–",
                 arrow: Self.arrow(week.strainAvg, previous?.strainAvg, decimals: 1)),
        ]
        self.init(range: Self.range(from: week.from, to: week.to), cells: cells)
    }

    /// Verglichen wird, was zu sehen ist: zwei Werte, die gerundet gleich
    /// dastehen, sind gleich. Fehlt einer, gibt es keinen Pfeil.
    static func arrow(_ current: Double?, _ previous: Double?, decimals: Int) -> Arrow? {
        guard let current, let previous else { return nil }
        let factor = pow(10, Double(decimals))
        let now = (current * factor).rounded()
        let before = (previous * factor).rounded()
        if now > before { return .up }
        if now < before { return .down }
        return .same
    }

    /// „02.11.–08.11.“ - Tag und Monat reichen, die Woche ist die letzte.
    static func range(from: CalendarDate, to: CalendarDate) -> String {
        String(format: "%02d.%02d.–%02d.%02d.", from.day, from.month, to.day, to.month)
    }
}
