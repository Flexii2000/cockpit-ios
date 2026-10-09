import Foundation

/// Eine Nacht, wie die App sie aus Health bildet und der Weight Tracker sie
/// speichert (`POST`/`GET /api/nights`, Vertrag §2). Ein fehlendes Feld heisst
/// „unbekannt", nie 0.
///
/// `sleepStart`/`sleepEnd` sind Zeitpunkte: `APIClient.encoder()` schreibt
/// sie als ISO 8601 mit `Z`, wie Jacksons `Instant` sie liest.
struct Night: Codable, Equatable, Sendable {
    /// Der Aufwachtag in der Zeitzone des Geraets.
    let date: CalendarDate
    let sleepStart: Date?
    let sleepEnd: Date?
    let asleepMinutes: Int
    let inBedMinutes: Int?
    let awakeMinutes: Int?
    let deepMinutes: Int?
    let remMinutes: Int?
    let coreMinutes: Int?
    let hrvSdnnMs: Double?
    let hrvSdnnSamples: Int?
    let hrvRmssdMs: Double?
    let hrvRmssdSamples: Int?
    let sleepingHeartRate: Double?
    let respiratoryRate: Double?
    let source: String?
}

/// Was die App an `POST /api/nights` schickt.
struct NightsUpload: Encodable, Sendable {
    let nights: [Night]
}

// MARK: - Recovery

/// Wie weit eine Recovery ist (Vertrag §3.1).
enum RecoveryStatus: String, LenientEnum {
    case ok = "OK"
    /// Noch keine 14 Baseline-Naechte mit HRV derselben Methode.
    case calibrating = "CALIBRATING"
    /// Die Nacht hat keine HRV - die anderen Werte stehen trotzdem da.
    case noHrv = "NO_HRV"
    /// Unter 90 Minuten geschlafen: kein Hauptschlaf, keine Bewertung.
    case tooShort = "TOO_SHORT"
    /// Fuer heute ist noch keine Nacht angekommen.
    case noNight = "NO_NIGHT"
    case unknown
}

/// Wie bei Whoop: ab 67 gruen, bis 33 rot, dazwischen gelb.
enum RecoveryBand: String, LenientEnum {
    case green = "GREEN", yellow = "YELLOW", red = "RED", unknown
}

/// SDNN misst Apple seit jeher, RMSSD Health Connect und Apple ab iOS 27.
enum HrvMethod: String, LenientEnum {
    case sdnn = "SDNN", rmssd = "RMSSD", unknown
}

/// Die Bausteine der Recovery, in der Reihenfolge ihres Gewichts.
enum ComponentKey: String, LenientEnum {
    case hrv = "HRV"
    /// Der Puls im Schlaf - in der Oberflaeche „RHF".
    case sleepingHeartRate = "SLEEPING_HEART_RATE"
    case sleep = "SLEEP"
    case respiratoryRate = "RESPIRATORY_RATE"
    case unknown
}

/// Das 7-Naechte-Mittel der HRV gegen den Normalbereich (Plews/Buchheit).
enum TrendStatus: String, LenientEnum {
    case below = "BELOW", within = "WITHIN", above = "ABOVE", unknown = "UNKNOWN"
}

struct RecoveryCalibration: Decodable, Equatable, Sendable {
    /// Baseline-Naechte mit HRV - beim Kalibrieren „9/14".
    let nights: Int
    let required: Int
}

/// Ein Baustein der Recovery einer Nacht.
struct RecoveryComponent: Decodable, Equatable, Identifiable, Sendable {
    let key: ComponentKey
    /// Der Messwert der Nacht in `unit` (HRV ms, Puls bpm, Schlaf min, Atem /min).
    let value: Double
    let unit: String
    /// Der Median der 60 Naechte davor; `nil`, solange zu wenige da sind.
    let baseline: Double?
    /// Abstand zur Baseline in robusten Standardabweichungen, **positiv =
    /// besser**, auf ±3 begrenzt - auch beim Puls und beim Atem, wo weniger
    /// besser ist. Die App dreht nichts um.
    let z: Double?
    /// Anteil am Score; 0, wenn der Baustein nicht einging.
    let weight: Double

    var id: String { key.rawValue }
}

struct HrvTrend: Decodable, Equatable, Sendable {
    /// Ab vier Naechten in den sieben, sonst `nil`.
    let mean7Ms: Double?
    let nights7: Int
    /// Der Normalbereich: Median ± 0,5 Streuung der 60 Naechte davor.
    let normalLowMs: Double?
    let normalHighMs: Double?
    let status: TrendStatus
}

/// Die Recovery eines Morgens (`GET /api/recovery/today`, `GET /api/recovery`)
/// - bewertet wird die Nacht davor.
struct RecoveryDay: Decodable, Equatable, Identifiable, Sendable {
    let date: CalendarDate
    let status: RecoveryStatus
    /// 0 bis 100, 50 = eine typische Nacht; nur bei `ok`.
    let score: Int?
    let band: RecoveryBand?
    let composite: Double?
    let hrvMethod: HrvMethod?
    let calibration: RecoveryCalibration?
    /// Ein Baustein steht da, sobald die Nacht den Wert hat - auch ohne Score.
    let components: [RecoveryComponent]
    /// Nur, wenn es einen Score gibt.
    let hrvTrend: HrvTrend?

    var id: CalendarDate { date }

    func component(_ key: ComponentKey) -> RecoveryComponent? {
        components.first { $0.key == key }
    }
}

/// Ab wie viel Schlaf mehr nichts mehr bringt (`GET`/`PUT /api/recovery/settings`).
struct RecoverySettings: Codable, Equatable, Sendable {
    let sleepNeedMinutes: Int

    /// Was der Dienst annimmt: 4 bis 12 Stunden.
    static let range = 240...720
    /// In Viertelstunden waehlbar - genauer schaetzt niemand seinen Bedarf.
    static let step = 15
}

/// Der Zeitraum der HRV-Kurve auf der Recovery-Seite.
enum RecoveryRange: Int, CaseIterable, Identifiable, Sendable {
    case month = 30
    case quarter = 90

    var id: Int { rawValue }

    var title: String { "\(rawValue) Tage" }
}

// MARK: - Anzeige

/// Die Recovery als Text - deutsch, mit den Namen aus dem Vertrag (§5):
/// „Recovery", „HRV", „RHF", „Schlaf", „Atemfrequenz".
enum RecoveryFormat {

    /// Was im Ring steht: Score in Prozent; beim Kalibrieren die Naechte;
    /// sonst ein Strich und der Grund. Unter dem Score steht nichts - daneben
    /// oder darueber steht ohnehin „Recovery".
    struct Ring: Equatable {
        let ratio: Double
        let tone: MacroTone
        let main: String
        let sub: String
    }

    static func ring(_ day: RecoveryDay?) -> Ring {
        guard let day else { return Ring(ratio: 0, tone: .neutral, main: "–", sub: "") }
        switch day.status {
        case .ok:
            guard let score = day.score else { break }
            return Ring(ratio: Double(score) / 100, tone: tone(day.band), main: "\(score) %", sub: "")
        case .calibrating:
            if let calibration = day.calibration, calibration.required > 0 {
                return Ring(ratio: Double(calibration.nights) / Double(calibration.required), tone: .neutral,
                            main: "\(calibration.nights)/\(calibration.required)", sub: "Nächte")
            }
        case .noHrv:
            return Ring(ratio: 0, tone: .neutral, main: "–", sub: "Keine HRV")
        case .tooShort:
            return Ring(ratio: 0, tone: .neutral, main: "–", sub: "Zu kurz")
        case .noNight:
            return Ring(ratio: 0, tone: .neutral, main: "–", sub: "Keine Nacht")
        case .unknown:
            break
        }
        return Ring(ratio: 0, tone: .neutral, main: "–", sub: "")
    }

    /// Die Bandfarbe - dieselben Verlaeufe wie die Tachos im Essen-Tab.
    static func tone(_ band: RecoveryBand?) -> MacroTone {
        switch band {
        case .green:  .good
        case .yellow: .warn
        case .red:    .bad
        default:      .neutral
        }
    }

    static func label(_ key: ComponentKey) -> String {
        switch key {
        case .hrv:               "HRV"
        case .sleepingHeartRate: "RHF"
        case .sleep:             "Schlaf"
        case .respiratoryRate:   "Atemfrequenz"
        case .unknown:           "–"
        }
    }

    /// „58 ms", „51 bpm", „7:41 h", „14,1 /min" - HRV und Puls ganz, der Atem
    /// mit einer Stelle: dort ist ein Zehntel schon ein Unterschied.
    static func value(_ key: ComponentKey, _ value: Double, unit: String) -> String {
        switch key {
        case .sleep:           hoursMinutes(value)
        case .respiratoryRate: GermanNumber.string(value, decimals: 1) + " " + unit
        default:               GermanNumber.string(value) + " " + unit
        }
    }

    /// „⌀ 50 ms" - der Median der Naechte davor.
    static func baseline(_ component: RecoveryComponent) -> String? {
        component.baseline.map { "⌀ " + value(component.key, $0, unit: component.unit) }
    }

    /// „7:41 h"
    static func hoursMinutes(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return String(format: "%d:%02d h", total / 60, total % 60)
    }

    /// Die Zeile im Dashboard: „HRV 58 ms · RHF 49 · 7:41 h".
    static func summaryLine(_ day: RecoveryDay) -> String? {
        var parts: [String] = []
        if let hrv = day.component(.hrv) {
            parts.append("HRV " + GermanNumber.string(hrv.value) + " " + hrv.unit)
        }
        if let heart = day.component(.sleepingHeartRate) {
            parts.append("RHF " + GermanNumber.string(heart.value))
        }
        if let sleep = day.component(.sleep) {
            parts.append(hoursMinutes(sleep.value))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// „⌀ 7 Nächte 52 ms" ueber der HRV-Kurve.
    static func trend(_ trend: HrvTrend?) -> String? {
        guard let mean = trend?.mean7Ms else { return nil }
        return "⌀ 7 Nächte " + GermanNumber.string(mean) + " ms"
    }
}
