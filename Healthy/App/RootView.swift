import SwiftUI

/// Was in der Leiste unten steht.
enum TabSelection: Hashable {
    case food, weight, shopping
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

    /// Womit die App aufmacht. Im Debug-Build ueber `COCKPIT_TAB` vorgebbar.
    static var initial: TabSelection {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["COCKPIT_TAB"] {
        case "weight":   return .weight
        case "shopping": return .shopping
        case "widget":   return .widget
        default:         return .food
        }
        #else
        return .food
        #endif
    }
}

/// Welcher Tab offen ist - erreichbar auch von ausserhalb der Oberflaeche.
@MainActor
@Observable
final class Router {
    static let shared = Router()
    var selection: TabSelection = .initial
    private init() {}
    func show(_ tab: TabSelection) { selection = tab }
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
            Tab(Backend.food.title, systemImage: Backend.food.systemImage, value: TabSelection.food) {
                FoodTab()
            }
            Tab(Backend.weight.title, systemImage: Backend.weight.systemImage, value: TabSelection.weight) {
                WeightTab()
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
        .onChange(of: scenePhase) { _, phase in
            // Zurueck im Vordergrund heisst oft: zurueck im Netz. Was im
            // Postausgang wartet, darf jetzt raus.
            if phase == .active { Task { await Outbox.shared.replay() } }
        }
    }
}
