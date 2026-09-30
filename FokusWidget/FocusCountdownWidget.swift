import SwiftUI
import WidgetKit

struct FocusEntry: TimelineEntry {
    let date: Date
    let state: FocusWidgetState
}

/// Alles kommt aus der App-Gruppe, ohne Netz: die laufende Session und der
/// Stand von heute, den die App nach jedem Laden ablegt.
///
/// Zwei Eintraege je Zeitleiste, solange eine Session laeuft: jetzt (der
/// Countdown) und ihr Ende (der Tagesstand). Dazwischen zaehlt der Countdown
/// von selbst. Die App und die Erweiterung `FokusMonitor` laden die Kachel bei
/// jedem Anfang und Ende neu.
struct FocusProvider: TimelineProvider {

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
                                          state: FocusWidgetState(session: nil, todayMinutes: state.todayMinutes,
                                                                  goal: state.goal))]
                completion(Timeline(entries: entries, policy: .after(session.end.addingTimeInterval(60))))
            } else {
                // Halbstuendlich plus Mitternacht - dann beginnt ein neuer Tag.
                completion(Timeline(entries: [FocusEntry(date: now, state: state)],
                                    policy: .after(RemainingCalories.nextRefresh(after: now))))
            }
        }
    }

    private func current() async -> FocusWidgetState {
        let session = FocusHandoff.loadSession().flatMap { active -> FocusWidgetState.Session? in
            active.isOver() ? nil : FocusWidgetState.Session(start: active.start, end: active.end, test: active.test)
        }
        let today = FocusHandoff.loadToday()
        return FocusWidgetState(session: session, todayMinutes: today.minutes, goal: today.goal)
    }
}

/// Die breite Fokus-Kachel: Countdown der Session, sonst der Stand von heute.
struct FocusCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.focus, provider: FocusProvider()) { entry in
            FocusWidgetView(state: entry.state)
                .containerBackground(.fill.tertiary, for: .widget)
                // Ein Tipp fuehrt in den Wald (RootView.onOpenURL).
                .widgetURL(URL(string: "cockpit://forest"))
        }
        .configurationDisplayName("Fokus")
        .description("Die Restzeit der Session, sonst der Stand von heute.")
        .supportedFamilies([.systemMedium])
    }
}
