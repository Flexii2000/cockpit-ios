import Foundation

/// Haelt die Liste und schickt Haken und Rueckfaelle.
@MainActor
@Observable
final class HabitsStore {

    private let api = HabitsAPI()

    private(set) var habits: [HabitStatus] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var isAccessProblem = false
    /// Habits, deren Haken ohne Netz im Postausgang liegt. Die Zeile zeigt
    /// dann eine Uhr statt des Hakens - was der Server daraus macht, weiss
    /// erst der naechste Abruf.
    private(set) var pendingIDs: Set<String> = []

    func load() async {
        isLoading = habits.isEmpty
        defer { isLoading = false }
        do {
            habits = try await api.list()
            errorMessage = nil
            isAccessProblem = false
            // Eine frische Liste ist die Wahrheit - was bis eben wartete, ist
            // entweder drin oder wird beim naechsten Nachsenden nochmal geholt.
            if await Outbox.shared.count == 0 { pendingIDs.removeAll() }
        } catch {
            report(error)
        }
    }

    /// Was der Knopf am Habit tut - je nach Art etwas anderes.
    ///
    /// Build: Haken setzen oder zuruecknehmen. Quit: Rueckfall eintragen oder
    /// zuruecknehmen. Der Server antwortet mit dem neuen Stand; der ersetzt
    /// die Zeile, statt dass die Liste komplett neu laedt.
    func toggleToday(_ habit: HabitStatus) async {
        guard !habit.kind.isAutomatic else { return }
        do {
            let updated: HabitStatus
            switch habit.kind {
            case .build:
                updated = habit.doneToday
                    ? try await api.unmark(id: habit.id, date: .today())
                    : try await api.mark(id: habit.id)
            case .quit:
                // „erledigt" heisst hier: kein Rueckfall. Der Knopf traegt
                // einen ein - oder nimmt ihn zurueck, wenn er versehentlich war.
                updated = habit.doneToday
                    ? try await api.mark(id: habit.id)
                    : try await api.unmark(id: habit.id, date: .today())
            case .food, .steps:
                return
            }
            replace(updated)
        } catch APIError.queued {
            pendingIDs.insert(habit.id)
            errorMessage = nil
        } catch {
            report(error)
        }
    }

    @discardableResult
    func create(name: String, kind: HabitStatus.Kind, weeklyStepGoal: Int?) async -> Bool {
        do {
            let created = try await api.create(HabitDraft(
                name: name, kind: kind.rawValue, weeklyStepGoal: weeklyStepGoal))
            habits.append(created)
            errorMessage = nil
            return true
        } catch {
            report(error)
            return false
        }
    }

    func delete(_ habit: HabitStatus) async {
        do {
            try await api.delete(id: habit.id)
            habits.removeAll { $0.id == habit.id }
        } catch {
            report(error)
        }
    }

    private func replace(_ updated: HabitStatus) {
        if let index = habits.firstIndex(where: { $0.id == updated.id }) {
            habits[index] = updated
        }
        errorMessage = nil
    }

    private func report(_ error: Error) {
        if let apiError = error as? APIError, case .notAuthorised = apiError {
            isAccessProblem = true
        }
        errorMessage = error.localizedDescription
    }
}
