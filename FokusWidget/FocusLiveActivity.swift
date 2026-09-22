import ActivityKit
import SwiftUI
import WidgetKit

/// Die laufende Fokus-Session als Live-Aktivitaet. Der Sperrbildschirm
/// bekommt den grossen Baum ohne Hintergrund, die Dynamic Island den
/// Countdown.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            FocusActivityView(start: context.attributes.start,
                              end: context.attributes.end,
                              test: context.attributes.test,
                              stale: context.isStale)
                // Durchsichtig statt Milchglas: das Hintergrundbild bleibt.
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 12) {
                        Image(systemName: "tree.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.green)
                        Text(timerInterval: context.attributes.start...context.attributes.end,
                             countsDown: true)
                            .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                            .frame(width: 120, alignment: .leading)
                    }
                }
            } compactLeading: {
                Image(systemName: "tree.fill")
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text(timerInterval: context.attributes.start...context.attributes.end, countsDown: true)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "tree.fill")
                    .foregroundStyle(.green)
            }
        }
    }
}
