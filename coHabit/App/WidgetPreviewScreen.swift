#if DEBUG
import SwiftUI
import WidgetKit

/// Alle Kacheln mit echten Daten - nur mit `COCKPIT_TAB=widget`. `#if DEBUG`
/// allein reicht nicht, auf dem Geraet laeuft ein Debug-Build (CLAUDE.md).
struct WidgetPreviewScreen: View {

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["COCKPIT_TAB"] == "widget"
    }

    @State private var state: CohabitWidgetState?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Kacheln").font(.heading(28)).foregroundStyle(Ink.ink)
                if let state {
                    if let data = state.data {
                        HStack(spacing: 14) {
                            ForEach(Array(data.cohabits.prefix(2))) { item in
                                labelled("Klein") {
                                    SmallCohabitWidgetView(item: item, staleSince: state.staleSince)
                                        .padding(14)
                                        .frame(width: 158, height: 158)
                                        .background(SmallCohabitBackground(color: item.ref.typeColor))
                                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                                }
                            }
                        }
                        labelled("Mittel · Tagesübersicht") {
                            TodayWidgetView(data: data, staleSince: state.staleSince)
                                .padding(14)
                                .frame(width: 338, height: 158)
                                .background(Ink.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        labelled("Groß · Challenge & Ziele") {
                            BoardWidgetView(data: data, staleSince: state.staleSince)
                                .padding(14)
                                .frame(width: 338, height: 354)
                                .background {
                                    ZStack {
                                        data.challenge?.ref.typeColor.colors.surface ?? Ink.surface
                                        if let color = data.challenge?.ref.typeColor {
                                            CornerCircle(color: color.colors.accent.opacity(0.6), corner: .topTrailing, size: 110)
                                        }
                                    }
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        labelled("Sperrbildschirm") {
                            HStack(spacing: 16) {
                                if let item = data.cohabits.first(where: { $0.ref.type == .streak }) ?? data.cohabits.first {
                                    CircularCohabitView(item: item)
                                        .frame(width: 72, height: 72)
                                }
                                if let challenge = data.challenge {
                                    ChallengeRectView(challenge: challenge)
                                        .frame(width: 160, height: 72)
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(16)
                            .background(Color(hex: 0x2B2A3A), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                    } else {
                        WidgetHint(state: state)
                            .frame(width: 158, height: 158)
                            .background(Ink.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                } else {
                    ProgressView()
                }
            }
            .padding(Metrics.gutter)
        }
        .screenBackground()
        .task { state = await WidgetLoader.load() }
    }

    private func labelled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(Ink.muted)
            content()
        }
    }
}
#endif
