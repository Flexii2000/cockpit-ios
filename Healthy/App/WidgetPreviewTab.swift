#if DEBUG
import SwiftUI
import WidgetKit

/// Zeigt die Kalorien-Kachel in allen Groessen und Zustaenden.
///
/// Der einzige Weg, sie im Simulator anzusehen: `simctl` kann kein Widget auf
/// den Homebildschirm legen. Erreichbar ueber COCKPIT_TAB=widget, nur im
/// Debug-Build. Die Sperrbildschirm-Formen kommen hier nur angenaehert:
/// Apples Accessory-Tachos zeichnen nur in einer echten Kachel.
struct WidgetPreviewTab: View {

    @State private var state: WidgetState = .unreachable(nil)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    labelled("systemSmall – echte Daten") {
                        CaloriesWidgetView(family: .systemSmall, state: state)
                            .frame(width: 158, height: 158)
                    }
                    labelled("systemMedium – echte Daten") {
                        CaloriesWidgetView(family: .systemMedium, state: state)
                            .frame(width: 338, height: 158)
                    }
                    labelled("Sperrbildschirm – Ring und Rechteck") {
                        HStack(spacing: 12) {
                            CaloriesWidgetView(family: .accessoryCircular, state: state)
                                .frame(width: 72, height: 72)
                            CaloriesWidgetView(family: .accessoryRectangular, state: state)
                                .frame(width: 172, height: 72)
                        }
                        .padding(8)
                    }
                    labelled("ohne Zugang") {
                        CaloriesWidgetView(family: .systemSmall, state: .noAccess)
                            .frame(width: 158, height: 158)
                    }
                    labelled("nicht erreichbar, ohne alten Stand") {
                        CaloriesWidgetView(family: .systemSmall, state: .unreachable(nil))
                            .frame(width: 158, height: 158)
                    }
                }
                .padding()
            }
            .navigationTitle("Kachel")
            .task {
                // Ohne eigenen Cookie: in der App gibt es den gemeinsamen
                // Speicher, den `Access.applyCookies()` beim Start gefuellt hat.
                if let day = try? await FoodAPI().day(.today()) {
                    state = .value(RemainingCalories(day: day))
                }
            }
        }
    }

    private func labelled<Content: View>(_ title: String,
                                         @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}
#endif
