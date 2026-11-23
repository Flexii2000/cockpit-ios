#if DEBUG
import SwiftUI
import WidgetKit

/// Zeigt die Fokus-Kachel, den To-Do-Countdown und die Live-Aktivitaet -
/// COCKPIT_TAB=widget. Der Countdown mit erfundenen Aufgaben, oben, weil der
/// Simulator nicht scrollen kann.
struct WidgetPreviewTab: View {

    var body: some View {
        let today = FocusHandoff.loadToday()
        let day = CalendarDate.today()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    labelled("Countdown systemSmall: in 60 Tagen, heute, überfällig, erledigt") {
                        LazyVGrid(columns: [GridItem(.fixed(158)), GridItem(.fixed(158))],
                                  alignment: .leading, spacing: 12) {
                            ForEach(Self.countdowns(day)) { todo in
                                TodoCountdownSmallView(state: .countdown(todo), day: day)
                                    .padding(16)
                                    .frame(width: 158, height: 158)
                                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 22))
                            }
                        }
                        .padding(10)
                    }
                    labelled("Countdown Sperrbildschirm: rechteckig, rund, Zeile") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                TodoCountdownRectangularView(state: .countdown(Self.countdowns(day)[0]), day: day)
                                    .frame(width: 160, height: 72)
                                TodoCountdownCircularView(state: .countdown(Self.countdowns(day)[0]), day: day)
                                    .frame(width: 72, height: 72)
                                TodoCountdownCircularView(state: .countdown(Self.countdowns(day)[2]), day: day)
                                    .frame(width: 72, height: 72)
                            }
                            TodoCountdownInlineView(state: .countdown(Self.countdowns(day)[0]), day: day)
                            TodoCountdownRectangularView(state: .empty, day: day)
                                .frame(width: 160, height: 72, alignment: .topLeading)
                        }
                        .padding(10)
                        .foregroundStyle(.white)
                        .background(Color.black.opacity(0.6))
                        .environment(\.colorScheme, .dark)
                    }
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

    /// Erfundene Aufgaben: in 60 Tagen, heute, seit 3 Tagen, erledigt.
    private static func countdowns(_ day: CalendarDate) -> [TodoCountdown] {
        [TodoCountdown(id: "a", title: "Klausur", area: "Uni", dueAt: day.adding(days: 60), isDone: false),
         TodoCountdown(id: "b", title: "Abgabe Hausarbeit", area: "Uni", dueAt: day, isDone: false),
         TodoCountdown(id: "c", title: "Steuererklärung", area: "Privat", dueAt: day.adding(days: -3), isDone: false),
         TodoCountdown(id: "d", title: "Anmeldung", area: "Uni", dueAt: day.adding(days: 10), isDone: true)]
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
