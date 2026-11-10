import Foundation

/// Eine Woche des Rueckblicks (Vertrag §9), gerechnet im Weight Tracker. Jeder
/// Wert ist `nil`, wenn kein Tag zaehlt - nie 0.
struct WeekStats: Decodable, Equatable, Sendable {
    let from: CalendarDate
    let to: CalendarDate
    /// Mittel der getrackten Tage.
    var kcalAvg: Double? = nil
    /// Verbrauch minus gegessen, Mittel der getrackten Tage mit Uhr; negativ
    /// ist ein Ueberschuss.
    var deficitAvg: Double? = nil
    var trackedDays: Int = 0
    var weightAvg: Double? = nil
    var weightDays: Int = 0
    /// Mittel dieser Woche minus das der Woche davor; `nil` unter drei
    /// Messungen in einer der beiden.
    var weightDeltaKg: Double? = nil
    /// Getrackte Tage nach der Eiweiss-Farbe (§11.1) - zusammen `trackedDays`.
    var proteinGreenDays: Int = 0
    var proteinYellowDays: Int = 0
    var proteinRedDays: Int = 0
    var stepsAvg: Double? = nil
    var stepsDays: Int = 0
    var strainAvg: Double? = nil
    var strainDays: Int = 0

    private enum CodingKeys: String, CodingKey {
        case from, to, kcalAvg, deficitAvg, trackedDays, weightAvg, weightDays, weightDeltaKg,
             proteinGreenDays, proteinYellowDays, proteinRedDays, stepsAvg, stepsDays, strainAvg, strainDays
    }

    init(from: CalendarDate, to: CalendarDate, kcalAvg: Double? = nil, deficitAvg: Double? = nil,
         trackedDays: Int = 0, weightAvg: Double? = nil, weightDays: Int = 0, weightDeltaKg: Double? = nil,
         proteinGreenDays: Int = 0, proteinYellowDays: Int = 0, proteinRedDays: Int = 0,
         stepsAvg: Double? = nil, stepsDays: Int = 0, strainAvg: Double? = nil, strainDays: Int = 0) {
        self.from = from
        self.to = to
        self.kcalAvg = kcalAvg
        self.deficitAvg = deficitAvg
        self.trackedDays = trackedDays
        self.weightAvg = weightAvg
        self.weightDays = weightDays
        self.weightDeltaKg = weightDeltaKg
        self.proteinGreenDays = proteinGreenDays
        self.proteinYellowDays = proteinYellowDays
        self.proteinRedDays = proteinRedDays
        self.stepsAvg = stepsAvg
        self.stepsDays = stepsDays
        self.strainAvg = strainAvg
        self.strainDays = strainDays
    }

    /// Zaehler, die ein aelterer Dienst nicht schickt, gelten als 0.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decode(CalendarDate.self, forKey: .from)
        to = try container.decode(CalendarDate.self, forKey: .to)
        kcalAvg = try container.decodeIfPresent(Double.self, forKey: .kcalAvg)
        deficitAvg = try container.decodeIfPresent(Double.self, forKey: .deficitAvg)
        trackedDays = try container.decodeIfPresent(Int.self, forKey: .trackedDays) ?? 0
        weightAvg = try container.decodeIfPresent(Double.self, forKey: .weightAvg)
        weightDays = try container.decodeIfPresent(Int.self, forKey: .weightDays) ?? 0
        weightDeltaKg = try container.decodeIfPresent(Double.self, forKey: .weightDeltaKg)
        proteinGreenDays = try container.decodeIfPresent(Int.self, forKey: .proteinGreenDays) ?? 0
        proteinYellowDays = try container.decodeIfPresent(Int.self, forKey: .proteinYellowDays) ?? 0
        proteinRedDays = try container.decodeIfPresent(Int.self, forKey: .proteinRedDays) ?? 0
        stepsAvg = try container.decodeIfPresent(Double.self, forKey: .stepsAvg)
        stepsDays = try container.decodeIfPresent(Int.self, forKey: .stepsDays) ?? 0
        strainAvg = try container.decodeIfPresent(Double.self, forKey: .strainAvg)
        strainDays = try container.decodeIfPresent(Int.self, forKey: .strainDays) ?? 0
    }
}

/// `GET /api/review/week`: die letzte volle Woche Montag bis Sonntag und die
/// davor.
struct WeekReview: Decodable, Equatable, Sendable {
    let week: WeekStats
    let previous: WeekStats?
    /// Ob der Kalorienzaehler antwortete (`food: OK|UNAVAILABLE`) - ohne ihn
    /// fehlen Aufnahme, Defizit und Eiweiss-Tage.
    var sources: [String: String]? = nil
}

struct ReviewAPI: Sendable {

    private let client = APIClient(backend: .weight)

    /// Ohne Angabe die letzte volle Woche.
    func week() async throws -> WeekReview {
        try await client.get("/api/review/week")
    }
}
