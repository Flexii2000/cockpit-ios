import Foundation
import ServiceManagement
import UserNotifications

/// Hält den Stand für Menüleiste und Ausklappfenster.
///
/// Fragt jede Minute und beim Öffnen - so oft prüft der Dienst die Spot-Lage.
/// Das kostet nichts: der Dienst antwortet aus seinem Zwischenstand, Cost
/// Explorer fragt nur er selbst (alle 6 h).
@MainActor
@Observable
final class UsageModel {

    private(set) var usage: AWSUsage?
    private(set) var error: String?
    private(set) var isAccessProblem = false
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var isSavingVerda = false
    /// `nil`, solange der Schlüsselbund noch nicht gelesen ist.
    private(set) var hasToken: Bool?
    private(set) var lastFetch: Date?

    private var token: String?
    private var loop: Task<Void, Never>?
    private let notifications = NotificationRelay()

    static let interval: Duration = .seconds(60)

    func start() {
        guard loop == nil else { return }
        // Die einzige Mac-Mitteilung: „Spot frei“, während das LLM auf On-Demand läuft.
        UNUserNotificationCenter.current().delegate = notifications
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
            notifySpotIfDue(fresh)
        } catch {
            isAccessProblem = (error as? CloudUsageError) == .notAuthorised
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

    /// - Returns: ob AWS das neue Budget (Dollar) angenommen hat.
    @discardableResult
    func setBudget(_ limit: Double) async -> Bool {
        guard let token else { return false }
        isSaving = true
        defer { isSaving = false }
        return await apply { try await self.client(token).setBudget(limit: limit) }
    }

    /// - Returns: ob der Dienst das neue Verda-Budget (Euro) angenommen hat.
    @discardableResult
    func setVerdaBudget(_ limit: Double) async -> Bool {
        guard let token else { return false }
        isSavingVerda = true
        defer { isSavingVerda = false }
        return await apply { try await self.client(token).setVerdaBudget(limit: limit) }
    }

    private func apply(_ put: () async throws -> (usage: AWSUsage, data: Data)) async -> Bool {
        do {
            let (fresh, _) = try await put()
            usage = fresh
            error = nil
            lastFetch = Date()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func client(_ token: String) -> CloudUsageClient {
        CloudUsageClient(baseURL: CloudUsageEndpoint.url, token: token)
    }

    // MARK: - Spot frei

    private static let spotSentKey = "spotAlertSent"

    /// Einmal je On-Demand-Instanz (Felix, 02.11.); gemerkt über einen Neustart hinweg.
    private func notifySpotIfDue(_ usage: AWSUsage) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["COCKPIT_CLOUD_SNAPSHOT"] != nil { return }
        #endif
        let defaults = UserDefaults.standard
        let sent = defaults.stringArray(forKey: Self.spotSentKey) ?? []
        guard let alert = AWSSpotAlert.due(usage, sent: Set(sent)) else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "spot-\(alert.instanceID)", content: content, trigger: nil))
        defaults.set(Array((sent + [alert.instanceID]).suffix(20)), forKey: Self.spotSentKey)
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

/// Zeigt die Mitteilung auch, während das Ausklappfenster offen ist.
final class NotificationRelay: NSObject, UNUserNotificationCenterDelegate, Sendable {

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
