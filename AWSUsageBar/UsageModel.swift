import Foundation
import ServiceManagement

/// Hält den Stand für Menüleiste und Ausklappfenster.
///
/// Fragt alle 5 Minuten und beim Öffnen. Das kostet nichts: der Dienst antwortet
/// aus seinem Zwischenstand, Cost Explorer fragt nur er selbst (alle 6 h).
@MainActor
@Observable
final class UsageModel {

    private(set) var usage: AWSUsage?
    private(set) var error: String?
    private(set) var isAccessProblem = false
    private(set) var isLoading = false
    private(set) var isSaving = false
    /// `nil`, solange der Schlüsselbund noch nicht gelesen ist.
    private(set) var hasToken: Bool?
    private(set) var lastFetch: Date?

    private var token: String?
    private var loop: Task<Void, Never>?

    static let interval: Duration = .seconds(300)

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    /// - Parameter ifOlderThan: beim Öffnen nur, wenn der letzte Abruf so alt ist -
    ///   sonst lädt jedes Aufklappen neu und die Zahlen springen.
    func refresh(ifOlderThan seconds: TimeInterval? = nil) async {
        if let seconds, let lastFetch, Date().timeIntervalSince(lastFetch) < seconds { return }
        if token == nil {
            // Die Abfrage kann einen Dialog zeigen und blockiert so lange.
            token = await Task.detached { TokenStore.read() }.value
            hasToken = token != nil
        }
        guard let token else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let (fresh, _) = try await client(token).usage()
            usage = fresh
            error = nil
            isAccessProblem = false
            lastFetch = Date()
        } catch {
            isAccessProblem = (error as? AWSUsageError) == .notAuthorised
            self.error = error.localizedDescription
        }
    }

    func saveToken(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = await Task.detached { TokenStore.save(trimmed) }.value
        token = trimmed
        hasToken = true
        await refresh()
    }

    /// - Returns: ob AWS das neue Budget angenommen hat.
    @discardableResult
    func setBudget(_ limit: Double) async -> Bool {
        guard let token else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let (fresh, _) = try await client(token).setBudget(limit: limit)
            usage = fresh
            error = nil
            lastFetch = Date()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func client(_ token: String) -> AWSUsageClient {
        AWSUsageClient(baseURL: AWSUsageEndpoint.url, token: token)
    }

    // MARK: - Beim Anmelden starten

    /// Gemerkt statt jedes Mal gefragt: `SMAppService` meldet keine Änderung, und
    /// der Schalter soll nach dem Umlegen gleich stimmen. Beim Öffnen neu gelesen -
    /// in den Systemeinstellungen kann man es auch abschalten.
    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled

    func readLaunchAtLogin() {
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchesAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            self.error = "Beim Anmelden starten: \(error.localizedDescription)"
        }
        readLaunchAtLogin()
    }
}
