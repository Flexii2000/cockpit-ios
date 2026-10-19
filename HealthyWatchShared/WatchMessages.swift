import Foundation

// Was zwischen Healthy auf dem iPhone und auf der Uhr hin- und hergeht (14.10.).
// Uebersetzt von Healthy, HealthyWatch und HealthyWatchWidget - deshalb nur
// Foundation, nichts aus einer der Apps.

/// Live-Werte des Trainings, von der Uhr ans iPhone.
struct WorkoutMetrics: Codable, Equatable, Sendable {
    var heartRate: Double?
    var activeKcal: Double?
    let at: Date
}

/// Das Geraet, das gerade dran ist - vom iPhone an die Uhr.
///
/// `note` und `repsMin` gibt es seit 19.10.; eine Seite von vorher schickt sie
/// nicht und liest sie nicht - beides geht (`decodeIfPresent`).
struct WorkoutCurrent: Codable, Equatable, Sendable {
    let exerciseId: String
    let name: String
    /// Die Notiz am Geraet, etwa die Sitzeinstellung - `nil` ohne.
    let note: String?
    /// Der Satz, der als naechster kommt (1-basiert).
    let set: Int
    let sets: Int
    /// Mit Spanne die obere Grenze - auf der Uhr vorbelegt.
    let reps: Int
    /// Die untere Grenze, nur bei einer echten Spanne: dann dreht die Krone
    /// die Wiederholungen.
    let repsMin: Int?
    let weightKg: Double
}

/// Botschaften waehrend eines Trainings - ueber die gespiegelte
/// `HKWorkoutSession` (`sendToRemoteWorkoutSession`).
enum WorkoutMessage: Codable, Equatable, Sendable {
    /// Uhr → iPhone.
    case metrics(WorkoutMetrics)
    /// iPhone → Uhr; `nil`: alle Saetze erledigt.
    case current(WorkoutCurrent?)
    /// Uhr → iPhone: „Satz erledigt“ - mit Kennung, damit ein wiederholtes
    /// Schicken nicht zweimal abhakt. `reps`: mit Spanne die an der Krone
    /// gewaehlten Wiederholungen (19.10.); `nil` heisst „wie geplant“.
    case setDone(id: String, exerciseId: String, reps: Int?)
    /// iPhone → Uhr: dieser Haken ist angekommen.
    case ack(id: String)
    /// Beide Richtungen: das Training ist vorbei.
    case end

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data) -> WorkoutMessage? {
        try? JSONDecoder().decode(WorkoutMessage.self, from: data)
    }
}

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
    /// `transferUserInfo` (Rueckfall, Uhr → iPhone): ein „Satz erledigt“ als JSON.
    static let workoutMessage = "workout"
}
