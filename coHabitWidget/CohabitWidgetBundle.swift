import SwiftUI
import WidgetKit

/// Die Kacheln von coHabit (Vertrag §5.5): klein und rund fuer ein gewaehltes
/// Co-Habit, mittel fuer heute, gross fuer Challenge und Ziele, rechteckig auf
/// dem Sperrbildschirm fuer den Platz in der Challenge.
@main
struct CohabitWidgetBundle: WidgetBundle {
    var body: some Widget {
        SingleCohabitWidget()
        TodayCohabitWidget()
        BoardCohabitWidget()
        ChallengeCohabitWidget()
    }
}

/// Nicht zeitkritisch: halbstuendlich - eigene Aktionen laden sofort neu.
private func nextRefresh(after date: Date = Date()) -> Date {
    date.addingTimeInterval(30 * 60)
}

// MARK: - Ein Co-Habit (klein, rund)

struct SingleEntry: TimelineEntry {
    let date: Date
    let state: CohabitWidgetState
    let item: WidgetData.Item?

    static let placeholder = SingleEntry(date: Date(), state: .data(.sample, staleSince: nil),
                                         item: WidgetData.sample.cohabits.first)
}

struct SingleProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SingleEntry { .placeholder }

    func snapshot(for configuration: SelectCohabitIntent, in context: Context) async -> SingleEntry {
        context.isPreview ? .placeholder : await entry(for: configuration)
    }

    func timeline(for configuration: SelectCohabitIntent, in context: Context) async -> Timeline<SingleEntry> {
        Timeline(entries: [await entry(for: configuration)], policy: .after(nextRefresh()))
    }

    private func entry(for configuration: SelectCohabitIntent) async -> SingleEntry {
        let state = await WidgetLoader.load()
        let items = state.data?.cohabits ?? []
        // Ohne Auswahl das erste - eine leere Kachel hilft niemandem.
        let item = items.first { $0.ref.id == configuration.cohabit?.id } ?? items.first
        return SingleEntry(date: Date(), state: state, item: item)
    }
}

struct SingleCohabitWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: CohabitWidgetKind.single, intent: SelectCohabitIntent.self,
                               provider: SingleProvider()) { entry in
            SingleFamilyView(entry: entry)
        }
        .configurationDisplayName("Co-Habit")
        .description("Kennzahl und Abhaken.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

private struct SingleFamilyView: View {
    let entry: SingleEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Group {
                if let item = entry.item {
                    CircularCohabitView(item: item)
                } else {
                    Image(systemName: "link")
                }
            }
            .containerBackground(.clear, for: .widget)
            .widgetURL(entry.item.flatMap { URL(string: "cohabit://cohabit/\($0.ref.id)") })
        default:
            Group {
                if let item = entry.item {
                    SmallCohabitWidgetView(item: item, staleSince: entry.state.staleSince)
                } else if entry.state.data != nil {
                    Text("Noch keine Co-Habits")
                        .font(.caption)
                        .foregroundStyle(Ink.muted)
                } else {
                    WidgetHint(state: entry.state)
                }
            }
            .containerBackground(for: .widget) {
                if let item = entry.item {
                    SmallCohabitBackground(color: item.ref.color)
                } else {
                    Ink.surface
                }
            }
            .widgetURL(URL(string: entry.item.map { "cohabit://cohabit/\($0.ref.id)" } ?? "cohabit://today"))
        }
    }
}

// MARK: - Heute, gross, Challenge

struct StateEntry: TimelineEntry {
    let date: Date
    let state: CohabitWidgetState

    static let placeholder = StateEntry(date: Date(), state: .data(.sample, staleSince: nil))
}

struct StateProvider: TimelineProvider {
    func placeholder(in context: Context) -> StateEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (StateEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        Task { completion(StateEntry(date: Date(), state: await WidgetLoader.load())) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<StateEntry>) -> Void) {
        Task {
            let entry = StateEntry(date: Date(), state: await WidgetLoader.load())
            completion(Timeline(entries: [entry], policy: .after(nextRefresh())))
        }
    }
}

struct TodayCohabitWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CohabitWidgetKind.today, provider: StateProvider()) { entry in
            Group {
                if let data = entry.state.data {
                    TodayWidgetView(data: data, staleSince: entry.state.staleSince)
                } else {
                    WidgetHint(state: entry.state)
                }
            }
            .containerBackground(Ink.surface, for: .widget)
            .widgetURL(URL(string: "cohabit://today"))
        }
        .configurationDisplayName("Heute")
        .description("Was heute offen ist.")
        .supportedFamilies([.systemMedium])
    }
}

struct BoardCohabitWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CohabitWidgetKind.board, provider: StateProvider()) { entry in
            Group {
                if let data = entry.state.data {
                    BoardWidgetView(data: data, staleSince: entry.state.staleSince)
                } else {
                    WidgetHint(state: entry.state)
                }
            }
            .containerBackground(for: .widget) {
                ZStack {
                    (entry.state.data?.challenge?.ref.color.colors.surface ?? Ink.surface)
                    if let color = entry.state.data?.challenge?.ref.color {
                        CornerCircle(color: color.colors.accent.opacity(0.6), corner: .topTrailing, size: 110)
                    }
                }
            }
            .widgetURL(URL(string: "cohabit://today"))
        }
        .configurationDisplayName("Challenge & Ziele")
        .description("Rangliste, Teamziel, offener Streak.")
        .supportedFamilies([.systemLarge])
    }
}

struct ChallengeCohabitWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CohabitWidgetKind.challenge, provider: StateProvider()) { entry in
            Group {
                if let challenge = entry.state.data?.challenge {
                    ChallengeRectView(challenge: challenge)
                        .widgetURL(URL(string: "cohabit://cohabit/\(challenge.ref.id)"))
                } else {
                    Text("Keine Challenge")
                        .font(.caption)
                }
            }
            .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Challenge-Platz")
        .description("Dein Platz in der Challenge.")
        .supportedFamilies([.accessoryRectangular])
    }
}
