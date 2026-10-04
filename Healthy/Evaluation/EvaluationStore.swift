import Foundation

/// Fragen und Antworten des Evaluation-Tabs - in einer Datei auf dem iPhone,
/// sonst nirgends (Felix, 04.10.).
///
/// Die Datei liegt mit Datenschutz „vollstaendig“: solange das iPhone gesperrt
/// ist, kann niemand sie lesen, auch die App nicht. Sie geht ins Backup des
/// iPhones, aber an keinen Server. Geladen wird erst hinter Face ID, und beim
/// Zusperren fliegt der Inhalt wieder aus dem Speicher.
@MainActor
@Observable
final class EvaluationStore {

    private(set) var data = EvaluationData()
    private(set) var isLoaded = false
    /// Die Datei war da, liess sich aber nicht lesen. Dann wird **nicht**
    /// gespeichert - ein leerer Stand ueberschriebe sonst alles Bisherige.
    private(set) var error: String?

    var range: EvaluationRange = .month
    /// Fragen, deren Linie im Diagramm aus ist.
    var hidden: Set<UUID> = []

    @ObservationIgnored private let file: URL
    @ObservationIgnored private let asksForReminders: Bool
    @ObservationIgnored private var isDemo = false

    /// - Parameter asksForReminders: ob die ersten Fragen nach der Erlaubnis
    ///   fuer Mitteilungen fragen. Tests nicht: mit der Erlaubnis meldet sich
    ///   Healthy auch fuer Push beim Kalorienzaehler an - aus dem Simulator.
    init(file: URL = EvaluationStore.defaultFile, asksForReminders: Bool = true) {
        self.file = file
        self.asksForReminders = asksForReminders
    }

    nonisolated static var defaultFile: URL {
        #if DEBUG
        if ProcessInfo.processInfo.environment["COCKPIT_EVALUATION_SCRATCH"] == "1" { return scratchFile }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Evaluation", isDirectory: true)
            .appendingPathComponent("evaluation.json")
    }

    #if DEBUG
    /// Fuer UI-Tests (`COCKPIT_EVALUATION_SCRATCH=1`): je Start eine frische
    /// Datei im Temp-Ordner - ein Test, der Fragen anlegt, soll weder auf
    /// alten Antworten aufsetzen noch welche hinterlassen.
    nonisolated private static let scratchFile = FileManager.default.temporaryDirectory
        .appendingPathComponent("evaluation-\(UUID().uuidString).json")
    #endif

    // MARK: - Laden und Speichern

    func load() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["COCKPIT_EVALUATION_DEMO"] == "1" {
            data = EvaluationDemo.data(today: .today())
            isDemo = true
            isLoaded = true
            return
        }
        #endif
        do {
            data = try Self.read(file) ?? EvaluationData()
            error = nil
            isLoaded = true
        } catch {
            self.error = "Evaluation nicht lesbar: \(error.localizedDescription)"
            isLoaded = false
        }
    }

    func unload() {
        data = EvaluationData()
        isLoaded = false
    }

    /// `nil`, wenn es die Datei noch nicht gibt; ein Fehler, wenn sie da ist,
    /// aber nicht zu lesen.
    nonisolated static func read(_ file: URL) throws -> EvaluationData? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(EvaluationData.self, from: Data(contentsOf: file))
    }

    private func save() {
        guard isLoaded, !isDemo else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(data).write(to: file, options: [.atomic, .completeFileProtection])
            error = nil
        } catch {
            self.error = "Nicht gespeichert: \(error.localizedDescription)"
        }
        let snapshot = data
        Task { await EvaluationReminder.schedule(snapshot) }
    }

    // MARK: - Antworten

    func value(of question: UUID, on date: CalendarDate) -> Int? {
        data.value(of: question, on: date)
    }

    /// Setzt eine Antwort - nur fuer heute und gestern. Derselbe Wert noch
    /// einmal nimmt sie zurueck.
    func toggle(_ value: Int, for question: UUID, on date: CalendarDate, today: CalendarDate = .today()) {
        guard EvaluationDays.editable(today: today).contains(date) else { return }
        let next = data.value(of: question, on: date) == value ? nil : value
        data.set(next, for: question, on: date)
        save()
    }

    // MARK: - Fragen

    /// Uebernimmt die Fragen aus dem Bearbeiten-Blatt. Leere fallen weg; was
    /// fehlt, verschwindet aus der Ansicht, seine Antworten bleiben in der Datei.
    func replaceQuestions(_ questions: [EvaluationQuestion]) {
        let cleaned = questions
            .map { EvaluationQuestion(id: $0.id, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.text.isEmpty }
        guard cleaned != data.questions else { return }
        let hadNone = data.questions.isEmpty
        data.questions = cleaned
        hidden.formIntersection(cleaned.map(\.id))
        save()
        // Die Erlaubnis im Zusammenhang erfragen: jetzt ist klar, wofuer.
        if hadNone, !cleaned.isEmpty, asksForReminders {
            Task {
                await Notifications.requestPermission()
                await EvaluationReminder.schedule(data)
            }
        }
    }
}

#if DEBUG
/// Ein Jahr erfundener Antworten fuer Aufnahmen im Simulator
/// (`COCKPIT_EVALUATION_DEMO=1`). Mit Platzhaltern statt echter Fragen - das
/// Repo ist oeffentlich. Wird nie gespeichert.
enum EvaluationDemo {
    static func data(today: CalendarDate) -> EvaluationData {
        let questions = ["Frage A", "Frage B", "Frage C"].map { EvaluationQuestion(text: $0) }
        var data = EvaluationData(questions: questions)
        var generator = SplitMix(seed: 42)
        var levels = [6.5, 7.0, 7.5]
        for offset in stride(from: 400, through: 0, by: -1) {
            // Ein paar Abende fehlen - Luecken gehoeren dazu.
            if generator.next() % 9 == 0 { continue }
            let date = today.adding(days: -offset)
            for (index, question) in questions.enumerated() {
                let step = Double(Int(generator.next() % 5) - 2) * 0.4
                levels[index] = min(9.5, max(2.5, levels[index] + step))
                data.set(Int(levels[index].rounded()), for: question.id, on: date)
            }
        }
        return data
    }

    /// Wiederholbarer Zufall, damit jede Aufnahme dieselben Werte zeigt.
    struct SplitMix {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }
}
#endif
