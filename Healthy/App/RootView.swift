import SwiftUI

/// Was in der Leiste unten steht. Das Dashboard zuerst, und dort macht die
/// App auf: es fasst zusammen, was die anderen Tabs im Einzelnen zeigen.
enum TabSelection: Hashable {
    case dashboard, food, weight, evaluation, shopping
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
    /// `recovery` und `logbook` oeffnen das Dashboard samt dieser Seite.
    static var initial: TabSelection {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["COCKPIT_TAB"] {
        case "food":       return .food
        case "weight":     return .weight
        case "evaluation": return .evaluation
        case "shopping":   return .shopping
        case "widget":     return .widget
        default:           return .dashboard
        }
        #else
        return .dashboard
        #endif
    }
}

/// Die Seiten im Dashboard. Keine Tabs: iOS zeigt hoechstens fuenf, und die
/// Leiste ist mit Dashboard, Essen, Gewicht, Evaluation und Einkauf voll.
enum DashboardPage: Hashable {
    case recovery, logbook

    /// Womit der Stapel im Dashboard aufmacht - im Debug-Build ueber
    /// `COCKPIT_TAB` vorgebbar, damit sich jede Seite aufnehmen laesst.
    static var initialPath: [DashboardPage] {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["COCKPIT_TAB"] {
        case "recovery": return [.recovery]
        case "logbook":  return [.logbook]
        default:         return []
        }
        #else
        return []
        #endif
    }
}

/// Welcher Tab offen ist - erreichbar auch von ausserhalb der Oberflaeche.
@MainActor
@Observable
final class Router {
    static let shared = Router()
    var selection: TabSelection = .initial
    /// Der Stapel im Dashboard (Recovery- und Logbook-Seite).
    var dashboardPath: [DashboardPage] = DashboardPage.initialPath
    /// Zaehlt die Bitten, im Essen-Tab heute zu zeigen. Ein Zaehler und kein
    /// Datum: der Tab soll auch dann springen, wenn schon heute gefragt war
    /// und inzwischen weitergeblaettert wurde.
    private(set) var foodTodayRequests = 0

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
        case .evaluation: show(.evaluation)
        case .logbook:    open(.logbook)
        }
    }
}

struct RootView: View {

    @Environment(Access.self) private var access
    @Environment(\.scenePhase) private var scenePhase

    /// Lebt hier und nicht im Tab: die Frist laeuft, waehrend ein anderer Tab
    /// offen ist, und nur die Wurzel sieht jeden Wechsel.
    @State private var evaluationLock = EvaluationLock()

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
            Tab("Evaluation", systemImage: "heart.text.square", value: TabSelection.evaluation) {
                EvaluationTab(lock: evaluationLock)
            }
            // Nur mit Einkaufs-Token: die App zeigt, wofuer ein Zugang da ist
            // (docs/PLAN-AUFTEILUNG.md). Ohne Token bleibt die Leiste, wie sie
            // war - kein leerer Tab mit Fehlermeldung.
            if access.shoppingToken != nil {
                Tab(Backend.shopping.title, systemImage: Backend.shopping.systemImage,
                    value: TabSelection.shopping) {
                    ShoppingTab()
                }
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
            SetupView(sections: [.privateToken, .weightToken, .shoppingToken])
        }
        // healthy://food - die Kalorien-Kachel. Startet sie die App erst, kommt
        // der Link genauso hier an.
        .onOpenURL { url in
            if let route = HealthyRoute.url(url) { router.follow(route) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Zurueck im Vordergrund heisst oft: zurueck im Netz. Was im
            // Postausgang wartet, darf jetzt raus.
            if phase == .active {
                Task {
                    await Outbox.shared.replay()
                    await EvaluationReminder.refresh()
                    await LogbookReminder.refresh()
                    // Die Nacht von heute frueh, die Energie bis jetzt -
                    // hoechstens alle zehn Minuten.
                    await HealthSync.shared.syncIfDue()
                }
            }
            // Die Frist der Evaluation zaehlt auch, wenn man die App verlaesst
            // - aber nur, wenn man sie von diesem Tab aus verlaesst; aus einem
            // anderen Tab laeuft sie schon seit dem Wechsel dorthin.
            if router.selection == .evaluation {
                if phase == .active {
                    Task { await evaluationLock.returnToForeground() }
                } else {
                    evaluationLock.leave()
                }
            }
        }
        .onChange(of: router.selection) { old, new in
            if old == .evaluation { evaluationLock.leave() }
            if new == .evaluation { Task { await evaluationLock.show() } }
        }
        .task {
            await EvaluationReminder.refresh()
            await LogbookReminder.refresh()
            // Start direkt im Tab (Antippen der Erinnerung, COCKPIT_TAB):
            // dann gibt es keinen Wechsel, der fragen koennte.
            if router.selection == .evaluation { await evaluationLock.show() }
        }
    }
}
