import Foundation

/// Das Gym in Healthy (Felix, 14.10.): Trainingstage mit Geraeten, Saetze
/// abhaken, „Training starten“.
///
/// Gezeigt wird der Stand des Dienstes und darueber, was in der Warteschlange
/// wartet (`GymOverlay`) - ein Haken steht sofort, auch im Keller ohne Netz,
/// und geht spaeter raus. Gerechnet wird beim Dienst: welcher Tag dran ist und
/// was „letztes Mal“ war.
@MainActor
@Observable
final class GymStore {

    private let api = GymAPI()
    private var queue: PendingChanges { PendingChanges.shared }

    /// Der Stand des Dienstes - ohne das, was noch wartet.
    private(set) var server: GymState?
    /// Ein Abruf, der vor einem Haken losging und nach dessen Antwort ankommt,
    /// ersetzt ihn nicht (wie im Logbook).
    @ObservationIgnored private var serverSequence = 0

    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var accessProblem = false

    /// Das laufende Training - nur hier gemerkt, nicht beim Dienst: ein Besuch,
    /// der nur durch Abhaken entstand, ist kein Training (Vertrag §6).
    private(set) var workout: ActiveWorkout? = ActiveWorkout.load()
    /// Das Geraet, das jemand in der Liste unten gewaehlt hat - sonst gilt das
    /// erste mit offenen Saetzen.
    var chosenExerciseId: String?

    @ObservationIgnored private let isDemo: Bool

    init() {
        #if DEBUG
        isDemo = ProcessInfo.processInfo.environment["COCKPIT_GYM_DEMO"] == "1"
        #else
        isDemo = false
        #endif
        if isDemo { workout = nil }
        if let workout, workout.isAbandoned() {
            ActiveWorkout.save(nil)
            self.workout = nil
        }
        queue.observe(.weight) { [weak self] event in self?.handle(event) }
    }

    /// Was fuer das Gym in der Warteschlange wartet.
    var pending: [GymChange] { queue.changes(for: .weight).compactMap(\.gym) }

    /// Was der Tab zeigt.
    var state: GymState? { server.map { GymOverlay.apply(pending, to: $0) } }

    var today: CalendarDate { .today() }

    // MARK: - Laden

    func load() async {
        isLoading = server == nil
        defer { isLoading = false }
        #if DEBUG
        if isDemo {
            if server == nil {
                server = GymDemo.state(today: today)
                // COCKPIT_GYM_WORKOUT=1: gleich mitten im Training, fuer Aufnahmen.
                if ProcessInfo.processInfo.environment["COCKPIT_GYM_WORKOUT"] == "1", let day = server?.days.first,
                   let first = day.exercises.first {
                    start(day)
                    toggle(first, 0, on: day)
                    toggle(first, 1, on: day)
                    WorkoutMirror.shared.showDemoMetrics()
                }
            }
            return
        }
        #endif
        await queue.waitUntilIdle(.weight, timeout: .seconds(3))
        let sequence = queue.nextSequence()
        do {
            let fresh = try await api.state()
            if sequence > serverSequence {
                server = fresh
                serverSequence = sequence
            }
            clearError()
        } catch {
            report(error)
        }
    }

    private func handle(_ event: PendingEvent) {
        switch event {
        case .delivered(let data, let sequence):
            // Die Antworten sind ein Geraet, ein Tag oder ein Besuch - was passt,
            // ersetzt den Stand; Logbook und Gewicht auf derselben Spur passen nicht.
            guard var current = server else { return }
            let decoder = APIClient.decoder()
            if let session = try? decoder.decode(GymSession.self, from: data) {
                current.sessions.removeAll { $0.id == session.id }
                current.sessions.append(session)
            } else if let day = try? decoder.decode(GymDay.self, from: data) {
                current.days.removeAll { $0.id == day.id }
                current.days.append(day)
                current.days.sort { $0.position < $1.position }
            } else if let machine = try? decoder.decode(GymMachine.self, from: data) {
                current.machines.removeAll { $0.id == machine.id }
                current.machines.append(machine)
            } else {
                return
            }
            server = current
            serverSequence = max(serverSequence, sequence)
        case .rejected:
            Task { await load() }
        case .drained:
            // Erst wenn alles da ist: Reihe und „letztes Mal“ rechnet der Dienst.
            Task { await load() }
        }
    }

    // MARK: - Trainingstage

    func addDay(name: String, weekdays: [Int]) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let state else { return }
        let position = (state.days.map(\.position).max() ?? -1) + 1
        send(.day(GymDay(id: GymID.make("d"), name: clean, position: position, exercises: [],
                         weekdays: weekdays.sorted())), label: clean)
    }

    /// Name und Wochentage eines Tages.
    func edit(_ day: GymDay, name: String, weekdays: [Int]) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = day
        if !clean.isEmpty { changed.name = clean }
        changed.weekdays = weekdays.sorted()
        guard changed != day else { return }
        send(.day(changed), label: changed.name)
    }

    /// Neue Reihenfolge der Tage - danach geht die Reihe A → B → C.
    func reorderDays(_ ids: [String]) {
        guard let state else { return }
        for (position, id) in ids.enumerated() {
            guard var day = state.day(id), day.position != position else { continue }
            day.position = position
            send(.day(day), label: day.name)
        }
    }

    /// Loeschen braucht Netz (Vertrag §6). Die Besuche bleiben, der Verlauf auch.
    func delete(_ day: GymDay) async -> Bool {
        if isDemo { server?.days.removeAll { $0.id == day.id }; return true }
        do {
            try await api.deleteDay(id: day.id)
            server?.days.removeAll { $0.id == day.id }
            clearError()
            return true
        } catch {
            report(error)
            return false
        }
    }

    // MARK: - Geraete am Tag

    /// Ein Geraet an einen Tag: ein vorhandenes oder ein neues mit diesem Namen.
    func addExercise(to day: GymDay, machineId: String?, newName: String?) {
        var machine: String
        if let machineId {
            machine = machineId
        } else {
            let clean = (newName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            // Ein gleichnamiges gibt es schon: das nehmen - sonst zerfiele der Verlauf.
            if let existing = state?.machines.first(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) {
                machine = existing.id
            } else {
                machine = GymID.make("m")
                send(.machine(GymMachine(id: machine, name: clean, archived: false, createdAt: nil)), label: clean)
            }
        }
        let exercise = GymExercise(id: GymID.make("e"), machineId: machine, sets: 3, reps: 10, weightKg: 0)
        send(.exercise(dayId: day.id, exercise: exercise), label: machineName(machine))
    }

    /// Gewicht, Saetze, Wiederholungen - im Training geaendert wird es der neue Plan (Felix, 14.10.).
    func update(_ exercise: GymExercise, in dayId: String) {
        send(.exercise(dayId: dayId, exercise: exercise), label: machineName(exercise.machineId))
    }

    func reorderExercises(of day: GymDay, _ ids: [String]) {
        var changed = day
        changed.exercises = ids.compactMap { id in day.exercises.first { $0.id == id } }
        guard changed.exercises != day.exercises else { return }
        send(.day(changed), label: day.name)
    }

    func remove(_ exercise: GymExercise, from day: GymDay) async -> Bool {
        if isDemo {
            if let index = server?.days.firstIndex(where: { $0.id == day.id }) {
                server?.days[index].exercises.removeAll { $0.id == exercise.id }
            }
            return true
        }
        do {
            try await api.deleteExercise(dayId: day.id, id: exercise.id)
            if let index = server?.days.firstIndex(where: { $0.id == day.id }) {
                server?.days[index].exercises.removeAll { $0.id == exercise.id }
            }
            clearError()
            return true
        } catch {
            report(error)
            return false
        }
    }

    func rename(machineId: String, to name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, var machine = state?.machine(machineId), machine.name != clean else { return }
        machine.name = clean
        send(.machine(machine), label: clean)
    }

    func machineName(_ id: String) -> String {
        state?.machine(id)?.name ?? "Gerät"
    }

    // MARK: - Haken

    /// Die Haken eines Tages von heute - aus allen Besuchen dieses Tages.
    func isDone(_ exercise: GymExercise, _ index: Int, on day: GymDay) -> Bool {
        state?.sessions(for: day.id, on: today).contains { $0.isDone(exercise.id, index) } ?? false
    }

    func doneCount(_ exercise: GymExercise, on day: GymDay) -> Int {
        (0..<max(exercise.sets, 1)).filter { isDone(exercise, $0, on: day) }.count
    }

    /// Ein Satz an oder aus. Ohne Besuch fuer diesen Tag legt der erste Haken
    /// einen an (Vertrag §6).
    func toggle(_ exercise: GymExercise, _ index: Int, on day: GymDay) {
        guard let state else { return }
        let sessions = state.sessions(for: day.id, on: today)
        if let session = sessions.first(where: { $0.isDone(exercise.id, index) }) {
            send(.tick(sessionId: session.id, exerciseId: exercise.id, index: index,
                       weightKg: nil, reps: nil, doneAt: nil), label: machineName(exercise.machineId))
            return
        }
        let sessionId = workoutSession(for: day) ?? openOrNewSession(for: day, in: state)
        send(.tick(sessionId: sessionId, exerciseId: exercise.id, index: index,
                   weightKg: exercise.weightKg, reps: exercise.reps, doneAt: Date()),
             label: machineName(exercise.machineId))
        // Fertig mit diesem Geraet: das naechste offene ist dran.
        if chosenExerciseId == exercise.id, doneCount(exercise, on: day) >= exercise.sets {
            chosenExerciseId = nil
        }
    }

    /// Der naechste offene Satz eines Geraets - fuer „Satz erledigt“ auf der Uhr.
    func tickNext(_ exercise: GymExercise, on day: GymDay) {
        guard let index = (0..<exercise.sets).first(where: { !isDone(exercise, $0, on: day) }) else { return }
        toggle(exercise, index, on: day)
    }

    private func workoutSession(for day: GymDay) -> String? {
        guard let workout, workout.dayId == day.id else { return nil }
        return workout.sessionId
    }

    private func openOrNewSession(for day: GymDay, in state: GymState) -> String {
        if let open = state.openSession(for: day.id, on: today) { return open.id }
        let id = GymID.make("s")
        send(.session(id: id, dayId: day.id, date: today, startedAt: Date(), endedAt: nil), label: day.name)
        return id
    }

    // MARK: - Training

    /// Der Tag, der vorgewaehlt ist: der mit dem heutigen Wochentag, sonst der
    /// in der Reihe (`GymState.suggestedDay`).
    var nextDay: GymDay? {
        state?.suggestedDay(on: today)
    }

    var workoutDay: GymDay? {
        guard let workout else { return nil }
        return state?.day(workout.dayId)
    }

    /// Das Geraet, das gerade dran ist: das gewaehlte, solange es offene Saetze
    /// hat, sonst das erste mit offenen Saetzen in der Reihenfolge des Tages.
    var currentExercise: GymExercise? {
        guard let day = workoutDay else { return nil }
        if let chosen = chosenExerciseId, let exercise = day.exercises.first(where: { $0.id == chosen }),
           doneCount(exercise, on: day) < exercise.sets {
            return exercise
        }
        return day.exercises.first { doneCount($0, on: day) < $0.sets }
    }

    func start(_ day: GymDay) {
        guard let state else { return }
        let now = Date()
        // Wurde heute an diesem Tag schon abgehakt, laeuft das Training in diesem Besuch weiter.
        let sessionId: String
        if let open = state.openSession(for: day.id, on: today) {
            sessionId = open.id
        } else {
            sessionId = GymID.make("s")
            send(.session(id: sessionId, dayId: day.id, date: today, startedAt: now, endedAt: nil), label: day.name)
        }
        let active = ActiveWorkout(sessionId: sessionId, dayId: day.id, date: today, startedAt: now)
        workout = active
        chosenExerciseId = nil
        if !isDemo { ActiveWorkout.save(active) }
    }

    func finish() {
        guard let workout, let state else { return }
        if let session = state.sessions.first(where: { $0.id == workout.sessionId }) {
            send(.session(id: session.id, dayId: session.dayId, date: session.date, startedAt: session.startedAt,
                          endedAt: Date()), label: state.day(session.dayId)?.name ?? "Training")
        }
        self.workout = nil
        chosenExerciseId = nil
        if !isDemo { ActiveWorkout.save(nil) }
    }

    // MARK: - Verlauf

    func history(of machineId: String) async -> [GymHistoryPoint] {
        #if DEBUG
        if isDemo { return GymDemo.history(machineId: machineId, today: today) }
        #endif
        return (try? await api.history(machineId: machineId)) ?? []
    }

    // MARK: - Intern

    private func send(_ change: GymChange, label: String) {
        if isDemo {
            // Vorfuehrdaten: nur im Speicher, nie gesendet.
            if let server { self.server = GymOverlay.apply([change], to: server) }
            return
        }
        queue.enqueue(.gym(change), label: label)
    }

    private func clearError() {
        error = nil
        accessProblem = false
    }

    private func report(_ error: Error) {
        if case APIError.notAuthorised = error {
            accessProblem = true
            self.error = "Kein Zugang zum Weight Tracker."
        } else {
            accessProblem = false
            self.error = error.localizedDescription
        }
    }
}

/// Ein Training, das gerade laeuft - gemerkt, damit es einen Neustart der App
/// uebersteht.
struct ActiveWorkout: Codable, Equatable, Sendable {
    let sessionId: String
    let dayId: String
    let date: CalendarDate
    let startedAt: Date

    private static let key = "gym.activeWorkout"

    /// Nach zwoelf Stunden ist niemand mehr im Gym - vergessenes „Beenden“.
    func isAbandoned(now: Date = Date()) -> Bool {
        now.timeIntervalSince(startedAt) > 12 * 3600
    }

    static func load() -> ActiveWorkout? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(ActiveWorkout.self, from: $0) }
    }

    static func save(_ workout: ActiveWorkout?) {
        if let workout, let data = try? JSONEncoder().encode(workout) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
