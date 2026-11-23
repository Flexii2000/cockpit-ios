import Foundation

/// Die grosse Komplikation fuer die Mitte des Modular-Zifferblatts (Felix,
/// 20.11.): drei Ringe nebeneinander - kcal, Schritte, Strain -, unter jedem die
/// Zahl. Jeder Ring fuellt sich bis zu seinem Ziel:
///
/// - **kcal:** das Gegessene gegen das Tagesziel, wie der runde kcal-Ring;
///   darunter der Rest, drueber mit Plus („+120“).
/// - **Schritte:** gegen das Schrittziel aus dem Weight Tracker.
/// - **Strain:** gegen das Ziel von heute (Felix' Wahl gegen „0–21 mit
///   Zielmarke“ wie in der App), darueber voll und orange. Ohne Ziel - beim
///   Kalibrieren - gegen die ganze Skala bis 21.
///
/// Bewusst ohne SwiftUI: die Sonderfaelle lassen sich so ohne Uhr pruefen.
struct HealthRings: Equatable, Sendable {

    enum Kind: String, CaseIterable, Sendable {
        case kcal, steps, strain

        var title: String {
            switch self {
            case .kcal:   "Kalorien"
            case .steps:  "Schritte"
            case .strain: "Strain"
            }
        }
    }

    struct Ring: Equatable, Identifiable, Sendable {
        let kind: Kind
        /// 0 bis 1.
        let fill: Double
        /// Die Zahl unter dem Ring, „–“ ohne Wert - nie eine erfundene.
        let value: String
        /// Ueber dem Ziel. Nur der Strain-Ring wechselt dann die Farbe.
        let over: Bool
        /// Fuer VoiceOver.
        let spoken: String

        var id: Kind { kind }
    }

    let kcal: Ring
    let steps: Ring
    let strain: Ring

    var all: [Ring] { [kcal, steps, strain] }

    /// Ohne bekanntes Schrittziel - dieselbe Vorgabe wie auf dem iPhone.
    static let defaultStepsGoal = 10_000

    /// Das obere Ende der Strain-Skala, wie bei Whoop und in der App.
    static let strainScale = 21.0

    static let missing = "–"
}

extension HealthRings {

    init(kcalConsumed: Double?, kcalTarget: Double?, steps: Int?, stepsGoal: Int,
         strain: Double?, targetStrain: Double?) {
        self.init(kcal: Self.kcalRing(consumed: kcalConsumed, target: kcalTarget),
                  steps: Self.stepsRing(steps: steps, goal: stepsGoal),
                  strain: Self.strainRing(strain: strain, target: targetStrain))
    }

    /// Erfundene Werte fuer den Platzhalter und die Vorschau.
    static let sample = HealthRings(kcalConsumed: 1550, kcalTarget: 2300, steps: 8214, stepsGoal: 10_000,
                                    strain: 12.4, targetStrain: 14.1)

    private static func kcalRing(consumed: Double?, target: Double?) -> Ring {
        guard let consumed, let target, target > 0 else {
            return Ring(kind: .kcal, fill: 0, value: missing, over: false, spoken: "unbekannt")
        }
        return Ring(kind: .kcal, fill: share(consumed, of: target),
                    value: KcalGaugeView.center(consumed: consumed, target: target),
                    over: consumed > target, spoken: KcalGaugeView.spokenRest(consumed: consumed, target: target))
    }

    private static func stepsRing(steps: Int?, goal: Int) -> Ring {
        guard let steps else {
            return Ring(kind: .steps, fill: 0, value: missing, over: false, spoken: "unbekannt")
        }
        return Ring(kind: .steps, fill: share(Double(steps), of: Double(goal)), value: grouped(steps),
                    over: goal > 0 && steps > goal, spoken: "\(steps) von \(goal)")
    }

    private static func strainRing(strain: Double?, target: Double?) -> Ring {
        // Ohne Puls heute (`NO_DATA`) steht das Ziel schon da - der Ring bleibt
        // trotzdem leer und ohne Zahl: 0 waere eine Behauptung.
        guard let strain else {
            return Ring(kind: .strain, fill: 0, value: missing, over: false,
                        spoken: target.map { "noch kein Wert, Ziel \(decimal($0))" } ?? "unbekannt")
        }
        guard let target, target > 0 else {
            return Ring(kind: .strain, fill: share(strain, of: strainScale), value: decimal(strain), over: false,
                        spoken: decimal(strain))
        }
        return Ring(kind: .strain, fill: share(strain, of: target), value: decimal(strain), over: strain > target,
                    spoken: "\(decimal(strain)), Ziel \(decimal(target))")
    }

    private static func share(_ value: Double, of whole: Double) -> Double {
        whole > 0 ? min(max(value / whole, 0), 1) : 0
    }

    private static let german = Locale(identifier: "de_DE")

    /// „8.214“
    static func grouped(_ value: Int) -> String {
        value.formatted(.number.locale(german))
    }

    /// „12,4“
    static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(german))
    }

    /// Alle 15 Minuten - die Schritte laufen weiter, auch ohne dass jemand die
    /// App oeffnet - und gleich nach Mitternacht. Eine Bitte an WidgetKit, keine
    /// Zusage: watchOS teilt die Auffrischungen selbst ein.
    static func nextRefresh(after now: Date, in timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let soon = now.addingTimeInterval(15 * 60)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
              let midnight = calendar.dateInterval(of: .day, for: tomorrow)?.start
        else { return soon }
        return min(soon, midnight.addingTimeInterval(60))
    }
}

// MARK: - Der Strain beim Weight Tracker

/// Was die Komplikation von `GET /api/strain/today` braucht (Vertrag §7.3).
/// Die App liest dieselbe Antwort als `StrainDay`; hier nur die drei Felder,
/// damit die Uhr nichts aus `Healthy/` mitbauen muss.
struct WatchStrain: Codable, Equatable, Sendable {
    /// yyyy-MM-dd - ohne Netz koennte der Offline-Stand von gestern kommen.
    let date: String
    /// 0 bis 21; `nil`, solange heute noch kein Puls angekommen ist.
    let strain: Double?
    /// `nil` beim Kalibrieren.
    let targetStrain: Double?
}

// MARK: - Letzter Stand

/// Was die Ringe zuletzt wussten - im Schluesselbund der Uhr wie der kcal-Stand
/// (`ComplicationStore`). Ist die Uhr gesperrt, kommt die Komplikation nicht an
/// Health heran, und ohne Netz nicht an den Weight Tracker; dann gilt der Stand
/// von heute weiter statt „–“.
struct RingsSnapshot: Codable, Equatable, Sendable {
    /// yyyy-MM-dd
    let date: String
    var steps: Int?
    /// Gilt ueber den Tag hinaus - es aendert sich selten.
    var stepsGoal: Int?
    var strain: Double?
    var targetStrain: Double?
}

/// Was ein Abruf gebracht hat. `nil` heisst jeweils: diese Quelle hat nicht
/// geantwortet.
struct RingsFetch: Equatable, Sendable {
    var steps: Int?
    var stepsGoal: Int?
    var strain: WatchStrain?
}

extension RingsSnapshot {

    /// Frisches gilt, Fehlendes kommt aus dem Stand von heute.
    ///
    /// Schritte: das Groessere aus beidem - im Laufe eines Tages werden es nur
    /// mehr, und so springt der Ring nicht zurueck, wenn Health auf der Uhr
    /// einmal weniger weiss. Strain: hat der Weight Tracker geantwortet, gilt
    /// seine Antwort ganz, auch „noch kein Strain“.
    static func merged(_ fetch: RingsFetch, stored: RingsSnapshot?, today: String) -> RingsSnapshot {
        let sameDay = stored?.date == today ? stored : nil
        let steps: Int? = switch (fetch.steps, sameDay?.steps) {
        case let (fresh?, old?): max(fresh, old)
        case let (fresh?, nil): fresh
        case let (nil, old): old
        }
        var snapshot = RingsSnapshot(date: today, steps: steps, stepsGoal: fetch.stepsGoal ?? stored?.stepsGoal,
                                     strain: sameDay?.strain, targetStrain: sameDay?.targetStrain)
        if let fresh = fetch.strain, fresh.date == today {
            snapshot.strain = fresh.strain
            snapshot.targetStrain = fresh.targetStrain
        }
        return snapshot
    }
}
