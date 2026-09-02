import SwiftUI

/// Was in der Leiste unten steht. Eigener Typ statt `Backend`, weil der
/// Zugang-Tab zu keinem Dienst gehoert - und `Backend?` als Auswahl waere
/// an jeder Verwendungsstelle eine Umstaendlichkeit.
enum TabSelection: Hashable {
    case food, weight, finance, setup
    #if DEBUG
    /// Nur zum Ansehen der Kachel - siehe WidgetPreviewTab.
    case widget

    /// Ob der Vorschau-Tab ueberhaupt in der Leiste steht.
    ///
    /// Nur, wenn er ausdruecklich angefordert wurde. `#if DEBUG` allein
    /// reicht als Schranke nicht: auf dem Geraet laeuft ein Debug-Build,
    /// jeder Debug-Tab waere also ein Tab, den Felix sieht - und dieser
    /// nuetzt ihm nichts.
    static var showsWidgetPreview: Bool {
        ProcessInfo.processInfo.environment["COCKPIT_TAB"] == "widget"
    }
    #endif

    /// Womit die App aufmacht. Im Debug-Build laesst sich das ueber
    /// `COCKPIT_TAB` vorgeben - so kann ein Skript jeden Tab einzeln
    /// aufnehmen, ohne dass jemand tippen muss.
    static var initial: TabSelection {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["COCKPIT_TAB"] {
        case "weight":  return .weight
        case "finance": return .finance
        case "setup":   return .setup
        case "widget":  return .widget
        default:        return .food
        }
        #else
        return .food
        #endif
    }
}

/// Das Tab-Geruest. Jeder Tab ist eine eigene Datei, damit der Umbau von
/// WebView auf nativ (Phase 1 und 2) genau eine Datei anfasst.
struct RootView: View {

    @Environment(Access.self) private var access
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: TabSelection = .initial

    let lock: FinanceLock

    var body: some View {
        TabView(selection: $selection) {
            Tab(Backend.food.title,
                systemImage: Backend.food.systemImage,
                value: TabSelection.food) {
                FoodTab()
            }
            Tab(Backend.weight.title,
                systemImage: Backend.weight.systemImage,
                value: TabSelection.weight) {
                WeightTab()
            }
            Tab(Backend.finance.title,
                systemImage: Backend.finance.systemImage,
                value: TabSelection.finance) {
                FinanceTab(lock: lock)
            }
            Tab("Zugang", systemImage: "gearshape", value: TabSelection.setup) {
                SetupView()
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
            // Ohne Token zeigen die drei Dienst-Tabs nur Anmeldeseiten -
            // dann gleich dorthin, wo man das aendern kann.
            if !access.isConfigured { selection = .setup }
        }
        // Sichtschutz fuer den App-Umschalter. iOS macht die Vorschau in dem
        // Moment, in dem die App inaktiv wird - ohne diese Decke stuenden die
        // Kontostaende dort weiter offen, und die Sperre waere mit einem Blick
        // auf die Vorschau umgangen. Nur ueber den Finanzen-Tab: bei Essen und
        // Gewicht gibt es nichts zu verbergen, und ein Flackern bei jedem
        // Wegschalten waere laestig.
        .overlay {
            if selection == .finance, scenePhase != .active {
                privacyCover
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Beim Verlassen wieder zu. Sonst schuetzt die Sperre nur den
            // ersten Blick und danach nie wieder.
            if phase != .active { lock.lock() }
        }
    }

    private var privacyCover: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
        }
        .ignoresSafeArea()
    }
}
