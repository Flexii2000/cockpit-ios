import Foundation

/// Haelt, was die Recovery-Seite zeigt: heute, die HRV der letzten 30 oder 90
/// Tage und den Schlafbedarf. Gerechnet ist das alles im Weight Tracker.
@MainActor
@Observable
final class RecoveryStore {

    private let api = RecoveryAPI()

    private(set) var today: RecoveryDay?
    /// Die Tage mit einer Nacht im Zeitraum der Kurve.
    private(set) var history: [RecoveryDay] = []
    var range: RecoveryRange = .month
    private(set) var sleepNeedMinutes: Int?

    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var accessProblem = false

    /// Das Fenster der Kurve: heute und die Tage davor.
    var historyFrom: CalendarDate { .today().adding(days: -(range.rawValue - 1)) }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        #if DEBUG
        if DashboardDemo.isOn {
            let today = CalendarDate.today()
            self.today = DashboardDemo.recoveryDay(offset: 0, today: today)
            history = DashboardDemo.recoveryDays(from: historyFrom, to: today)
            sleepNeedMinutes = sleepNeedMinutes ?? 480
            return
        }
        #endif
        do {
            async let today = api.today()
            async let history = api.days(from: historyFrom, to: .today())
            self.today = try await today
            self.history = try await history
            clearError()
        } catch {
            report(error)
        }
        // Die Einstellung ist Beiwerk: fehlt sie, zeigt das Blatt die Vorgabe.
        if let settings = try? await api.settings() {
            sleepNeedMinutes = settings.sleepNeedMinutes
        }
    }

    func select(_ range: RecoveryRange) async {
        self.range = range
        #if DEBUG
        if DashboardDemo.isOn {
            history = DashboardDemo.recoveryDays(from: historyFrom, to: .today())
            return
        }
        #endif
        do {
            history = try await api.days(from: historyFrom, to: .today())
            clearError()
        } catch {
            report(error)
        }
    }

    /// Aendert den Schlafbedarf - und damit auch alte Scores: der Dienst
    /// rechnet bei jeder Anfrage neu. Deshalb danach alles frisch.
    func updateSleepNeed(_ minutes: Int) async -> Bool {
        #if DEBUG
        if DashboardDemo.isOn {
            sleepNeedMinutes = minutes
            return true
        }
        #endif
        do {
            sleepNeedMinutes = try await api.updateSettings(sleepNeedMinutes: minutes).sleepNeedMinutes
            clearError()
        } catch {
            report(error)
            return false
        }
        await load()
        return true
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
