import SwiftUI

/// Gewohnheiten mit Flamme und Straehne.
///
/// Der Server rechnet, die Zeile zeigt. Vier Arten, vier rechte Raender:
/// Build bekommt einen Haken, Quit einen Rueckfall-Knopf, Track food den
/// kcal-Stand und die Schritte ihr „55/70k".
struct HabitsTab: View {

    @State private var store = HabitsStore()
    @State private var showingEditor = false

    var body: some View {
        NavigationStack {
            Group {
                if store.habits.isEmpty, store.isLoading {
                    LoadingPlaceholder()
                } else {
                    list
                }
            }
            .navigationTitle("Habits")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AccessButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingEditor = true } label: { Image(systemName: "plus") }
                        .accessibilityIdentifier("addHabit")
                }
            }
            .sheet(isPresented: $showingEditor) {
                HabitEditorSheet(store: store)
            }
            .refreshable { await store.load() }
            .task { await store.load() }
        }
    }

    private var list: some View {
        List {
            if let message = store.errorMessage {
                ErrorBanner(message: message, isAccessProblem: store.isAccessProblem)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            ForEach(store.habits) { habit in
                HabitRow(habit: habit) {
                    Task { await store.toggleToday(habit) }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await store.delete(habit) }
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
            if store.habits.isEmpty, !store.isLoading, store.errorMessage == nil {
                Text("Noch keine Habits. Oben rechts eins anlegen.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Eine Gewohnheit als Zeile.
struct HabitRow: View {

    let habit: HabitStatus
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                flame
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name)
                        .font(.body.weight(.medium))
                    subtitle
                }
                Spacer(minLength: 8)
                trailing
            }
            if habit.unavailable == nil {
                RecentDots(recent: habit.recent, unit: habit.unit)
            }
            if habit.kind == .steps, let progress = habit.progress {
                ProgressBar(fraction: progress.fraction, reached: habit.doneToday)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Links: die Flamme

    /// Flamme mit Zahl - wie bei Snapchat. Grau ohne Straehne, blass, wenn
    /// heute noch offen ist: die Straehne lebt, aber sie braucht dich.
    private var flame: some View {
        VStack(spacing: 0) {
            Image(systemName: habit.streak > 0 ? "flame.fill" : "flame")
                .font(.title2)
                .foregroundStyle(flameColor)
            Text("\(habit.streak)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(habit.streak > 0 ? .primary : .secondary)
                .accessibilityIdentifier("streak-\(habit.id)")
        }
        .frame(width: 40)
        .opacity(habit.unavailable == nil ? 1 : 0.3)
    }

    private var flameColor: Color {
        guard habit.streak > 0 else { return .secondary }
        return habit.atRisk ? .orange.opacity(0.45) : .orange
    }

    @ViewBuilder
    private var subtitle: some View {
        if let unavailable = habit.unavailable {
            Text(unavailable)
                .font(.caption)
                .foregroundStyle(.red)
        } else if habit.atRisk {
            Text("\(habit.streakText) · heute noch offen")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            Text(habit.streakText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Rechts: je nach Art

    @ViewBuilder
    private var trailing: some View {
        switch habit.kind {
        case .build:
            Button(action: toggle) {
                Image(systemName: habit.doneToday ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(habit.doneToday ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("toggle-\(habit.id)")
        case .quit:
            if habit.doneToday {
                Button("Rückfall", action: toggle)
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .accessibilityIdentifier("toggle-\(habit.id)")
            } else {
                // Der Rueckfall steht - der Knopf nimmt ihn zurueck, falls
                // er ein Fehlgriff war.
                Button("Doch nicht", action: toggle)
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("toggle-\(habit.id)")
            }
        case .food:
            if let progress = habit.progress {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: habit.doneToday ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(habit.doneToday ? Color.green : Color.secondary)
                    Text(progress.kcalText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        case .steps:
            if let progress = habit.progress {
                Text(progress.stepsText)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(habit.doneToday ? Color.green : Color.primary)
                    .accessibilityIdentifier("steps-\(habit.id)")
            }
        }
    }
}

/// Die letzten sieben Tage oder Wochen als Punkte, aelteste links.
struct RecentDots: View {

    let recent: [Bool]
    let unit: HabitStatus.Unit

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(recent.enumerated()), id: \.offset) { index, done in
                Circle()
                    .fill(done ? Color.orange : Color.primary.opacity(0.12))
                    .frame(width: 8, height: 8)
                    // Der letzte Punkt ist heute bzw. diese Woche - ein Ring
                    // drumherum, damit man weiss, wo man steht.
                    .overlay {
                        if index == recent.count - 1 {
                            Circle().stroke(Color.orange, lineWidth: 1).padding(-2)
                        }
                    }
            }
            Text(unit == .days ? "7 Tage" : "7 Wochen")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
        .padding(.leading, 52)
    }
}

/// Die Leiste unter einem Schritte-Habit - dieselbe Form wie im Gewicht-Tab.
struct ProgressBar: View {

    let fraction: Double
    let reached: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(reached ? Color.green : Color.orange)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 6)
        .padding(.leading, 52)
    }
}

/// Der Weg zum Zugang-Blatt - seit dem sechsten Tab kein eigener Tab mehr.
struct AccessButton: View {
    var body: some View {
        Button {
            Router.shared.showsSetup = true
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Zugang")
    }
}
