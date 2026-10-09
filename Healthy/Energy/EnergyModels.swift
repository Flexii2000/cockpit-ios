import Foundation

/// Aktive Energie und Ruheenergie eines Tages, wie sie zum Weight Tracker
/// gehen (`POST /api/energy`, Vertrag §1.1). Ein fehlendes Feld heisst
/// „unbekannt" und laesst beim Dienst den gespeicherten Wert stehen.
struct EnergyDayUpload: Codable, Equatable, Sendable {
    let date: CalendarDate
    let activeKcal: Double?
    let basalKcal: Double?
}

/// Was die App an `POST /api/energy` schickt.
struct EnergyUpload: Encodable, Sendable {
    let days: [EnergyDayUpload]
    /// `true` liesse auch heute und gestern sinken - die App schickt das nie;
    /// heute und gestern gewinnt beim Dienst je Feld das Maximum.
    let replace: Bool?
}
