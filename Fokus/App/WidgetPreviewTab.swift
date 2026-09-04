#if DEBUG
import SwiftUI
import WidgetKit

/// Zeigt die Habits-Kachel klein und mittel - COCKPIT_TAB=widget.
struct WidgetPreviewTab: View {

    @State private var habits: HabitsWidgetState = .unreachable

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    labelled("Habits systemSmall") {
                        HabitsWidgetView(family: .systemSmall, state: habits)
                            .padding(14)
                            .frame(width: 158, height: 158)
                    }
                    labelled("Habits systemMedium") {
                        HabitsWidgetView(family: .systemMedium, state: habits)
                            .padding(14)
                            .frame(width: 338, height: 158)
                    }
                    labelled("ohne Zugang") {
                        HabitsWidgetView(family: .systemSmall, state: .noAccess)
                            .frame(width: 158, height: 158)
                    }
                }
                .padding()
            }
            .navigationTitle("Kachel")
            .task {
                if let list = try? await HabitsAPI().list() {
                    habits = .value(list, staleSince: OfflineStatus.shared.staleSince[.habits])
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
