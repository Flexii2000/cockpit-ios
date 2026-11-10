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
    /// Seit 10.11.: der ganze Tag, damit die Uhr-App unter dem kcal-Bogen die
    /// Makros zeigen kann. Fehlt in einem Stand von vor dem Update - der bleibt
    /// lesbar, die Zeilen fehlen dann nur.
    var consumed: Nutrients? = nil
    /// Die Ziele samt `proteinMinG` (Eiweiss Erhalt, Vertrag §11.1).
    var targets: Nutrients? = nil

    /// Ob beide denselben Tagesstand zeigen - der Zeitpunkt des Holens zaehlt nicht.
    func showsSame(as other: ComplicationSnapshot?) -> Bool {
        guard let other else { return false }
        return date == other.date && consumedKcal == other.consumedKcal && targetKcal == other.targetKcal
            && consumed == other.consumed && targets == other.targets
    }
}

/// Schluessel der WatchConnectivity-Woerterbuecher.
enum WatchKeys {
    /// `updateApplicationContext`: der Privat-Token, damit die Komplikation
    /// selbst beim Kalorienzaehler fragen kann.
    static let privateToken = "fh_private"
    /// Der persoenliche Healthy-Token (seit 10.11.) - auf einem iPhone, das
    /// Felix' Privat-Token nicht hat.
    static let healthToken = "health_token"
    /// Seit 10.11. im Kontext: das iPhone nennt **beide** Token, die es hat.
    /// Steht die Marke da, gilt auch das Fehlen - ein Token, der nicht mehr
    /// mitkommt, wird auf der Uhr geloescht. Ein Kontext ohne Marke stammt von
    /// einer aelteren iPhone-App und sagt ueber den persoenlichen Token nichts.
    static let accessVersion = "access_version"
    /// `transferCurrentComplicationUserInfo`: `ComplicationSnapshot` als JSON.
    static let snapshot = "complication"
}
