import SwiftUI

/// Was in der Leiste unten steht. Eigener Typ statt `Backend`, weil der
/// Zugang-Tab zu keinem Dienst gehoert - und `Backend?` als Auswahl waere
/// an jeder Verwendungsstelle eine Umstaendlichkeit.
enum TabSelection: Hashable {
    case food, weight, finance, grades, setup
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
        case "grades":  return .grades
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

    /// Die Auswahl liegt im Router, damit eine Benachrichtigung sie umstellen
    /// kann (siehe `Router`).
    ///
    /// Berechnet und nicht gespeichert: eine private gespeicherte Eigenschaft
    /// zoege den erzeugten Initialisierer mit auf `private` herunter, und
    /// `CockpitApp` kaeme nicht mehr an ihn heran.
    private var router: Router { Router.shared }

    let financeLock: BiometricLock
    let gradesLock: BiometricLock

    /// Die Tabs, hinter denen etwas liegt, das nicht offen herumstehen soll.
    private var lockedTabs: [TabSelection: BiometricLock] {
        [.finance: financeLock, .grades: gradesLock]
    }

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selection) {
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
                FinanceTab(lock: financeLock)
            }
            Tab(Backend.grades.title,
                systemImage: Backend.grades.systemImage,
                value: TabSelection.grades) {
                GradesTab(lock: gradesLock)
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
            // Ohne Token zeigen die Dienst-Tabs nur Anmeldeseiten - dann
            // gleich dorthin, wo man das aendern kann.
            if !access.isConfigured { router.selection = .setup }
        }
        // Sichtschutz fuer den App-Umschalter. iOS macht die Vorschau in dem
        // Moment, in dem die App inaktiv wird - ohne diese Decke stuenden die
        // Kontostaende oder die Noten dort weiter offen, und die Sperre waere
        // mit einem Blick auf die Vorschau umgangen. Nur ueber den gesperrten
        // Tabs: bei Essen und Gewicht gibt es nichts zu verbergen, und ein
        // Flackern bei jedem Wegschalten waere laestig.
        .overlay {
            if lockedTabs[router.selection] != nil, scenePhase != .active {
                privacyCover
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Beim Verlassen wieder zu. Sonst schuetzt die Sperre nur den
            // ersten Blick und danach nie wieder. Beide zusperren, nicht nur
            // die des offenen Tabs: sonst stuende der andere beim naechsten
            // Wechsel offen, obwohl die App zwischendurch aus der Hand war.
            if phase != .active {
                financeLock.lock()
                gradesLock.lock()
            }
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
