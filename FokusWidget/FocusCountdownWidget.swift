import SwiftUI
import WidgetKit

struct FocusEntry: TimelineEntry {
    let date: Date
    let state: FocusWidgetState
}

/// Liest die laufende Session und den Tagesstand aus der App-Gruppe - kein
/// Netz, kein Token: was die Kachel zeigt, hat die App dort abgelegt.
///
/// Zwei Eintraege je Zeitleiste: jetzt (die Session laeuft) und ihr Ende
/// (der Stand von heute, den Baum schon mitgezaehlt). Dazwischen zaehlt der
/// Countdown von selbst. Die App und die Erweiterung `FokusMonitor` laden die
/// Kachel bei jedem Anfang und Ende neu.
struct FocusProvider: TimelineProvider {

    func placeholder(in context: Context) -> FocusEntry {
        FocusEntry(date: Date(), state: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (FocusEntry) -> Void) {
        completion(FocusEntry(date: Date(), state: context.isPreview ? .placeholder : current()))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<FocusEntry>) -> Void) {
        let now = Date()
        let state = current()
        var entries = [FocusEntry(date: now, state: state)]
        if let session = state.session, session.end > now {
            let minutes = session.test ? 0 : Int(session.end.timeIntervalSince(session.start) / 60)
            entries.append(FocusEntry(date: session.end,
                                      state: FocusWidgetState(session: nil,
                                                              todayMinutes: state.todayMinutes + minutes,
                                                              goal: state.goal)))
            completion(Timeline(entries: entries, policy: .after(session.end.addingTimeInterval(60))))
        } else {
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
        }
    }

    private func current() -> FocusWidgetState {
        let session = FocusHandoff.loadSession().flatMap { active -> FocusWidgetState.Session? in
            active.isOver() ? nil : FocusWidgetState.Session(start: active.start, end: active.end, test: active.test)
        }
        let today = FocusHandoff.loadToday()
        return FocusWidgetState(session: session, todayMinutes: today.minutes, goal: today.goal)
    }
}

/// Der Countdown der Fokus-Session auf dem Homebildschirm, breit.
struct FocusCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.focus, provider: FocusProvider()) { entry in
            FocusWidgetView(state: entry.state)
                .containerBackground(.fill.tertiary, for: .widget)
                // Ein Tipp fuehrt in den Wald (RootView.onOpenURL, Host "forest").
                .widgetURL(URL(string: "cockpit://forest"))
        }
        .configurationDisplayName("Fokus")
        .description("Die Restzeit der laufenden Session.")
        .supportedFamilies([.systemMedium])
    }
}
