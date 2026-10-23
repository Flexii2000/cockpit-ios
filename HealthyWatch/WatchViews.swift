import SwiftUI

/// Der Tagesstand wie auf der Komplikation.
struct WatchHomeView: View {

    @State private var snapshot = ComplicationStore.snapshot()

    var body: some View {
        VStack(spacing: 8) {
            KcalGaugeView(consumed: isToday ? snapshot?.consumedKcal : nil, target: snapshot?.targetKcal)
                .scaleEffect(1.6)
                .frame(height: 100)
            Text("Healthy").font(.footnote).foregroundStyle(.secondary)
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["COCKPIT_WATCH_DEMO"] == "kcal" {
                snapshot = ComplicationSnapshot(date: Self.todayISO, consumedKcal: 1550, targetKcal: 2300,
                                                fetchedAt: Date())
                return
            }
            #endif
            snapshot = ComplicationStore.snapshot()
        }
    }

    private var isToday: Bool { snapshot?.date == Self.todayISO }

    private static var todayISO: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", parts.year ?? 2026, parts.month ?? 1, parts.day ?? 1)
    }
}
