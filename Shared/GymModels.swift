import Foundation

// Das Gym beim Weight Tracker (Vertrag `HEALTHY-CONTRACT.md` §6, seit 14.10.).
// Die Kennungen vergibt die App - deshalb darf jeder Schreibweg in die
// Warteschlange (`GymChange`), und ein Haken steht auch im Keller ohne Netz.

struct GymMachine: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var archived: Bool
    var createdAt: Date?
}

/// Ein Geraet an einem Trainingstag: „3×8 · 40 kg“.
struct GymExercise: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var machineId: String
    var sets: Int
    var reps: Int
    var weightKg: Double
}

struct GymDay: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var position: Int
    var exercises: [GymExercise]
    var updatedAt: Date?
}

/// Ein abgehakter Satz - mit dem Gewicht und den Wiederholungen des Moments.
struct GymSet: Codable, Equatable, Sendable {
    let exerciseId: String
    let machineId: String
    let index: Int
    let weightKg: Double
    let reps: Int
    var doneAt: Date?
}

/// Ein Besuch fuer einen Trainingstag.
struct GymSession: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var dayId: String
    var date: CalendarDate
    var startedAt: Date
    var endedAt: Date?
    var sets: [GymSet]

    func isDone(_ exerciseId: String, _ index: Int) -> Bool {
        sets.contains { $0.exerciseId == exerciseId && $0.index == index }
    }

    func doneCount(_ exerciseId: String) -> Int {
        sets.filter { $0.exerciseId == exerciseId }.count
    }
}

/// „Letztes Mal“ an einem Geraet (rechnet der Dienst).
struct GymLast: Codable, Equatable, Sendable {
    let date: CalendarDate
    let weightKg: Double
    let sets: Int
    let reps: Int
}

struct GymHistoryPoint: Codable, Equatable, Identifiable, Sendable {
    let date: CalendarDate
    let weightKg: Double
    let sets: Int
    let reps: Int
    var id: CalendarDate { date }
}

/// `GET /api/gym`.
struct GymState: Codable, Equatable, Sendable {
    let today: CalendarDate
    var machines: [GymMachine]
    var days: [GymDay]
    var nextDayId: String?
    /// Gestern bis morgen.
    var sessions: [GymSession]
    var last: [String: GymLast]

    static func empty(today: CalendarDate = .today()) -> GymState {
        GymState(today: today, machines: [], days: [], nextDayId: nil, sessions: [], last: [:])
    }

    func machine(_ id: String) -> GymMachine? { machines.first { $0.id == id } }
    func day(_ id: String) -> GymDay? { days.first { $0.id == id } }

    /// Der Besuch, an dem heute abgehakt wird: der juengste nicht beendete
    /// dieses Tages von heute (Vertrag §6: je Tag und Datum derselbe, solange er
    /// nicht beendet ist).
    func openSession(for dayId: String, on date: CalendarDate) -> GymSession? {
        sessions.filter { $0.dayId == dayId && $0.date == date && $0.endedAt == nil }
            .max { $0.startedAt < $1.startedAt }
    }

    /// Alle Besuche dieses Tages von heute - fuer die Haken auf der Karte, auch
    /// nach „Beenden“.
    func sessions(for dayId: String, on date: CalendarDate) -> [GymSession] {
        sessions.filter { $0.dayId == dayId && $0.date == date }
    }

}

/// Neue Kennungen der App - Vorsilbe wie im Vertrag (`m-`, `d-`, `e-`, `s-`).
enum GymID {
    static func make(_ prefix: Character) -> String {
        "\(prefix)-" + UUID().uuidString.lowercased()
    }
}

/// Gewicht deutsch: „37,5 kg“, „40 kg“, 0 als „ohne Gewicht“.
enum GymFormat {
    static func weight(_ kg: Double) -> String {
        guard kg > 0 else { return "ohne Gewicht" }
        let rounded = (kg * 100).rounded() / 100
        let text = rounded == rounded.rounded()
            ? String(Int(rounded))
            : rounded.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "de_DE")))
        return text + " kg"
    }

    /// „3×8“.
    static func scheme(sets: Int, reps: Int) -> String { "\(sets)×\(reps)" }

    /// „letztes Mal 3×8 · 37,5 kg“.
    static func last(_ last: GymLast) -> String {
        "letztes Mal " + scheme(sets: last.sets, reps: last.reps) + " · " + weight(last.weightKg)
    }
}
