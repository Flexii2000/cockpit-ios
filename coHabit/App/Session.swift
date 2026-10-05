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
    /// Die eigene Farbe je Typ (Vertrag §5.2b) - aus `me`, beim Waehlen sofort.
    /// Eigens gefuehrt statt aus `me` berechnet: jede Ansicht, die nach Typ
    /// faerbt, liest das (`CohabitRef.typeColor`) und soll nur neu zeichnen,
    /// wenn sich die Farben aendern - nicht bei jedem Laden von `/me`.
    private(set) var typeColors: TypeColors = .defaults
    /// Warum die App wieder am Start steht - „Zugang ungültig".
    var signedOutReason: String?

    var isSignedIn: Bool { token != nil }
    var meId: String? { me?.person.id }

    private init() {
        var switched = false
        #if DEBUG
        switched = CohabitToken.seedFromEnvironment()
        NotificationImage.handOverDebugBase(to: CohabitGroup.defaults)
        #endif
        token = CohabitToken.load()
        if switched {
            // Eine andere Person (Debug-Schalter): deren Vorgaenger soll man
            // nicht mehr sehen, auch nicht ohne Netz.
            OfflineCache.clear()
            CohabitGroup.removeMe()
        }
        if token != nil && !switched {
            // Der letzte bekannte Stand, damit „Du", der Avatar und die
            // Farben sofort stimmen - frisch geholt wird gleich danach.
            me = CohabitGroup.loadMe()
            typeColors = me?.typeColors ?? .defaults
        }
    }

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
        CohabitGroup.saveMe(me)
        show(me.typeColors ?? .defaults)
    }

    private func show(_ colors: TypeColors) {
        if colors != typeColors { typeColors = colors }
    }

    /// Waehlt die Farbe eines Typs (Vertrag §5.2b): sofort ueberall, dann beim
    /// Dienst - nur dieser Platz. Schlaegt das fehl, springt die Wahl zurueck.
    /// - Returns: die Meldung des Dienstes, wenn es nicht ging.
    func chooseTypeColor(_ color: PaletteKey, for slot: TypeColorSlot, api: CohabitAPI? = nil) async -> String? {
        let previous = typeColors[slot]
        guard color != previous else { return nil }
        apply(typeColors.setting(color, for: slot))
        do {
            let saved = try await (api ?? self.api()).saveTypeColor(color, for: slot)
            // Ein zweiter Tipp auf denselben Platz, waehrend dieser unterwegs
            // war, hat Vorrang - sonst sprang die Wahl kurz zurueck.
            if typeColors[slot] == color { apply(typeColors.setting(saved[slot], for: slot)) }
            WidgetSync.typeColorsChanged(saved)
            return nil
        } catch {
            if typeColors[slot] == color { apply(typeColors.setting(previous, for: slot)) }
            return error.localizedDescription
        }
    }

    /// Zeigt Farben, bevor `/me` sie bringt - auch im Speicher der App-Gruppe,
    /// damit die Kachel und der naechste Start sie schon kennen. Nicht privat:
    /// die Tests stellen damit den Stand vor ihnen wieder her.
    func apply(_ colors: TypeColors) {
        if var me {
            me.typeColors = colors
            self.me = me
            CohabitGroup.saveMe(me)
        }
        show(colors)
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
        show(.defaults)
        CohabitGroup.removeMe()
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

    /// Neue Typfarben: der Stand der Kachel bekommt sie sofort (auch fuer den
    /// Fall, dass sie selbst nicht durchkommt), dann laden die Kacheln neu.
    @MainActor
    static func typeColorsChanged(_ colors: TypeColors) {
        if var data = CohabitGroup.loadWidgetData() {
            data.typeColors = colors
            CohabitGroup.saveWidgetData(data)
        }
        WidgetCenter.shared.reloadAllTimelines()
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

extension CohabitRef {
    /// Die Farbe in der App, ueberall: die eigene des Typs (Vertrag §5.2b).
    /// Liest `Session.typeColors` - so zeichnet sich jede Ansicht, die sie
    /// benutzt, nach einer Wahl auf der Seite „Farben" von selbst neu. Gibt es
    /// nur in der App; die Kachel faerbt mit `typeColor(in:)` und den Farben
    /// von `/widget`.
    @MainActor var typeColor: PaletteKey { typeColor(in: Session.shared.typeColors) }
}
