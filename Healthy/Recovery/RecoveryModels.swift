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
