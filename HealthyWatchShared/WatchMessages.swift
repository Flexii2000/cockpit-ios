import Foundation

// Was zwischen Healthy auf dem iPhone und auf der Uhr hin- und hergeht (14.10.). Seit 23.10.
// nur noch die kcal-Komplikation - das Krafttraining ist mit dem Gym-Tab nach Sport gezogen
// (SportWatchShared). Uebersetzt von Healthy, HealthyWatch und HealthyWatchWidget - deshalb
// nur Foundation, nichts aus einer der Apps.

/// Der Stand der kcal-Komplikation (iPhone → Uhr per WatchConnectivity).
struct ComplicationSnapshot: Codable, Equatable, Sendable {
    let date: String          // yyyy-MM-dd, Tag des iPhones
    let consumedKcal: Double
    let targetKcal: Double
    let fetchedAt: Date
}

/// Schluessel der WatchConnectivity-Woerterbuecher.
enum WatchKeys {
    /// `updateApplicationContext`: der Privat-Token, damit die Komplikation
    /// selbst beim Kalorienzaehler fragen kann.
    static let privateToken = "fh_private"
    /// `transferCurrentComplicationUserInfo`: `ComplicationSnapshot` als JSON.
    static let snapshot = "complication"
}
