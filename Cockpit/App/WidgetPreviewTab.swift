#if DEBUG
import SwiftUI
import WidgetKit

/// Zeigt die Kachel in allen Groessen und Zustaenden.
///
/// Der einzige Weg, sie im Simulator anzusehen: `simctl` kann kein Widget auf
/// den Homebildschirm legen, und in der Erweiterung selbst laesst sich nichts
/// aufnehmen. Erreichbar ueber COCKPIT_TAB=widget, nur im Debug-Build.
struct WidgetPreviewTab: View {

    @State private var state: WidgetState = .unreachable(nil)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    beschriftet("systemSmall – echte Daten") {
                        CaloriesWidgetView(family: .systemSmall, state: state)
                            .frame(width: 158, height: 158)
                    }
                    beschriftet("systemMedium – echte Daten") {
                        CaloriesWidgetView(family: .systemMedium, state: state)
                            .frame(width: 338, height: 158)
                    }
                    beschriftet("ohne Zugang") {
                        CaloriesWidgetView(family: .systemSmall, state: .noAccess)
                            .frame(width: 158, height: 158)
                    }
                    beschriftet("nicht erreichbar, ohne alten Stand") {
                        CaloriesWidgetView(family: .systemSmall, state: .unreachable(nil))
                            .frame(width: 158, height: 158)
                    }
                }
                .padding()
            }
            .navigationTitle("Kachel")
            .task { await laden() }
        }
    }

    private func beschriftet<Inhalt: View>(_ titel: String,
                                           @ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titel).font(.caption).foregroundStyle(.secondary)
            inhalt()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func laden() async {
        // Hier ohne eigenen Cookie: in der App gibt es den gemeinsamen
        // Speicher, den `Access.applyCookies()` beim Start gefuellt hat.
        if let day = try? await FoodAPI().day(.today()) {
            state = .value(RemainingCalories(day: day))
        }
    }
}
#endif
