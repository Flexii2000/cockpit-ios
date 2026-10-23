import Foundation

// Was zwischen Sport auf dem iPhone und auf der Uhr hin- und hergeht (23.10.; bis dahin
// zwischen Healthy und seiner Uhr-App). Uebersetzt von Sport und SportWatch - deshalb nur
// Foundation, nichts aus einer der Apps.

/// Live-Werte des Trainings, von der Uhr ans iPhone.
struct WorkoutMetrics: Codable, Equatable, Sendable {
    var heartRate: Double?
    var activeKcal: Double?
    let at: Date
}

/// Das Geraet, das gerade dran ist.
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

/// Ein Geraet des Tages in der Liste der Uhr (Felix, 23.10.: Geraeteliste zum Wechseln).
struct WorkoutStation: Codable, Equatable, Sendable, Identifiable {
    let exerciseId: String
    let name: String
    let done: Int
    let sets: Int

    var id: String { exerciseId }
    var isDone: Bool { done >= sets }
}

/// Was die Uhr vom Training wissen muss - vom iPhone, nach jeder Aenderung.
struct WorkoutPlan: Codable, Equatable, Sendable {
    /// Das Geraet, das dran ist; `nil`: alle Saetze erledigt.
    let current: WorkoutCurrent?
    /// Alle Geraete des Tages in seiner Reihenfolge.
    let stations: [WorkoutStation]
    /// Wann zuletzt ein Satz abgehakt wurde, an der Uhr oder am iPhone - fuer die Pause.
    let lastSetAt: Date?
}

/// Botschaften waehrend eines Krafttrainings - ueber die gespiegelte
/// `HKWorkoutSession` (`sendToRemoteWorkoutSession`), sonst per WatchConnectivity.
enum WorkoutMessage: Codable, Equatable, Sendable {
    /// Uhr → iPhone.
    case metrics(WorkoutMetrics)
    /// iPhone → Uhr.
    case plan(WorkoutPlan)
    /// Uhr → iPhone: „Satz erledigt“ - mit Kennung, damit ein wiederholtes
    /// Schicken nicht zweimal abhakt. `reps`: mit Spanne die an der Krone
    /// gewaehlten Wiederholungen; `nil` heisst „wie geplant“.
    case setDone(id: String, exerciseId: String, reps: Int?)
    /// Uhr → iPhone: dieses Geraet ist jetzt dran (eines ist besetzt).
    case choose(id: String, exerciseId: String)
    /// iPhone → Uhr: diese Botschaft ist angekommen.
    case ack(id: String)
    /// Beide Richtungen: das Training ist vorbei.
    case end

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data) -> WorkoutMessage? {
        try? JSONDecoder().decode(WorkoutMessage.self, from: data)
    }
}

/// Schluessel der WatchConnectivity-Woerterbuecher zwischen Sport und seiner Uhr.
enum SportWatchKeys {
    /// `updateApplicationContext`: der Privat-Token, damit die Uhr ein Padel-Ergebnis selbst
    /// beim Padel-Dienst abliefern kann.
    static let privateToken = "fh_private"
    /// `transferUserInfo` (Rueckfall): eine `WorkoutMessage` als JSON.
    static let workoutMessage = "workout"
    /// `transferUserInfo`, Uhr → iPhone: ein `PadelMatchReport` als JSON - zusaetzlich zum
    /// direkten Weg, falls die Uhr gerade kein Netz hat.
    static let padelReport = "padel"
}
