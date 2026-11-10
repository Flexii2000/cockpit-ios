import Foundation

/// Haelt, was das Strain-Fenster zeigt: die Tage des gewaehlten Zeitraums.
/// Gerechnet ist alles im Weight Tracker (Vertrag §7).
@MainActor
@Observable
final class StrainStore {

    private let api = StrainAPI()

    /// Jeder Kalendertag des Zeitraums ab dem ersten gespeicherten - auch Tage
    /// ohne Histogramm, mit den Werten ihres Morgens.
    private(set) var days: [StrainDay] = []
    private(set) var range = StrainRange.load()

    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var error: String?
    private(set) var accessProblem = false

    /// Das Fenster der Diagramme: heute und die Tage davor.
    var from: CalendarDate { .today().adding(days: -(range.rawValue - 1)) }

    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        let today = CalendarDate.today()
        let from = from
        #if DEBUG
        if DashboardDemo.isOn {
            days = DashboardDemo.strainDays(from: from, to: today)
            return
        }
        #endif
        do {
            days = try await api.days(from: from, to: today)
            error = nil
            accessProblem = false
        } catch APIError.notAuthorised {
            accessProblem = true
            error = "Kein Zugang zum Weight Tracker."
        } catch {
            accessProblem = false
            self.error = error.localizedDescription
        }
    }

    /// Der Zeitraum wird gemerkt - wer ein Jahr sehen will, will das beim
    /// naechsten Mal auch.
    func select(_ range: StrainRange) async {
        guard range != self.range else { return }
        self.range = range
        range.save()
        await load()
    }
}
