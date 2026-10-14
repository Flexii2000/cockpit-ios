import SwiftUI

/// To-Do, Wald, Einkauf und Evaluation. Einkauf und Evaluation wohnen hier
/// seit 14.10. - Healthy brauchte den Platz in der Leiste fuer den Gym-Tab.
enum TabSelection: Hashable {
    case todo, forest, shopping, evaluation
    #if DEBUG
    case widget

    static var showsWidgetPreview: Bool {
        ProcessInfo.processInfo.environment["COCKPIT_TAB"] == "widget"
    }
    #endif

    static var initial: TabSelection {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["COCKPIT_TAB"] {
        case "widget":     return .widget
        case "forest":     return .forest
        case "shopping":   return .shopping
        case "evaluation": return .evaluation
        default:           break
        }
        #endif
        // Die Habits sind nach coHabit umgezogen - vorn steht jetzt To-Do.
        return .todo
    }
}

@MainActor
@Observable
final class Router {
    static let shared = Router()
    var selection: TabSelection = .initial
    /// Ein Link aus einer angetippten Meldung, bis die App ihn oeffnen kann.
    /// Gemerkt statt sofort geoeffnet: startet der Tipp die App erst, ist sie
    /// beim Eintreffen noch nicht aktiv, und iOS oeffnet dann nichts.
    var pendingLink: URL?
    private init() {}
    func show(_ tab: TabSelection) { selection = tab }
    func open(_ link: URL) { pendingLink = link }
}

struct RootView: View {

    @Environment(Access.self) private var access
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    /// Lebt hier und nicht im Tab: die Frist laeuft, waehrend ein anderer Tab
    /// offen ist, und nur die Wurzel sieht jeden Wechsel.
    @State private var evaluationLock = EvaluationLock()

    private var router: Router { Router.shared }
    private var setup: SetupPresenter { SetupPresenter.shared }

    var body: some View {
        @Bindable var router = router
        @Bindable var setup = setup
        TabView(selection: $router.selection) {
            Tab(Backend.todo.title, systemImage: Backend.todo.systemImage, value: TabSelection.todo) {
                TodoTab()
            }
            Tab("Wald", systemImage: "tree", value: TabSelection.forest) {
                ForestTab()
            }
            // Nur mit Einkaufs-Token, wie vorher in Healthy: ohne Token kein
            // leerer Tab mit Fehlermeldung.
            if access.shoppingToken != nil {
                Tab(Backend.shopping.title, systemImage: Backend.shopping.systemImage,
                    value: TabSelection.shopping) {
                    ShoppingTab()
                }
            }
            Tab("Evaluation", systemImage: "heart.text.square", value: TabSelection.evaluation) {
                EvaluationTab(lock: evaluationLock)
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
            if access.privateToken == nil { setup.isPresented = true }
        }
        .sheet(isPresented: $setup.isPresented) {
            SetupView(sections: [.privateToken, .shoppingToken])
        }
        // Ein Tipp auf die Fokus-Kachel (`.widgetURL`) - oder die Rueckkehr
        // aus der Kurzbefehle-App (`cockpit-fokus://forest`, siehe
        // ShortcutsBridge).
        .onOpenURL { url in
            if url.host() == "forest" { router.show(.forest) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Zurueck im Vordergrund heisst oft: zurueck im Netz.
            PendingSync.foreground(phase == .active)
            openPendingLink()
            if phase == .active {
                Task {
                    await EvaluationImportState.shared.runIfOffered()
                    await EvaluationReminder.refresh()
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
        .onChange(of: router.pendingLink, initial: true) { _, _ in openPendingLink() }
        .onChange(of: router.selection) { old, new in
            if old == .evaluation { evaluationLock.leave() }
            if new == .evaluation { Task { await evaluationLock.show() } }
        }
        .task {
            // Erst uebernehmen, was Healthy anbietet, dann die Sperre: der Tab
            // laedt seine Datei beim Entsperren und soll dann schon alles sehen.
            await EvaluationImportState.shared.runIfOffered()
            await EvaluationReminder.refresh()
            // Start direkt im Tab (Antippen der Erinnerung, COCKPIT_TAB): dann
            // gibt es keinen Wechsel, der fragen koennte.
            if router.selection == .evaluation { await evaluationLock.show() }
        }
    }

    /// Oeffnet den Link einer angetippten Meldung (eine Feature-Request-Karte)
    /// in Safari - sobald die App aktiv ist, nicht vorher.
    private func openPendingLink() {
        guard scenePhase == .active, let link = router.pendingLink else { return }
        router.pendingLink = nil
        openURL(link)
    }
}
