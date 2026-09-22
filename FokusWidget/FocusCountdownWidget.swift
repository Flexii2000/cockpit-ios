import SwiftUI
import WidgetKit

struct FocusEntry: TimelineEntry {
    let date: Date
    let state: FocusWidgetState
}

/// Die laufende Session kommt aus der App-Gruppe (kein Netz), die Habits
/// fuer die Zeit ohne Session wie bei der Habits-Kachel vom Dienst.
///
/// Zwei Eintraege je Zeitleiste, solange eine Session laeuft: jetzt (der
/// Countdown) und ihr Ende (die Habits). Dazwischen zaehlt der Countdown von
/// selbst. Die App und die Erweiterung `FokusMonitor` laden die Kachel bei
/// jedem Anfang und Ende neu.
struct FocusProvider: TimelineProvider {

    private let timeout: TimeInterval = 12

    func placeholder(in context: Context) -> FocusEntry {
        FocusEntry(date: Date(), state: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (FocusEntry) -> Void) {
        if context.isPreview {
            completion(FocusEntry(date: Date(), state: .placeholder))
            return
        }
        Task { completion(FocusEntry(date: Date(), state: await current())) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<FocusEntry>) -> Void) {
        Task {
            let now = Date()
            let state = await current()
            if let session = state.session, session.end > now {
                let entries = [FocusEntry(date: now, state: state),
                               FocusEntry(date: session.end,
                                          state: FocusWidgetState(session: nil, habits: state.habits))]
                completion(Timeline(entries: entries, policy: .after(session.end.addingTimeInterval(60))))
            } else {
                // Wie die Habits-Kachel: halbstuendlich plus Mitternacht.
                completion(Timeline(entries: [FocusEntry(date: now, state: state)],
                                    policy: .after(RemainingCalories.nextRefresh(after: now))))
            }
        }
    }

    private func current() async -> FocusWidgetState {
        let session = FocusHandoff.loadSession().flatMap { active -> FocusWidgetState.Session? in
            active.isOver() ? nil : FocusWidgetState.Session(start: active.start, end: active.end, test: active.test)
        }
        return FocusWidgetState(session: session, habits: await HabitsWidgetState.load(timeout: timeout))
    }
}

/// Die breite Flow-Kachel: Countdown der Session, sonst die Habits.
struct FocusCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.focus, provider: FocusProvider()) { entry in
            FocusWidgetView(state: entry.state)
                .containerBackground(.fill.tertiary, for: .widget)
                // Ein Tipp fuehrt dorthin, was gerade zu sehen ist: in den
                // Wald oder zu den Habits (RootView.onOpenURL).
                .widgetURL(URL(string: entry.state.session == nil ? "cockpit://habits" : "cockpit://forest"))
        }
        .configurationDisplayName("Flow")
        .description("Die Restzeit der Session, sonst die Habits.")
        .supportedFamilies([.systemMedium])
    }
}
