import Foundation

/// Eine Aenderung im Gym, sofort gezeigt und spaeter geschickt (Vertrag §6).
///
/// Jede ist ein PUT mit der Kennung der App und traegt den **ganzen** neuen
/// Stand ihres Ziels - deshalb gilt je Ziel die neueste (`role .state`), und
/// was davor wartet, darf wegfallen. Ein Tag schickt darum immer seine ganze
/// Liste mit, eine Uebung immer alle Felder.
///
/// Loeschen geht nicht hier hindurch: das braucht Netz (Vertrag §6).
enum GymChange: Codable, Equatable, Sendable {
    case machine(GymMachine)
    case day(GymDay)
    case exercise(dayId: String, exercise: GymExercise)
    case session(id: String, dayId: String, date: CalendarDate, startedAt: Date, endedAt: Date?)
    /// Ein Satz: mit Gewicht und Wiederholungen abgehakt, ohne wieder offen.
    case tick(sessionId: String, exerciseId: String, index: Int, weightKg: Double?, reps: Int?, doneAt: Date?)

    var target: String? {
        switch self {
        case .machine(let machine): "machine/" + machine.id
        case .day(let day): "day/" + day.id
        case .exercise(_, let exercise): "exercise/" + exercise.id
        case .session(let id, _, _, _, _): "session/" + id
        case .tick(let sessionId, let exerciseId, let index, _, _, _): Self.tickKey(sessionId, exerciseId, index)
        }
    }

    static func tickKey(_ sessionId: String, _ exerciseId: String, _ index: Int) -> String {
        "tick/\(sessionId)/\(exerciseId)/\(index)"
    }

    var role: PendingRole { .state }

    var request: PendingRequest {
        switch self {
        case .machine(let machine):
            PendingRequest(method: "PUT", path: "/api/gym/machines/\(machine.id)",
                           body: Self.encode(MachineBody(name: machine.name, archived: machine.archived)))
        case .day(let day):
            PendingRequest(method: "PUT", path: "/api/gym/days/\(day.id)",
                           body: Self.encode(DayBody(name: day.name, position: day.position,
                                                     exercises: day.exercises)))
        case .exercise(let dayId, let exercise):
            PendingRequest(method: "PUT", path: "/api/gym/days/\(dayId)/exercises/\(exercise.id)",
                           body: Self.encode(ExerciseBody(machineId: exercise.machineId, sets: exercise.sets,
                                                          reps: exercise.reps, weightKg: exercise.weightKg)))
        case .session(let id, let dayId, let date, let startedAt, let endedAt):
            PendingRequest(method: "PUT", path: "/api/gym/sessions/\(id)",
                           body: Self.encode(SessionBody(dayId: dayId, date: date, startedAt: startedAt,
                                                         endedAt: endedAt)))
        case .tick(let sessionId, let exerciseId, let index, let weightKg, let reps, let doneAt):
            PendingRequest(method: "PUT", path: "/api/gym/sessions/\(sessionId)/sets/\(exerciseId)/\(index)",
                           body: weightKg == nil || reps == nil
                               ? Data("{}".utf8)
                               : Self.encode(TickBody(weightKg: weightKg, reps: reps, doneAt: doneAt)))
        }
    }

    func notice(label: String, status: Int, message: String?) -> PendingNotice {
        if status == 404 {
            return PendingNotice(text: "„\(label)“ gibt es im Gym nicht mehr.", isInfo: true)
        }
        return .error("„\(label)“ ließ sich nicht speichern", message, status: status)
    }

    // MARK: - Ruempfe

    private struct MachineBody: Encodable { let name: String; let archived: Bool }
    private struct DayBody: Encodable { let name: String; let position: Int; let exercises: [GymExercise] }
    private struct ExerciseBody: Encodable { let machineId: String; let sets: Int; let reps: Int; let weightKg: Double }
    private struct SessionBody: Encodable { let dayId: String; let date: CalendarDate; let startedAt: Date; let endedAt: Date? }
    private struct TickBody: Encodable { let weightKg: Double?; let reps: Int?; let doneAt: Date? }

    private static func encode<T: Encodable>(_ body: T) -> Data? {
        try? APIClient.encoder().encode(body)
    }
}

/// Legt, was wartet, ueber den Stand des Dienstes - nur nachbilden, nicht
/// nachrechnen: `nextDayId` und „letztes Mal“ bleiben, wie der Dienst sie
/// zuletzt geschickt hat.
enum GymOverlay {

    static func apply(_ changes: [GymChange], to state: GymState) -> GymState {
        var state = state
        for change in changes {
            switch change {
            case .machine(let machine):
                if let index = state.machines.firstIndex(where: { $0.id == machine.id }) {
                    state.machines[index] = machine
                } else {
                    state.machines.append(machine)
                }
            case .day(let day):
                if let index = state.days.firstIndex(where: { $0.id == day.id }) {
                    state.days[index] = day
                } else {
                    state.days.append(day)
                }
                state.days.sort { $0.position < $1.position }
            case .exercise(let dayId, let exercise):
                guard let dayIndex = state.days.firstIndex(where: { $0.id == dayId }) else { continue }
                if let index = state.days[dayIndex].exercises.firstIndex(where: { $0.id == exercise.id }) {
                    state.days[dayIndex].exercises[index] = exercise
                } else {
                    state.days[dayIndex].exercises.append(exercise)
                }
            case .session(let id, let dayId, let date, let startedAt, let endedAt):
                if let index = state.sessions.firstIndex(where: { $0.id == id }) {
                    state.sessions[index].dayId = dayId
                    state.sessions[index].date = date
                    state.sessions[index].startedAt = startedAt
                    state.sessions[index].endedAt = endedAt
                } else {
                    state.sessions.append(GymSession(id: id, dayId: dayId, date: date, startedAt: startedAt,
                                                     endedAt: endedAt, sets: []))
                }
            case .tick(let sessionId, let exerciseId, let index, let weightKg, let reps, let doneAt):
                guard let sessionIndex = state.sessions.firstIndex(where: { $0.id == sessionId }) else { continue }
                state.sessions[sessionIndex].sets.removeAll { $0.exerciseId == exerciseId && $0.index == index }
                if let weightKg, let reps {
                    let machineId = state.days.lazy.flatMap(\.exercises).first { $0.id == exerciseId }?.machineId ?? ""
                    state.sessions[sessionIndex].sets.append(GymSet(exerciseId: exerciseId, machineId: machineId,
                                                                    index: index, weightKg: weightKg, reps: reps,
                                                                    doneAt: doneAt))
                }
            }
        }
        return state
    }
}
