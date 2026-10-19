import Foundation

// Das Gym beim Weight Tracker (Vertrag `HEALTHY-CONTRACT.md` §6, seit 14.10.).
// Die Kennungen vergibt die App - deshalb darf jeder Schreibweg in die
// Warteschlange (`GymChange`), und ein Haken steht auch im Keller ohne Netz.

struct GymMachine: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var archived: Bool
    var createdAt: Date?
    /// Etwa die Sitzeinstellung (Felix, 19.10.) - haengt am Geraet, gilt also in
    /// jedem Tag damit. `""` loescht sie beim Dienst, `nil` laesst sie stehen.
    var note: String?
}

/// Ein Geraet an einem Trainingstag: „3×8 · 40 kg“, mit Spanne „2×8–10 · 40 kg“.
struct GymExercise: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var machineId: String
    var sets: Int
    /// Mit Spanne die obere Grenze - das Ziel, mit dem abgehakt wird (Felix, 19.10.).
    var reps: Int
    /// Die untere Grenze der Spanne. Eine ist es nur, wenn sie unter `reps`
    /// liegt: zum Entfernen schickt die App `reps` selbst, denn `nil` hiesse
    /// beim Dienst „bleibt“ (Vertrag §6).
    var repsMin: Int?
    var weightKg: Double
}

extension GymExercise {
    /// Eine echte Spanne, etwa 8...10 - sonst `nil`.
    static func range(reps: Int, repsMin: Int?) -> ClosedRange<Int>? {
        guard let repsMin, repsMin >= 1, repsMin < reps else { return nil }
        return repsMin...reps
    }

    var repsRange: ClosedRange<Int>? { Self.range(reps: reps, repsMin: repsMin) }

    /// Was „mindestens“ zeigt: ohne Spanne dieselbe Zahl wie `reps`.
    var repsLower: Int { repsRange?.lowerBound ?? reps }

    /// Eine neue obere Grenze. Die untere wandert mit, wenn sie sonst darueber
    /// laege - und ohne Spanne bleibt es ohne: eine eben entfernte
    /// (`repsMin == reps`) wuerde beim naechsten Plus sonst wieder eine.
    func withReps(_ value: Int) -> GymExercise {
        var changed = self
        changed.reps = value
        if let repsMin {
            changed.repsMin = repsRange == nil ? value : min(repsMin, value)
        }
        return changed
    }
}

struct GymDay: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var position: Int
    var exercises: [GymExercise]
    var updatedAt: Date?
    /// An welchen Wochentagen der Tag dran ist - ISO, 1 = Montag … 7 = Sonntag
    /// (Felix, 14.10.: „dienstags bekommt man den Dienstag“).
    var weekdays: [Int] = []
}

extension GymDay {
    // Aeltere Staende - vom Dienst, im Zwischenspeicher, in der Warteschlange -
    // kennen `weekdays` nicht. Ohne das hier waere der ganze Tab leer.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        position = try container.decode(Int.self, forKey: .position)
        exercises = try container.decode([GymExercise].self, forKey: .exercises)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        weekdays = try container.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
    }
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
    /// Die Wiederholungen der Saetze mit diesem, dem schwersten Gewicht, nach
    /// Satz (seit 19.10.) - leer in aelteren Staenden.
    var setReps: [Int] = []
}

extension GymLast {
    // Aeltere Antworten und Zwischenspeicher haben `setReps` nicht.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(CalendarDate.self, forKey: .date)
        weightKg = try container.decode(Double.self, forKey: .weightKg)
        sets = try container.decode(Int.self, forKey: .sets)
        reps = try container.decode(Int.self, forKey: .reps)
        setReps = try container.decodeIfPresent([Int].self, forKey: .setReps) ?? []
    }
}

struct GymHistoryPoint: Codable, Equatable, Identifiable, Sendable {
    let date: CalendarDate
    let weightKg: Double
    let sets: Int
    let reps: Int
    /// Wie bei `GymLast`; zwei Besuche an einem Tag: die des frueheren zuerst.
    var setReps: [Int] = []
    var id: CalendarDate { date }
}

extension GymHistoryPoint {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(CalendarDate.self, forKey: .date)
        weightKg = try container.decode(Double.self, forKey: .weightKg)
        sets = try container.decode(Int.self, forKey: .sets)
        reps = try container.decode(Int.self, forKey: .reps)
        setReps = try container.decodeIfPresent([Int].self, forKey: .setReps) ?? []
    }
}

/// Eine Muskelgruppe der Geraeteliste („Brust“ mit ihren Geraeten). Die Liste
/// kommt vom Dienst - so steht sie fuer iOS und Android an einer Stelle.
struct GymCatalogGroup: Codable, Equatable, Sendable {
    let name: String
    let entries: [String]
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
    var catalog: [GymCatalogGroup] = []

    static func empty(today: CalendarDate = .today()) -> GymState {
        GymState(today: today, machines: [], days: [], nextDayId: nil, sessions: [], last: [:])
    }

    func machine(_ id: String) -> GymMachine? { machines.first { $0.id == id } }
    func day(_ id: String) -> GymDay? { days.first { $0.id == id } }

    /// Der Tag, der beim Start vorgewaehlt ist (Vertrag §6): der mit dem
    /// heutigen Wochentag - haben ihn mehrere, der, der in der Reihe dran ist,
    /// sonst der vorderste. Hat ihn keiner: der in der Reihe.
    ///
    /// Hier und nicht im Dienst: im Gym ohne Netz kann der Stand von gestern
    /// sein, das Datum des Handys stimmt immer.
    func suggestedDay(on date: CalendarDate) -> GymDay? {
        let weekday = date.isoWeekday
        let matching = days.filter { $0.weekdays.contains(weekday) }
        if let next = nextDayId, let day = matching.first(where: { $0.id == next }) { return day }
        return matching.first ?? nextDayId.flatMap(day) ?? days.first
    }

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

extension GymState {
    // `catalog` gibt es erst seit dem Nachtrag vom 14.10. - aeltere Staende im
    // Zwischenspeicher haben es nicht.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        today = try container.decode(CalendarDate.self, forKey: .today)
        machines = try container.decode([GymMachine].self, forKey: .machines)
        days = try container.decode([GymDay].self, forKey: .days)
        nextDayId = try container.decodeIfPresent(String.self, forKey: .nextDayId)
        sessions = try container.decode([GymSession].self, forKey: .sessions)
        last = try container.decode([String: GymLast].self, forKey: .last)
        catalog = try container.decodeIfPresent([GymCatalogGroup].self, forKey: .catalog) ?? []
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

    /// „3×8“, mit Spanne „2×8–10“.
    static func scheme(sets: Int, reps: Int, repsMin: Int? = nil) -> String {
        "\(sets)×" + (GymExercise.range(reps: reps, repsMin: repsMin).map(range) ?? "\(reps)")
    }

    /// „8–10“, mit Halbgeviertstrich wie im Vertrag.
    static func range(_ range: ClosedRange<Int>) -> String {
        "\(range.lowerBound)–\(range.upperBound)"
    }

    static let weekdayNames = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    /// „Di · Fr“ - ISO-Wochentage, Montag zuerst.
    static func weekdays(_ days: [Int]) -> String {
        days.sorted().filter { (1...7).contains($0) }.map { weekdayNames[$0 - 1] }.joined(separator: " · ")
    }

    /// Was im Gewichtsfeld steht, als Zahl: „37,5“ und „37.5“ gehen, ein
    /// angehaengtes „kg“ auch; leer ist 0 (ohne Gewicht). Unsinn und mehr als
    /// 500 kg: `nil` - dann bleibt das alte Gewicht.
    static func parseWeight(_ text: String) -> Double? {
        var clean = text.trimmingCharacters(in: .whitespaces).lowercased()
        if clean.hasSuffix("kg") { clean = String(clean.dropLast(2)).trimmingCharacters(in: .whitespaces) }
        if clean.isEmpty { return 0 }
        guard let value = Double(clean.replacingOccurrences(of: ",", with: ".")),
              value.isFinite, value >= 0, value <= 500 else { return nil }
        return (value * 100).rounded() / 100
    }

    /// Das Gewicht im Eingabefeld: „37,5“, „40“ - ohne Gewicht bleibt es leer.
    static func weightField(_ kg: Double) -> String {
        guard kg > 0 else { return "" }
        return String(weight(kg).dropLast(3))
    }

    /// „letztes Mal 3×8 · 37,5 kg“, „letztes Mal 10, 9 · 40 kg“.
    static func last(_ last: GymLast) -> String {
        "letztes Mal " + sets(last.setReps, sets: last.sets, reps: last.reps) + " · " + weight(last.weightKg)
    }

    /// Eine Zeile im Verlauf: „3×8 · 37,5 kg“, „10, 9 · 40 kg“.
    static func history(_ point: GymHistoryPoint) -> String {
        sets(point.setReps, sets: point.sets, reps: point.reps) + " · " + weight(point.weightKg)
    }

    /// Die Saetze mit dem schwersten Gewicht (Vertrag §6, 19.10.): alle gleich
    /// „2×10“ - so viele Saetze, wie es mit diesem Gewicht waren -, sonst jeder
    /// einzeln „10, 9“. Ohne `setReps` (aeltere Staende) wie bisher aus `sets`
    /// und `reps`.
    static func sets(_ setReps: [Int], sets: Int, reps: Int) -> String {
        guard let first = setReps.first else { return scheme(sets: sets, reps: reps) }
        return setReps.allSatisfy { $0 == first }
            ? scheme(sets: setReps.count, reps: first)
            : setReps.map(String.init).joined(separator: ", ")
    }

    /// Die Notiz, wie sie zum Dienst geht: ohne Leerraum aussen und hoechstens
    /// 200 Zeichen. Gezaehlt wie der Dienst (Java, UTF-16) - mehr kaeme als
    /// Ablehnung zurueck, und die Notiz waere weg.
    static func note(_ text: String) -> String {
        var kept = ""
        for character in text.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard kept.utf16.count + character.utf16.count <= 200 else { break }
            kept.append(character)
        }
        return kept.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
