#if DEBUG
import SwiftUI
import WidgetKit

/// Zeigt die Fokus-Kachel und die Live-Aktivitaet - COCKPIT_TAB=widget.
struct WidgetPreviewTab: View {

    var body: some View {
        let today = FocusHandoff.loadToday()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    labelled("Fokus systemMedium, Session läuft") {
                        FocusWidgetView(state: FocusWidgetState(
                            session: .init(start: Date(), end: Date().addingTimeInterval(1_500), test: false),
                            todayMinutes: today.minutes, goal: today.goal))
                            .padding(14)
                            .frame(width: 338, height: 158)
                    }
                    labelled("Fokus systemMedium, ohne Session") {
                        FocusWidgetView(state: FocusWidgetState(session: nil, todayMinutes: today.minutes,
                                                                goal: today.goal))
                            .padding(14)
                            .frame(width: 338, height: 158)
                    }
                    labelled("Live-Aktivität (Sperrbildschirm)") {
                        FocusActivityView(start: Date().addingTimeInterval(-900),
                                          end: Date().addingTimeInterval(2_700),
                                          test: false, stale: false)
                            .frame(width: 358)
                            .background(Color.black.opacity(0.6))
                    }
                    labelled("Live-Aktivität, vorbei") {
                        FocusActivityView(start: Date().addingTimeInterval(-3_600),
                                          end: Date().addingTimeInterval(-600),
                                          test: false, stale: true)
                            .frame(width: 358)
                            .background(Color.black.opacity(0.6))
                    }
                }
                .padding()
            }
            .navigationTitle("Kachel")
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
