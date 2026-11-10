import Foundation

// MARK: - Upload

/// Das Puls-Histogramm eines Tages, wie es zum Weight Tracker geht
/// (`POST /api/strain`, Vertrag §7.1): `minutes[i]` sind die Minuten mit Puls
/// in `[fromBpm + 5·i, fromBpm + 5·i + 5)`. Wie es entsteht, steht in
/// `HealthHeart`.
struct HeartDayUpload: Codable, Equatable, Sendable {
    let date: CalendarDate
    /// Die Summe von `minutes` - wie lange an dem Tag ein Puls bekannt war.
    let coverageMinutes: Double
    /// Das kleinste belegte Fach, ein Vielfaches von 5.
    let fromBpm: Int
    let minutes: [Double]
}

/// Was die App an `POST /api/strain` schickt.
struct HeartUpload: Encodable, Sendable {
    let days: [HeartDayUpload]
    /// `true` ersetzte auch heute und gestern - die App schickt das nie; dort
    /// gewinnt beim Dienst als Ganzes der Upload mit der groesseren Abdeckung.
    let replace: Bool?
}

/// Die Antwort auf einen Upload: was fuer den Tag jetzt gespeichert ist.
struct StrainStored: Decodable, Equatable, Sendable {
    let date: CalendarDate
    let coverageMinutes: Double
}

// MARK: - Strain

/// Wie weit der Strain eines Tages ist (Vertrag §7.3), in dieser Reihenfolge
/// geprueft.
enum StrainStatus: String, LenientEnum {
    case ok = "OK"
    /// Es gibt noch kein Ziel: kein Ruhepuls bestimmbar oder weniger als 14
    /// abgedeckte Tage unter den 28 davor. Last und Strain stehen da, sobald
    /// der Ruhepuls bekannt ist.
    case calibrating = "CALIBRATING"
    /// Ein vergangener Tag mit weniger als 600 Minuten Puls - die Werte stehen
    /// da, der Tag zaehlt nicht in die Mittel.
    case lowCoverage = "LOW_COVERAGE"
    /// Fuer den Tag liegt kein Histogramm vor. Die Werte des Morgens (Ziel,
    /// Akut, Gewohnt) stehen trotzdem da.
    case noData = "NO_DATA"
    case unknown
}

/// Der Strain in vier Stufen (nach dem gezeigten Wert: unter 8, unter 14,
/// unter 18, sonst) - die Farbe, die Freunde voneinander sehen (§10).
enum StrainBand: String, LenientEnum {
    case light = "LIGHT", moderate = "MODERATE", high = "HIGH", allOut = "ALL_OUT", unknown
}

struct StrainCalibration: Decodable, Equatable, Sendable {
    /// Abgedeckte Tage unter den 28 vor diesem Tag.
    let days: Int
    let required: Int
}

/// Der Strain eines Tages (`GET /api/strain/today`, `GET /api/strain`),
/// gerechnet im Weight Tracker - die App rechnet hier nichts nach.
///
/// Die Felder gehoeren zu zwei Gruppen. **Zum Histogramm des Tages:**
/// `coverageMinutes`, `load`, `strain`, `band` - ohne Histogramm `nil`.
/// **Zum Morgen des Tages** (Daten bis zum Vortag): `hrRest`, `hrMax`,
/// `acuteLoad`, `chronicLoad`, `targetLoad`, `targetStrain`, Recovery und
/// `calibration` - sie stehen auch an einem Tag ohne Histogramm da. So reisst
/// die Form-Kurve an einem Tag ohne Uhr nicht ab, und das Ziel steht, bevor
/// der erste Puls des Tages kommt.
struct StrainDay: Decodable, Equatable, Identifiable, Sendable {
    let date: CalendarDate
    let status: StrainStatus
    /// Heute: der Strain ist der Stand **bisher**, nie eine Prognose.
    let partial: Bool
    let coverageMinutes: Int?
    /// Der Tag ist vorbei und hat mindestens 600 Minuten - nur solche zaehlen
    /// in die Mittel spaeterer Tage.
    let covered: Bool
    /// Banisters TRIMP des Tages.
    let load: Double?
    /// 0 bis 21, eine Nachkommastelle.
    let strain: Double?
    let band: StrainBand?
    /// Die Last, die heute passt: gewohnte Last × Form × Recovery.
    let targetLoad: Double?
    /// Dieselbe Last auf der Strain-Skala - die Zielmarke.
    let targetStrain: Double?
    /// Gewichtetes Mittel der Last, 7 Tage - „Akut“.
    let acuteLoad: Double?
    /// Gewichtetes Mittel der Last, 28 Tage - „Gewohnt“.
    let chronicLoad: Double?
    /// Die Recovery der Nacht zu diesem Tag (§3), sonst `nil`.
    let recoveryScore: Int?
    let recoveryBand: RecoveryBand?
    let hrRest: Double?
    let hrMax: Double?
    let calibration: StrainCalibration?

    var id: CalendarDate { date }

    private enum CodingKeys: String, CodingKey {
        case date, status, partial, coverageMinutes, covered, load, strain, band, targetLoad, targetStrain,
             acuteLoad, chronicLoad, recoveryScore, recoveryBand, hrRest, hrMax, calibration
    }

    init(date: CalendarDate, status: StrainStatus, partial: Bool = false, coverageMinutes: Int? = nil,
         covered: Bool = false, load: Double? = nil, strain: Double? = nil, band: StrainBand? = nil,
         targetLoad: Double? = nil, targetStrain: Double? = nil, acuteLoad: Double? = nil,
         chronicLoad: Double? = nil, recoveryScore: Int? = nil, recoveryBand: RecoveryBand? = nil,
         hrRest: Double? = nil, hrMax: Double? = nil, calibration: StrainCalibration? = nil) {
        self.date = date
        self.status = status
        self.partial = partial
        self.coverageMinutes = coverageMinutes
        self.covered = covered
        self.load = load
        self.strain = strain
        self.band = band
        self.targetLoad = targetLoad
        self.targetStrain = targetStrain
        self.acuteLoad = acuteLoad
        self.chronicLoad = chronicLoad
        self.recoveryScore = recoveryScore
        self.recoveryBand = recoveryBand
        self.hrRest = hrRest
        self.hrMax = hrMax
        self.calibration = calibration
    }

    /// Nur Datum und Status sind Pflicht: ein Dienst, der ein Feld (noch)
    /// nicht schickt, soll nicht die ganze Karte leeren. `coverageMinutes`
    /// kommt als ganze Zahl; eine Kommazahl wuerde trotzdem gelesen.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        date = try values.decode(CalendarDate.self, forKey: .date)
        status = try values.decode(StrainStatus.self, forKey: .status)
        partial = try values.decodeIfPresent(Bool.self, forKey: .partial) ?? false
        coverageMinutes = try values.decodeIfPresent(Double.self, forKey: .coverageMinutes).map { Int($0.rounded()) }
        covered = try values.decodeIfPresent(Bool.self, forKey: .covered) ?? false
        load = try values.decodeIfPresent(Double.self, forKey: .load)
        strain = try values.decodeIfPresent(Double.self, forKey: .strain)
        band = try values.decodeIfPresent(StrainBand.self, forKey: .band)
        targetLoad = try values.decodeIfPresent(Double.self, forKey: .targetLoad)
        targetStrain = try values.decodeIfPresent(Double.self, forKey: .targetStrain)
        acuteLoad = try values.decodeIfPresent(Double.self, forKey: .acuteLoad)
        chronicLoad = try values.decodeIfPresent(Double.self, forKey: .chronicLoad)
        recoveryScore = try values.decodeIfPresent(Int.self, forKey: .recoveryScore)
        recoveryBand = try values.decodeIfPresent(RecoveryBand.self, forKey: .recoveryBand)
        hrRest = try values.decodeIfPresent(Double.self, forKey: .hrRest)
        hrMax = try values.decodeIfPresent(Double.self, forKey: .hrMax)
        calibration = try values.decodeIfPresent(StrainCalibration.self, forKey: .calibration)
    }
}

// MARK: - Einstellungen

/// Woher der Maximalpuls kommt, mit dem gerechnet wird (Vertrag §7.5).
enum HrMaxSource: String, LenientEnum {
    /// Von der Person festgelegt.
    case setting = "SETTING"
    /// Der hoechste Puls, der an einem Tag des letzten Jahres mindestens zwei
    /// Minuten erreicht wurde.
    case observed = "OBSERVED"
    /// 170 - auch wenn der beobachtete darunter liegt.
    case standard = "DEFAULT"
    case unknown
}

enum HrRestSource: String, LenientEnum {
    /// Der Median des Pulses im Schlaf der Baseline-Naechte.
    case nights = "NIGHTS"
    /// Ohne genug Naechte: das 5. Perzentil der Histogramme.
    case histogram = "HISTOGRAM"
    /// Noch keiner bestimmbar. Nicht `none` genannt - das laese sich bei
    /// einem optionalen Wert wie „kein Wert“.
    case missing = "NONE"
    case unknown
}

/// Womit der Strain heute gerechnet wird (`GET`/`PUT /api/strain/settings`).
struct StrainSettings: Decodable, Equatable, Sendable {
    /// Was die Person festgelegt hat, sonst `nil`.
    let hrMax: Double?
    /// Was gilt.
    let hrMaxUsed: Double
    let hrMaxSource: HrMaxSource
    let hrMaxObserved: Double?
    /// Der Ruhepuls von heute; `nil`, solange keiner bestimmbar ist.
    let hrRest: Double?
    let hrRestSource: HrRestSource
    let tau: Double

    /// Was der Dienst als festgelegten Maximalpuls annimmt.
    static let hrMaxRange = 120.0...230.0
}

/// Was die App an `PUT /api/strain/settings` schickt. `nil` fehlt im JSON -
/// das heisst beim Dienst: zurueck zum beobachteten Maximalpuls.
struct StrainSettingsRequest: Encodable, Sendable {
    let hrMax: Double?
}

// MARK: - Zeitraum

/// Der Zeitraum des Strain-Fensters (Vertrag §5): `6 Wo.` · `3 Mon.` ·
/// `6 Mon.` · `1 Jahr`, gemerkt - wer ein Jahr sehen will, will das beim
/// naechsten Mal auch.
enum StrainRange: Int, CaseIterable, Identifiable, Sendable {
    case sixWeeks = 42
    case threeMonths = 90
    case sixMonths = 180
    case year = 365

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .sixWeeks:    "6 Wo."
        case .threeMonths: "3 Mon."
        case .sixMonths:   "6 Mon."
        case .year:        "1 Jahr"
        }
    }

    static let key = "strain.range"

    static func load(from defaults: UserDefaults = .standard) -> StrainRange {
        StrainRange(rawValue: defaults.integer(forKey: key)) ?? .sixWeeks
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.key)
    }
}

// MARK: - Anzeige

/// Der Strain als Text - die Formate aus dem Vertrag (§5): „Strain“, „Ziel“,
/// „Akut“, „Gewohnt“, „Form“.
enum StrainFormat {

    /// Das obere Ende der Skala - wie bei Whoop.
    static let scale = 21.0

    /// „12,4“ - eine Nachkommastelle.
    static func value(_ strain: Double) -> String {
        GermanNumber.string(strain, decimals: 1)
    }

    /// „Ziel 14,1“
    static func target(_ targetStrain: Double) -> String {
        "Ziel " + value(targetStrain)
    }

    /// „118“ - die Last in der Form-Kurve, ganz.
    static func load(_ load: Double) -> String {
        GermanNumber.string(load)
    }

    /// Wo ein Strain auf der Skala 0–21 liegt, als Anteil 0…1.
    static func fraction(_ strain: Double) -> Double {
        min(max(strain / scale, 0), 1)
    }
}
