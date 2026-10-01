import SwiftUI
import WidgetKit

/// Wer angemeldet ist.
///
/// Kein Konto im ueblichen Sinn: ein Token je Person, eingefuegt als Link
/// (App-Link, Healthy-Link) oder ausgestellt beim Annehmen einer Einladung
/// (Vertrag §0, §1.2). Gespeichert wird er erst, wenn `GET /me` damit 200
/// liefert.
@MainActor
@Observable
final class Session {

    static let shared = Session()

    private(set) var token: String?
    private(set) var me: MeView?
    /// Warum die App wieder am Start steht - „Zugang ungültig".
    var signedOutReason: String?

    var isSignedIn: Bool { token != nil }
    var meId: String? { me?.person.id }

    private init() {
        var switched = false
        #if DEBUG
        switched = CohabitToken.seedFromEnvironment()
        #endif
        token = CohabitToken.load()
        if switched {
            // Eine andere Person (Debug-Schalter): deren Vorgaenger soll man
            // nicht mehr sehen, auch nicht ohne Netz.
            OfflineCache.clear()
            CohabitGroup.defaults.removeObject(forKey: Self.meKey)
        }
        if token != nil && !switched {
            // Der letzte bekannte Stand, damit „Du" und der Avatar sofort
            // stimmen - frisch geholt wird gleich danach.
            me = try? APIClient.decoder().decode(MeView.self, from: CohabitGroup.defaults.data(forKey: Self.meKey) ?? Data())
        }
    }

    private static let meKey = "cohabit.me"

    func api() -> CohabitAPI { CohabitAPI(token: token) }

    /// Prueft einen Token und uebernimmt ihn.
    @discardableResult
    func signIn(token raw: String) async throws -> MeView {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Ohne Speicher: ein alter Stand von /me gehoerte womoeglich jemand anderem.
        let me: MeView = try await CohabitAPI(token: token, usesCache: false).get("/me")
        CohabitToken.save(token)
        self.token = token
        store(me)
        signedOutReason = nil
        await CohabitOutbox.shared.refreshStatus()
        Router.shared.consumePendingLink()
        await PushRegistration.afterSignIn()
        WidgetSync.refreshSoon()
        return me
    }

    /// Meldet mit dem Token eines Links an - aus „Link einfügen" auf dem Start
    /// oder aus einem Link, der die App ohne Sitzung oeffnet.
    /// - Returns: warum es nicht ging (401 heisst „Link ungültig"), sonst `nil`.
    func signIn(withLinkToken token: String) async -> String? {
        do {
            try await signIn(token: token)
            return nil
        } catch CohabitError.unauthorized {
            return "Link ungültig"
        } catch {
            return error.localizedDescription
        }
    }

    /// Ein Setup-Link, waehrend schon jemand angemeldet ist.
    func switchAccount(to token: String) async {
        guard token != self.token else { return }
        do {
            let candidate: MeView = try await CohabitAPI(token: token, usesCache: false).get("/me")
            if candidate.person.id != me?.person.id {
                // Eine andere Person: nichts von der vorigen soll liegen bleiben.
                await wipe(reason: nil)
            }
            try await signIn(token: token)
            Toast.shared.show("Angemeldet als \(candidate.person.displayName)")
        } catch {
            Toast.shared.show("Link ungültig", error: true)
        }
    }

    func refreshMe() async {
        guard isSignedIn else { return }
        do {
            store(try await api().get("/me"))
        } catch CohabitError.unauthorized {
            await wipe(reason: "Zugang ungültig")
        } catch {
            // Ohne Netz bleibt der letzte Stand stehen.
        }
    }

    func store(_ me: MeView) {
        self.me = me
        if let data = try? APIClient.encoder().encode(me) {
            CohabitGroup.defaults.set(data, forKey: Self.meKey)
        }
    }

    /// Abmelden: beim Dienst den eigenen Token widerrufen und das Geraet
    /// austragen, dann lokal alles loeschen (Vertrag §5.4).
    func signOut() async {
        let api = api()
        try? await api.sendIgnoringResponse("DELETE", "/me/app-links/current")
        if let device = Notifications.deviceToken {
            try? await api.sendIgnoringResponse("DELETE", "/devices/\(device)")
        }
        await wipe(reason: nil)
    }

    /// Alles Lokale weg - Token, Speicher, Postausgang, Stand der Kachel.
    func wipe(reason: String?) async {
        CohabitToken.clear()
        token = nil
        me = nil
        CohabitGroup.defaults.removeObject(forKey: Self.meKey)
        OfflineCache.clear()
        await CohabitOutbox.shared.clear()
        CohabitGroup.clear()
        PhotoLoader.shared.clear()
        CohabitSync.shared.reset()
        CohabitHealthSync.shared.forget()
        TimelineFilter.clear()
        WidgetCenter.shared.reloadAllTimelines()
        Router.shared.reset()
        signedOutReason = reason
    }

    /// Jede 401 landet hier: der Token gilt nicht mehr (auf einem anderen
    /// Geraet abgemeldet, Account geloescht).
    func handle(_ error: Error) async -> Bool {
        if case CohabitError.unauthorized = error {
            await wipe(reason: "Zugang ungültig")
            return true
        }
        return false
    }
}

/// Die Kachel mit frischem Stand versorgen: die App holt `/widget`, legt es
/// in die App-Gruppe und laesst die Kacheln neu zeichnen.
enum WidgetSync {

    @MainActor private static var lastRefresh: Date?

    @MainActor
    static func refresh() async {
        guard Session.shared.isSignedIn else { return }
        lastRefresh = Date()
        guard let data: WidgetData = try? await Session.shared.api().get("/widget") else { return }
        CohabitGroup.saveWidgetData(data)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Nach dem Laden von „Heute" - hoechstens einmal pro Minute.
    @MainActor
    static func refreshSoon() {
        if let lastRefresh, Date().timeIntervalSince(lastRefresh) < 60 { return }
        Task { await refresh() }
    }

    /// Die eigene Aktion sofort zeigen (Vertrag §5.5), dann neu laden.
    @MainActor
    static func markDone(_ cohabitId: String) {
        if let data = CohabitGroup.loadWidgetData() {
            CohabitGroup.saveWidgetData(data.markingDone(cohabitId))
            WidgetCenter.shared.reloadAllTimelines()
        }
        Task { await refresh() }
    }
}
