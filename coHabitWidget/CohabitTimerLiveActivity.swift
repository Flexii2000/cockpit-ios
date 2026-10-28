import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Der laufende Timer als Live-Aktivitaet (Vertrag §5.2d): auf dem
/// Sperrbildschirm wie die Karte in „Heute" - Flaeche in der Typfarbe, Name,
/// grosse Zeit und rechts der Stopp -, in der Dynamic Island nur die Zeit.
struct CohabitTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CohabitTimerAttributes.self) { context in
            CohabitTimerLockView(attributes: context.attributes, startedAt: context.state.startedAt)
                .activityBackgroundTint(colors(context.attributes).surface)
                .activitySystemActionForegroundColor(Ink.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.name)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StopButton(cohabitId: context.attributes.cohabitId, size: 44,
                               fill: colors(context.attributes).accent)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    elapsed(context.state.startedAt)
                        .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 6)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(colors(context.attributes).accent)
            } compactTrailing: {
                elapsed(context.state.startedAt)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .frame(width: 48)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(colors(context.attributes).accent)
            }
        }
    }

    private func colors(_ attributes: CohabitTimerAttributes) -> PaletteColor {
        (PaletteKey(rawValue: attributes.color) ?? .peach).colors
    }
}

/// Hochzaehlend ab dem Start, ohne Ende - „12:34", ab einer Stunde „1:02:05".
private func elapsed(_ startedAt: Date) -> Text {
    Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
}

struct CohabitTimerLockView: View {
    let attributes: CohabitTimerAttributes
    let startedAt: Date

    private var colors: PaletteColor { (PaletteKey(rawValue: attributes.color) ?? .peach).colors }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(attributes.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(colors.onSurface)
                    .lineLimit(1)
                elapsed(startedAt)
                    .font(.system(size: 44, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(Ink.ink)
            }
            Spacer(minLength: 8)
            StopButton(cohabitId: attributes.cohabitId, size: 56, fill: colors.accent)
        }
        .padding(18)
    }
}

/// Der Stopp wie in der App: rund, in der Typfarbe gefuellt.
private struct StopButton: View {
    let cohabitId: String
    let size: CGFloat
    let fill: Color

    var body: some View {
        Button(intent: StopCohabitTimerIntent(cohabitId: cohabitId)) {
            Image(systemName: "stop.fill")
                .font(.system(size: size * 0.36, weight: .heavy))
                .foregroundStyle(Ink.ink)
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Timer stoppen")
    }
}
