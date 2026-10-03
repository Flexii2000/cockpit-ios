import SwiftUI

/// Die vier Bildschirme der unteren Leiste; „+" ist keiner, es oeffnet das
/// Anlegen als Blatt.
enum MainTab: Hashable {
    case today, timeline, stats, profile

    /// Womit die App aufmacht - im Debug-Build ueber `COCKPIT_TAB`.
    static var initial: MainTab {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["COCKPIT_TAB"] {
        case "timeline": return .timeline
        case "stats": return .stats
        case "profile": return .profile
        default: break
        }
        #endif
        return .today
    }
}

enum DetailSection: Hashable {
    case overview, chat
}

/// Was sich auf einen Bildschirm schieben laesst.
enum Route: Hashable {
    case cohabit(String, DetailSection)
    case friends
    case notifications
    case health
    case archived
    case appLinks
    case editProfile
    case export
}

/// Eine Einladung zum Anzeigen: eine offene (aus der Liste) oder ein
/// Einladungslink (`cohabit://join/…`).
enum InvitationTarget: Identifiable, Hashable {
    case pending(InvitationView)
    case pendingId(String)
    case join(String)

    var id: String {
        switch self {
        case .pending(let invitation): "p-" + invitation.id
        case .pendingId(let id): "p-" + id
        case .join(let code): "j-" + code
        }
    }
}

/// Wo die App gerade steht - erreichbar auch von ausserhalb der Oberflaeche
/// (Push, Kachel, Links).
@MainActor
@Observable
final class Router {

    static let shared = Router()

    var tab: MainTab = .initial
    var todayPath: [Route] = []
    var timelinePath: [Route] = []
    var statsPath: [Route] = []
    var profilePath: [Route] = []
    var showsCreate = false
    var invitation: InvitationTarget?
    /// Ein Co-Habit, dessen Abhaken sich oeffnen soll, sobald seine
    /// Detailseite geladen ist (`cohabit://cohabit/{id}/checkin`).
    var pendingCheckIn: String?
    /// Ein Link, der ankam, bevor jemand angemeldet war - einer, der erst mit
    /// Sitzung etwas bedeutet (ein Co-Habit, ein Tab).
    private(set) var pendingLink: DeepLink?
    /// Ohne Sitzung: die Registrierung zu einem Einladungslink, die der Start
    /// zeigt (`JoinView`) - aus „Link einfügen" oder aus einem geoeffneten Link.
    var joinCode: String?
    /// Ohne Sitzung: warum ein geoeffneter Link nicht anmelden konnte - steht
    /// auf dem Start wie ein Fehler bei „Link einfügen".
    var linkError: String?
    /// Ohne Sitzung meldet gerade ein geoeffneter Link an.
    private(set) var isSigningIn = false

    private init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["COCKPIT_TAB"] == "new" { showsCreate = true }
        #endif
    }

    /// Ob auf dem aktuellen Bildschirm etwas daraufgeschoben ist - dann
    /// verschwindet die untere Leiste (die Detailseite hat ihren eigenen Knopf).
    var isDeep: Bool {
        switch tab {
        case .today: !todayPath.isEmpty
        case .timeline: !timelinePath.isEmpty
        case .stats: !statsPath.isEmpty
        case .profile: !profilePath.isEmpty
        }
    }

    func open(_ url: URL) {
        guard let link = LinkParser.parse(url) else { return }
        open(link)
    }

    func open(_ link: DeepLink) {
        guard Session.shared.isSignedIn else {
            openWithoutSession(link)
            return
        }
        showsCreate = false
        switch link {
        case .today:
            tab = .today
            todayPath = []
        case .timeline:
            tab = .timeline
            timelinePath = []
        case .new:
            showsCreate = true
        case .stats:
            tab = .stats
        case .profile:
            tab = .profile
            profilePath = []
        case .friends:
            tab = .profile
            profilePath = [.friends]
        case .cohabit(let id):
            showCohabit(id, section: .overview)
        case .chat(let id):
            showCohabit(id, section: .chat)
        case .checkIn(let id):
            pendingCheckIn = id
            showCohabit(id, section: .overview)
        case .invitation(let id):
            invitation = .pendingId(id)
        case .join(let code):
            invitation = .join(code)
        case .setup, .healthySetup:
            // Ein neuer Zugang, waehrend schon jemand angemeldet ist - die
            // Sitzung prueft ihn und uebernimmt ihn, wenn er gilt.
            if let token = link.token {
                Task { await Session.shared.switchAccount(to: token) }
            }
        }
    }

    /// Ohne Sitzung: ein Link mit Token meldet sofort an (der Knopf „In der App
    /// öffnen" der Weboberflaeche, ein App- oder Healthy-Link), ein
    /// Einladungslink oeffnet die Registrierung - beides wie „Link einfügen"
    /// auf dem Start. Nur was erst mit Sitzung etwas bedeutet, wartet in
    /// `pendingLink`; ein Link mit Token landet dort nie, sonst liefe nach der
    /// Anmeldung noch eine zweite.
    private func openWithoutSession(_ link: DeepLink) {
        if let token = link.token {
            Task { await signIn(withLinkToken: token) }
        } else if case .join(let code) = link {
            linkError = nil
            joinCode = code
        } else {
            pendingLink = link
        }
    }

    private func signIn(withLinkToken token: String) async {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        linkError = nil
        linkError = await Session.shared.signIn(withLinkToken: token)
    }

    /// Nach der Anmeldung nachholen, was vorher angeklopft hat.
    func consumePendingLink() {
        guard let link = pendingLink else { return }
        pendingLink = nil
        if link.token == nil { open(link) }
    }

    func showCohabit(_ id: String, section: DetailSection) {
        tab = .today
        todayPath = [.cohabit(id, section)]
    }

    /// Den Chat eines Co-Habits auf dem aktuellen Bildschirm oeffnen (aus der Timeline).
    func push(_ route: Route) {
        switch tab {
        case .today: todayPath.append(route)
        case .timeline: timelinePath.append(route)
        case .stats: statsPath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    func reset() {
        tab = .today
        todayPath = []
        timelinePath = []
        statsPath = []
        profilePath = []
        showsCreate = false
        invitation = nil
        pendingCheckIn = nil
        joinCode = nil
        linkError = nil
    }
}

/// Eine kurze Meldung oben - „Erledigt", Fehler des Dienstes.
@MainActor
@Observable
final class Toast {
    static let shared = Toast()

    private(set) var message: String?
    /// Eine kleine Zeile unter einer grossen Meldung - „+20 P" und darunter
    /// „Basis 10 · Distanz 5 · Dauer 5" nach einem Lauf.
    private(set) var detail: String?
    private(set) var isError = false
    private var hideTask: Task<Void, Never>?

    private init() {}

    func show(_ text: String, detail: String? = nil, error: Bool = false) {
        message = text
        self.detail = detail
        isError = error
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(error ? 4 : (detail == nil ? 2.2 : 3.5)))
            guard !Task.isCancelled else { return }
            self?.message = nil
            self?.detail = nil
        }
    }

    func show(_ error: Error) {
        if case CohabitError.queued = error { return }
        show(error.localizedDescription, error: true)
    }
}

/// Zaehlt hoch, wenn sich etwas geaendert hat, das andere Bildschirme zeigen
/// (ein Haken, ein neues Co-Habit) - sie laden dann neu.
@MainActor
@Observable
final class DataBus {
    static let shared = DataBus()
    private(set) var revision = 0
    private init() {}

    func changed() {
        revision += 1
    }
}
