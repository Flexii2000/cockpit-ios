import Foundation

/// Hält, was der Cloud-Tab zeigt (AWS und Verda). Gerechnet wird im Dienst
/// `cloud-usage`; hier wird nur geholt, für den Weg ohne Netz abgelegt und die
/// Budgets werden weitergereicht.
@MainActor
@Observable
final class CloudStore {

    private(set) var usage: AWSUsage?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var isSavingVerda = false
    private(set) var error: String?
    private(set) var isAccessProblem = false

    /// Einmal je Start nach der Push-Erlaubnis fragen - und erst, wenn Zahlen da
    /// sind: die Pushes (50/75/90/100 %) hat Felix gewollt, aber die Frage gehört
    /// in den Moment, in dem er den Tab benutzt, nicht vor den Sperrbildschirm.
    private var askedForPush = false

    func load(access: Access) async {
        guard let token = access.privateToken else {
            usage = nil
            error = nil
            return
        }
        let client = CloudUsageClient(baseURL: Backend.cloud.url, token: token)
        if usage == nil { isLoading = true }
        defer { isLoading = false }
        do {
            let (fresh, data) = try await client.usage()
            usage = fresh
            error = nil
            isAccessProblem = false
            OfflineCache.store(data, for: client.usageURL)
            OfflineStatus.shared.online(.cloud)
            await askForPushOnce()
            await CloudPush.registerIfNeeded(privateToken: token)
        } catch CloudUsageError.offline {
            // Ohne Netz der letzte Stand, mit Datum in der Leiste - wie die übrigen Tabs.
            if let cached = OfflineCache.load(for: client.usageURL),
               let stored = try? CloudUsageCoding.decoder().decode(AWSUsage.self, from: cached.data) {
                usage = stored
                error = nil
                OfflineStatus.shared.servedFromCache(.cloud, fetchedAt: cached.fetchedAt)
            } else {
                report(CloudUsageError.offline)
            }
        } catch {
            report(error)
        }
    }

    /// - Returns: ob AWS das neue Budget (Dollar) angenommen hat.
    @discardableResult
    func setBudget(_ limit: Double, access: Access) async -> Bool {
        guard let token = access.privateToken else { return false }
        isSaving = true
        defer { isSaving = false }
        return await apply(token) { try await $0.setBudget(limit: limit) }
    }

    /// - Returns: ob der Dienst das neue Verda-Budget (Euro) angenommen hat.
    @discardableResult
    func setVerdaBudget(_ limit: Double, access: Access) async -> Bool {
        guard let token = access.privateToken else { return false }
        isSavingVerda = true
        defer { isSavingVerda = false }
        return await apply(token) { try await $0.setVerdaBudget(limit: limit) }
    }

    /// Beide Budgets antworten mit dem ganzen neuen Stand - der ersetzt den alten,
    /// auch offline.
    private func apply(_ token: String,
                       _ put: (CloudUsageClient) async throws -> (usage: AWSUsage, data: Data)) async -> Bool {
        let client = CloudUsageClient(baseURL: Backend.cloud.url, token: token)
        do {
            let (fresh, data) = try await put(client)
            usage = fresh
            error = nil
            OfflineCache.store(data, for: client.usageURL)
            return true
        } catch {
            report(error)
            return false
        }
    }

    private func report(_ error: Error) {
        isAccessProblem = (error as? CloudUsageError) == .notAuthorised
        self.error = error.localizedDescription
    }

    private func askForPushOnce() async {
        guard !askedForPush else { return }
        askedForPush = true
        await Notifications.requestPermission()
    }
}

/// Meldet Vault beim Dienst für die Budget-Pushes an.
///
/// Zwei Wege führen hierher: der Tab nach dem Laden und der AppDelegate, wenn
/// Apple eine (neue) Kennung vergibt - die kommt nach der Erlaubnis erst, wenn
/// der Tab längst fertig geladen hat.
enum CloudPush {

    /// Bis 02.11. `aws.registeredDeviceToken` (unter `/aws-usage`). Der neue
    /// Schlüssel meldet die Kennung nach dem Umzug einmal beim Dienst unter neuem
    /// Namen an - die Anmeldung ist idempotent, ein zweites Mal schadet nicht.
    private static let registeredKey = "cloud.registeredDeviceToken"

    static func registerIfNeeded(privateToken: String?) async {
        #if DEBUG
        // Wie bei Kalorienzaehler und Noten: kein Testlauf meldet eine
        // Simulator-Kennung beim Dienst an.
        if ProcessInfo.processInfo.environment["COCKPIT_NO_PUSH"] == "1" { return }
        #endif
        guard let privateToken, let device = Notifications.deviceToken else { return }
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: registeredKey) != device else { return }
        do {
            try await CloudUsageClient(baseURL: Backend.cloud.url, token: privateToken)
                .registerDevice(token: device)
            defaults.set(device, forKey: registeredKey)
        } catch {
            // Beim nächsten Laden des Tabs noch einmal - kein Grund, die Zahlen
            // deshalb nicht zu zeigen.
            print("Cloud-Push nicht angemeldet: \(error.localizedDescription)")
        }
    }
}
