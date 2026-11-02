import AppKit
import Foundation
import ServiceManagement
import UserNotifications

/// Hält den Stand für Menüleiste und Ausklappfenster.
///
/// Fragt alle 5 Minuten, beim Öffnen, nach dem Aufwachen und kurz nach dem
/// Wochen-Reset. claude.ai verlangt dafür nichts; die Seite „Nutzung“ fragt
/// genauso oft.
@MainActor
@Observable
final class UsageModel {

    enum Phase: Equatable {
        /// Schlüsselbund noch nicht gelesen.
        case starting
        case signedOut
        case signedIn
        /// Cloudflare will eine Prüfung sehen - im Anmeldefenster geht sie durch.
        case challenged
    }

    private(set) var usage: ClaudeUsage?
    private(set) var phase: Phase = .starting
    private(set) var error: String?
    private(set) var isLoading = false
    private(set) var lastFetch: Date?
    /// Springt nach einer gelungenen Anmeldung um - das Anmeldefenster schließt sich dann.
    private(set) var loginCompletedAt: Date?

    let web = ClaudeWeb()

    private var organization: String?
    private var loop: Task<Void, Never>?
    private var wake: Task<Void, Never>?
    private var resetTimer: Task<Void, Never>?
    private let notifications = NotificationRelay()

    static let interval: Duration = .seconds(300)

    #if DEBUG
    /// Für die Bilder (`Snapshot`) - ohne claude.ai, ohne Schlüsselbund.
    init(preview usage: ClaudeUsage?, at date: Date) {
        self.usage = usage
        phase = usage == nil ? .signedOut : .signedIn
        lastFetch = usage == nil ? nil : date
    }
    #endif

    init() {}

    func start() {
        guard loop == nil else { return }
        UNUserNotificationCenter.current().delegate = notifications
        loop = Task { [weak self] in
            await self?.restoreSession()
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Self.interval)
            }
        }
        wake = Task { [weak self] in
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: NSWorkspace.didWakeNotification) {
                // Das Netz ist direkt nach dem Aufwachen oft noch nicht da.
                try? await Task.sleep(for: .seconds(10))
                await self?.refresh()
            }
        }
    }

    private func restoreSession() async {
        if let cookies = await Task.detached(operation: { SessionKeychain.load() }).value {
            await web.restore(cookies)
        }
        phase = await web.hasSession() ? .signedIn : .signedOut
    }

    /// - Parameter ifOlderThan: beim Öffnen nur, wenn der letzte Abruf so alt ist -
    ///   sonst lädt jedes Aufklappen neu und die Zahlen springen.
    func refresh(ifOlderThan seconds: TimeInterval? = nil) async {
        if let seconds, let lastFetch, Date().timeIntervalSince(lastFetch) < seconds { return }
        guard phase != .starting, !isLoading else { return }
        guard await web.hasSession() else {
            phase = .signedOut
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let organization = try await currentOrganization()
            let data = try await web.get("/api/organizations/\(organization)/usage")
            let fresh = try ClaudeUsage.parse(data)
            usage = fresh
            error = nil
            phase = .signedIn
            lastFetch = Date()
            await web.persistIfChanged()
            notifyIfDue(fresh)
            scheduleRefreshAfterReset(fresh)
        } catch ClaudeWeb.Failure.signedOut {
            phase = .signedOut
            organization = nil
            error = nil
        } catch ClaudeWeb.Failure.challenged {
            phase = .challenged
            error = nil
        } catch {
            self.error = Self.message(error)
        }
    }

    private func currentOrganization() async throws -> String {
        if let organization { return organization }
        let data = try await web.get("/api/organizations")
        let all = (try? JSONDecoder().decode([ClaudeOrganization].self, from: data)) ?? []
        guard let picked = ClaudeOrganization.pick(all, lastActive: await web.lastActiveOrganization()) else {
            throw ModelError.noSubscription
        }
        organization = picked.uuid
        return picked.uuid
    }

    private enum ModelError: Error { case noSubscription }

    private static func message(_ error: Error) -> String {
        switch error {
        case ModelError.noSubscription: "Kein Claude-Abo in diesem Konto"
        case ClaudeUsageParseError.notJSON: "claude.ai hat unerwartet geantwortet"
        case ClaudeWeb.Failure.http(let status): "claude.ai antwortet \(status)"
        case ClaudeWeb.Failure.unreachable: "claude.ai nicht erreichbar"
        default: error.localizedDescription
        }
    }

    /// Nach dem Reset sofort neu fragen, nicht erst beim nächsten 5-Minuten-Takt -
    /// sonst stünde die alte Woche noch bis zu fünf Minuten in der Leiste.
    private func scheduleRefreshAfterReset(_ usage: ClaudeUsage) {
        resetTimer?.cancel()
        guard let resetsAt = usage.weekly?.resetsAt else { return }
        let delay = resetsAt.timeIntervalSinceNow + 30
        guard delay > 0 else { return }
        resetTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    // MARK: - Anmelden und Abmelden

    /// Vor dem Anmeldefenster: eine abgelaufene Sitzung wegräumen, damit
    /// claude.ai die Anmeldeseite zeigt statt umzuleiten. Bei einer
    /// Cloudflare-Prüfung bleibt die Sitzung - das Fenster soll nur die Prüfung zeigen.
    func prepareLogin() async -> URL {
        if phase == .challenged { return ClaudeWeb.base }
        if phase == .signedOut {
            await web.forget()
            usage = nil
            lastFetch = nil
        }
        return ClaudeWeb.loginURL
    }

    enum LoginCheck { case done, noSession, notYet }

    /// Aus dem Anmeldefenster, sobald ein Sitzungs-Cookie da ist oder eine Seite
    /// fertig geladen hat. `notYet`: Sitzung da, aber claude.ai nimmt sie noch nicht
    /// (oder es lief gerade schon eine Abfrage) - das Fenster fragt dann gleich nach.
    func loginMayHaveCompleted() async -> LoginCheck {
        guard phase != .starting, await web.hasSession() else { return .noSession }
        guard !isLoading else { return .notYet }
        phase = .signedIn
        organization = nil
        await refresh()
        guard phase == .signedIn, usage != nil else { return .notYet }
        loginCompletedAt = Date()
        requestNotificationPermission()
        return .done
    }

    func signOut() async {
        resetTimer?.cancel()
        isLoading = true
        await web.signOut()
        isLoading = false
        usage = nil
        lastFetch = nil
        organization = nil
        error = nil
        phase = .signedOut
    }

    // MARK: - Mitteilungen

    private static let thresholdsKey = "weeklyThresholds"

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 50/75/90/100 % des Wochenlimits, je Woche einmal (Felix, 02.11.).
    private func notifyIfDue(_ usage: ClaudeUsage) {
        guard let weekly = usage.weekly else { return }
        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey: Self.thresholdsKey)
            .flatMap { try? JSONDecoder().decode(Thresholds.self, from: $0) }
        let stored = saved ?? Thresholds()
        let (due, next) = stored.check(percent: weekly.percent, resetsAt: weekly.resetsAt)
        if next != stored || saved == nil, let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: Self.thresholdsKey)
        }
        // Beim allerersten Abruf (gleich nach der Anmeldung) ist „50 % erreicht“
        // keine Neuigkeit - die Stufen gelten als gemeldet, gemeldet wird erst die nächste.
        guard let due, saved != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = due >= 100
            ? "Claude: Wochenlimit erreicht"
            : "Claude: \(ClaudeUsageFormat.percent(weekly.percent)) der Woche"
        if let resetsAt = weekly.resetsAt {
            content.body = "Reset \(ClaudeUsageFormat.resetTime(resetsAt)) · \(ClaudeUsageFormat.remaining(until: resetsAt))"
        }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "weekly-\(next.window ?? "-")-\(due)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Beim Anmelden starten

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
        } catch {
            self.error = "Beim Anmelden starten: \(error.localizedDescription)"
        }
        readLaunchAtLogin()
    }
}

/// Zeigt Mitteilungen auch, während das Ausklappfenster offen ist (dann gilt die
/// App als aktiv, und macOS würde sie sonst still schlucken). Completion-Handler
/// statt `async` - siehe CLAUDE.md, „Delegaten-Rückrufe“.
final class NotificationRelay: NSObject, UNUserNotificationCenterDelegate, Sendable {

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
