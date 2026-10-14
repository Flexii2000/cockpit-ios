import SwiftUI

/// Was in der Leiste unten steht. Das Dashboard zuerst, und dort macht die
/// App auf: es fasst zusammen, was die anderen Tabs im Einzelnen zeigen.
/// Evaluation und Einkauf sind am 14.10. nach Fokus gezogen - fuer den Gym-Tab.
enum TabSelection: Hashable {
    case dashboard, food, weight
    #if DEBUG
    /// Nur zum Ansehen der Kacheln - siehe WidgetPreviewTab.
    case widget

    /// Ob der Vorschau-Tab in der Leiste steht: nur auf ausdrueckliche
    /// Anforderung. `#if DEBUG` allein reicht nicht - auf dem Geraet laeuft
    /// ein Debug-Build.
    static var showsWidgetPreview: Bool {
        ProcessInfo.processInfo.environment["COCKPIT_TAB"] == "widget"
    }
    #endif

    /// Womit die App aufmacht. Im Debug-Build ueber `COCKPIT_TAB` vorgebbar;
    /// `recovery` oeffnet das Dashboard samt dieser Seite, `logbook` und
    /// `effects` das Dashboard an dieser Stelle.
    static var initial: TabSelection {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["COCKPIT_TAB"] {
        case "food":       return .food
        case "weight":     return .weight
        case "widget":     return .widget
        default:           return .dashboard
        }
        #else
        return .dashboard
        #endif
    }
}

/// Die Seiten im Dashboard. Keine Tabs: iOS zeigt hoechstens fuenf, und was
/// zum Dashboard gehoert, soll dort bleiben. Das Logbook ist seit 12.10. keine
/// Seite mehr, es steht im Dashboard selbst.
enum DashboardPage: Hashable {
    case recovery

    /// Womit der Stapel im Dashboard aufmacht - im Debug-Build ueber
    /// `COCKPIT_TAB` vorgebbar, damit sich jede Seite aufnehmen laesst.
    static var initialPath: [DashboardPage] {
        #if DEBUG
        return ProcessInfo.processInfo.environment["COCKPIT_TAB"] == "recovery" ? [.recovery] : []
        #else
        return []
        #endif
    }
}

/// Stellen im Dashboard, zu denen gescrollt wird - der Tipp auf die Erinnerung
/// fuehrt zum Logbook.
enum DashboardAnchor: String, Hashable {
    case logbook, effects

    /// Im Debug-Build ueber `COCKPIT_TAB=logbook|effects` - fuer Bilder.
    static var initial: DashboardAnchor? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["COCKPIT_TAB"].flatMap(DashboardAnchor.init(rawValue:))
        #else
        return nil
        #endif
    }
}

/// Welcher Tab offen ist - erreichbar auch von ausserhalb der Oberflaeche.
@MainActor
@Observable
final class Router {
    static let shared = Router()
    var selection: TabSelection = .initial
    /// Der Stapel im Dashboard (die Recovery-Seite).
    var dashboardPath: [DashboardPage] = DashboardPage.initialPath
    /// Zaehlt die Bitten, im Essen-Tab heute zu zeigen. Ein Zaehler und kein
    /// Datum: der Tab soll auch dann springen, wenn schon heute gefragt war
    /// und inzwischen weitergeblaettert wurde.
    private(set) var foodTodayRequests = 0
    /// Zaehlt die Tipps auf die Erinnerung des Logbooks: das Dashboard scrollt
    /// dann zum Logbook und zeigt gestern (`LogbookStore.followToday`).
    private(set) var logbookRequests = 0

    private init() {}

    func show(_ tab: TabSelection) { selection = tab }

    /// Eine Seite im Dashboard, frisch oben auf dem Stapel.
    func open(_ page: DashboardPage) {
        selection = .dashboard
        dashboardPath = [page]
    }

    func showFoodToday() {
        selection = .food
        foodTodayRequests += 1
    }

    func follow(_ route: HealthyRoute) {
        switch route {
        case .food:       show(.food)
        case .foodToday:  showFoodToday()
        case .dashboard:
            selection = .dashboard
            dashboardPath = []
        case .logbook:
            selection = .dashboard
            dashboardPath = []
            logbookRequests += 1
        }
    }
}

struct RootView: View {

    @Environment(Access.self) private var access
    @Environment(\.scenePhase) private var scenePhase

    private var router: Router { Router.shared }
    private var setup: SetupPresenter { SetupPresenter.shared }

    var body: some View {
        @Bindable var router = router
        @Bindable var setup = setup
        TabView(selection: $router.selection) {
            Tab("Dashboard", systemImage: "rectangle.grid.2x2", value: TabSelection.dashboard) {
                DashboardTab()
            }
            Tab(Backend.food.title, systemImage: Backend.food.systemImage, value: TabSelection.food) {
                FoodTab()
            }
            Tab(Backend.weight.title, systemImage: Backend.weight.systemImage, value: TabSelection.weight) {
                WeightTab()
            }
            #if DEBUG
            if TabSelection.showsWidgetPreview {
                Tab("Kachel", systemImage: "square.grid.2x2", value: TabSelection.widget) {
                    WidgetPreviewTab()
                }
            }
            #endif
        }
        .onAppear {
            // Ohne Token zeigen die Tabs nur Anmeldeseiten - dann gleich das
            // Blatt aufmachen, auf dem man das aendern kann.
            if access.privateToken == nil || access.weightToken == nil { setup.isPresented = true }
        }
        .sheet(isPresented: $setup.isPresented) {
            SetupView(sections: [.privateToken, .weightToken])
        }
        // healthy://food - die Kalorien-Kachel. Startet sie die App erst, kommt
        // der Link genauso hier an.
        .onOpenURL { url in
            if let route = HealthyRoute.url(url) { router.follow(route) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Zurueck im Vordergrund heisst oft: zurueck im Netz. Was im
            // Postausgang und in der Warteschlange wartet, darf jetzt raus.
            PendingSync.foreground(phase == .active)
            if phase == .active {
                Task {
                    await handOverEvaluation()
                    await LogbookReminder.refresh()
                    await StepsWidgetBridge.refresh()
                    // Die Nacht von heute frueh, die Energie bis jetzt -
                    // hoechstens alle zehn Minuten.
                    await HealthSync.shared.syncIfDue()
                }
            }
        }
        .task {
            await handOverEvaluation()
            await LogbookReminder.refresh()
            // Die Schritte-Kacheln zaehlen gesperrt mit dem Schrittzaehler des
            // iPhones - fragen kann nur die App, und nur im Vordergrund.
            if HealthSync.shared.isAvailable { await StepsNow.requestPermission() }
            await StepsWidgetBridge.refresh()
        }
    }

    /// Die Evaluation wohnt seit 14.10. in Fokus. Healthy bietet seine Datei an,
    /// bis Fokus quittiert (`EvaluationHandoff`), und behaelt sie als Sicherung;
    /// die Erinnerungen um 21:30 kommen nur noch aus Fokus.
    private func handOverEvaluation() async {
        EvaluationHandoff.offer()
        await EvaluationHandoff.removeHealthyReminders()
    }
}
