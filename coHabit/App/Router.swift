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
    /// Ein Link, der ankam, bevor jemand angemeldet war.
    private(set) var pendingLink: DeepLink?

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
            pendingLink = link
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
    }
}

/// Eine kurze Meldung oben - „Erledigt", Fehler des Dienstes.
@MainActor
@Observable
final class Toast {
    static let shared = Toast()

    private(set) var message: String?
    private(set) var isError = false
    private var hideTask: Task<Void, Never>?

    private init() {}

    func show(_ text: String, error: Bool = false) {
        message = text
        isError = error
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(error ? 4 : 2.2))
            guard !Task.isCancelled else { return }
            self?.message = nil
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
