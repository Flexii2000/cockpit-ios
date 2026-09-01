import SwiftUI

/// Was in der Leiste unten steht. Eigener Typ statt `Backend`, weil der
/// Zugang-Tab zu keinem Dienst gehoert - und `Backend?` als Auswahl waere
/// an jeder Verwendungsstelle eine Umstaendlichkeit.
enum TabSelection: Hashable {
    case food, weight, finance, setup
}

/// Das Tab-Geruest. Jeder Tab ist eine eigene Datei, damit der Umbau von
/// WebView auf nativ (Phase 1 und 2) genau eine Datei anfasst.
struct RootView: View {

    @Environment(Access.self) private var access
    @State private var selection: TabSelection = .food

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
                FinanceTab()
            }
            Tab("Zugang", systemImage: "gearshape", value: TabSelection.setup) {
                SetupView()
            }
        }
        .onAppear {
            // Ohne Token zeigen die drei Dienst-Tabs nur Anmeldeseiten -
            // dann gleich dorthin, wo man das aendern kann.
            if !access.isConfigured { selection = .setup }
        }
    }
}
