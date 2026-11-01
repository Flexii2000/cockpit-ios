import Foundation

/// Hält, was der AWS-Tab zeigt. Gerechnet wird im Dienst `aws-usage`; hier wird
/// nur geholt, für den Weg ohne Netz abgelegt und das Budget weitergereicht.
@MainActor
@Observable
final class AWSStore {

    private(set) var usage: AWSUsage?
    private(set) var isLoading = false
    private(set) var isSaving = false
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
        let client = AWSUsageClient(baseURL: Backend.aws.url, token: token)
        if usage == nil { isLoading = true }
        defer { isLoading = false }
        do {
            let (fresh, data) = try await client.usage()
            usage = fresh
            error = nil
            isAccessProblem = false
            OfflineCache.store(data, for: client.usageURL)
            OfflineStatus.shared.online(.aws)
            await askForPushOnce()
            await AWSPush.registerIfNeeded(privateToken: token)
        } catch AWSUsageError.offline {
            // Ohne Netz der letzte Stand, mit Datum in der Leiste - wie die übrigen Tabs.
            if let cached = OfflineCache.load(for: client.usageURL),
               let stored = try? AWSUsageCoding.decoder().decode(AWSUsage.self, from: cached.data) {
                usage = stored
                error = nil
                OfflineStatus.shared.servedFromCache(.aws, fetchedAt: cached.fetchedAt)
            } else {
                report(AWSUsageError.offline)
            }
        } catch {
            report(error)
        }
    }

    /// - Returns: ob AWS das neue Budget angenommen hat.
    @discardableResult
    func setBudget(_ limit: Double, access: Access) async -> Bool {
        guard let token = access.privateToken else { return false }
        let client = AWSUsageClient(baseURL: Backend.aws.url, token: token)
        isSaving = true
        defer { isSaving = false }
        do {
            let (fresh, data) = try await client.setBudget(limit: limit)
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
        isAccessProblem = (error as? AWSUsageError) == .notAuthorised
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
enum AWSPush {

    private static let registeredKey = "aws.registeredDeviceToken"

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
            try await AWSUsageClient(baseURL: Backend.aws.url, token: privateToken)
                .registerDevice(token: device)
            defaults.set(device, forKey: registeredKey)
        } catch {
            // Beim nächsten Laden des Tabs noch einmal - kein Grund, die Zahlen
            // deshalb nicht zu zeigen.
            print("AWS-Push nicht angemeldet: \(error.localizedDescription)")
        }
    }
}
