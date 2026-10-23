import Foundation

/// Der Padel-Tab (Felix, 23.10.): die Uebersicht des Dienstes und die Buchungen live aus
/// Playtomic, dazu jede Aenderung - die Antwort ist der neue Stand.
@MainActor
@Observable
final class PadelStore {

    private(set) var overview: PadelOverview?
    /// Live aus Playtomic; `nil`, solange nichts da ist.
    private(set) var bookings: [PadelBooking]?
    /// Playtomic kann fuer sich scheitern - dann nur dort die Meldung.
    private(set) var bookingsError: String?
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var accessProblem = false
    /// Waehrend eine Aenderung unterwegs ist - Knoepfe nicht doppelt.
    private(set) var isWorking = false

    @ObservationIgnored private let api = PadelAPI()
    @ObservationIgnored private let isDemo: Bool

    init() {
        #if DEBUG
        isDemo = ProcessInfo.processInfo.environment["COCKPIT_PADEL_DEMO"] == "1"
        #else
        isDemo = false
        #endif
    }

    #if DEBUG
    /// Fuer Unit-Tests: ein Stand nur im Speicher - nichts geht an den Dienst.
    init(memory overview: PadelOverview, bookings: [PadelBooking]) {
        isDemo = true
        self.overview = overview
        self.bookings = bookings
    }
    #endif

    var isOwner: Bool { overview?.viewer.owner ?? false }

    // MARK: - Laden

    func load() async {
        #if DEBUG
        if isDemo {
            if overview == nil {
                overview = PadelDemo.overview()
                bookings = PadelDemo.bookings()
            }
            return
        }
        #endif
        isLoading = overview == nil
        defer { isLoading = false }
        async let fresh = api.overview()
        async let live = api.bookings()
        do {
            overview = try await fresh
            clearError()
        } catch {
            report(error)
        }
        do {
            bookings = try await live
            bookingsError = nil
        } catch {
            bookingsError = "Playtomic: " + error.localizedDescription
        }
    }

    // MARK: - Termine

    func skip(_ o: PadelOccurrence, day: Bool = false) async {
        await change { try await $0.skip(o.id, day: day) }
    }

    func unskip(_ o: PadelOccurrence, day: Bool = false) async {
        await change { try await $0.unskip(o.id, day: day) }
    }

    func retry(_ o: PadelOccurrence) async {
        await change { try await $0.retry(o.id) }
    }

    func remove(_ o: PadelOccurrence, day: Bool = false) async {
        await change { try await $0.remove(o.id, day: day) }
    }

    @discardableResult
    func move(_ o: PadelOccurrence, date: String, start: String, minutes: Int) async -> Bool {
        await change { try await $0.move(o.id, to: PadelSlotRequest(date: date, start: start, durationMinutes: minutes)) }
    }

    @discardableResult
    func addOneOff(_ slot: PadelSlotRequest) async -> Bool {
        await change { try await $0.addOneOff(slot) }
    }

    // MARK: - Serien und Plaetze

    @discardableResult
    func createSeries(_ series: PadelSeriesRequest) async -> Bool {
        await change { try await $0.createSeries(series) }
    }

    /// Pausieren oder fortsetzen - alles andere geht unveraendert zurueck, auch der Mitspieler.
    func setActive(_ series: PadelSeries, _ active: Bool) async {
        let request = PadelSeriesRequest(weekday: series.weekday, start: series.start,
                                         durationMinutes: series.durationMinutes, active: active,
                                         latestStart: series.latestStart, club: series.club, partner: series.partner)
        await change { try await $0.updateSeries(series.id, request) }
    }

    func delete(_ series: PadelSeries) async {
        await change { try await $0.deleteSeries(series.id) }
    }

    func saveCourtOrder(_ ids: [String]) async {
        await change { try await $0.courtOrder(ids) }
    }

    // MARK: - Buchungen

    func cancel(_ booking: PadelBooking) async {
        await changeBookings { try await $0.cancel(booking.matchId) }
    }

    func publish(_ booking: PadelBooking) async {
        await changeBookings { try await $0.publish(booking.matchId) }
    }

    func merge(_ booking: PadelBooking) async {
        await changeBookings { try await $0.merge(booking.matchId) }
    }

    // MARK: - Intern

    /// Eine Aenderung, deren Antwort die neue Uebersicht ist. In den Vorfuehrdaten passiert nichts.
    @discardableResult
    private func change(_ operation: (PadelAPI) async throws -> PadelOverview) async -> Bool {
        guard !isDemo else { return true }
        isWorking = true
        defer { isWorking = false }
        do {
            overview = try await operation(api)
            clearError()
            return true
        } catch {
            report(error)
            return false
        }
    }

    private func changeBookings(_ operation: (PadelAPI) async throws -> [PadelBooking]) async {
        guard !isDemo else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            bookings = try await operation(api)
            clearError()
            // Stornieren und Zusammenfuehren aendern auch die Termine des Dienstes.
            if let fresh = try? await api.overview() { overview = fresh }
        } catch {
            report(error)
        }
    }

    private func clearError() {
        error = nil
        accessProblem = false
    }

    private func report(_ error: Error) {
        if case APIError.notAuthorised = error {
            accessProblem = true
            self.error = "Kein Zugang zu Padel."
        } else {
            accessProblem = false
            self.error = error.localizedDescription
        }
    }
}
