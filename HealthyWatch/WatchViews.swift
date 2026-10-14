import SwiftUI

/// Ohne Training: der Tagesstand wie auf der Komplikation.
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
            if ProcessInfo.processInfo.environment["COCKPIT_WATCH_DEMO"] == "workout" {
                WorkoutManager.shared.showDemo()
                return
            }
            if ProcessInfo.processInfo.environment["COCKPIT_WATCH_DEMO"] == "kcal" {
                snapshot = ComplicationSnapshot(date: Self.todayISO, consumedKcal: 1550, targetKcal: 2300,
                                                fetchedAt: Date())
                return
            }
            #endif
            await WorkoutManager.shared.requestAuthorization()
            snapshot = ComplicationStore.snapshot()
        }
    }

    private var isToday: Bool { snapshot?.date == Self.todayISO }

    private static var todayISO: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", parts.year ?? 2026, parts.month ?? 1, parts.day ?? 1)
    }
}

/// Das laufende Training: oben die Werte, darunter das Geraet mit „Satz
/// erledigt“, ganz unten „Beenden“ - als Seiten zum Drehen der Krone.
struct WatchWorkoutView: View {

    private var workout: WorkoutManager { WorkoutManager.shared }

    var body: some View {
        TabView {
            metrics
            machine
            finish
        }
        .tabViewStyle(.verticalPage)
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Self.duration(since: workout.startDate ?? context.date, now: context.date))
                    .font(.system(.title, design: .rounded).monospacedDigit().weight(.semibold))
                    .foregroundStyle(.yellow)
            }
            Label(workout.heartRate.map { "\(Int($0.rounded())) bpm" } ?? "– bpm", systemImage: "heart.fill")
                .foregroundStyle(.red)
            Label(workout.activeKcal.map { "\(Int($0.rounded())) kcal" } ?? "– kcal", systemImage: "flame.fill")
                .foregroundStyle(.orange)
        }
        .font(.title3.monospacedDigit())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var machine: some View {
        if let current = workout.current {
            VStack(spacing: 6) {
                Text(current.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text("Satz \(current.set) von \(current.sets)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("\(current.reps) × " + GymFormat.weight(current.weightKg))
                    .font(.title3.monospacedDigit().weight(.semibold))
                Button {
                    workout.setDone()
                } label: {
                    Label("Satz erledigt", systemImage: "checkmark")
                }
                .tint(.green)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: workout.everythingDone ? "checkmark.circle.fill" : "iphone")
                    .font(.largeTitle)
                    .foregroundStyle(workout.everythingDone ? .green : .secondary)
            }
        }
    }

    private var finish: some View {
        Button(role: .destructive) {
            Task { await workout.end() }
        } label: {
            Label("Beenden", systemImage: "xmark")
        }
    }

    static func duration(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
