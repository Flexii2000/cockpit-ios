import SwiftUI

/// Gewicht - nativ seit M1. Die Weboberflaeche stapelt vier Diagramme
/// untereinander; hier ist es eines mit Umschalter, weil vier Diagramme auf
/// einem Handy vor allem Scrollweg bedeuten.
struct WeightTab: View {

    @State private var store = WeightStore()
    @State private var showingEntry = false
    @State private var showingTarget = false
    @State private var showingStepsGoal = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = store.error {
                        ErrorBanner(message: error, isAccessProblem: store.accessProblem)
                    }

                    if let summary = store.summary {
                        tiles(summary)
                        chart
                        StepsCard(steps: store.stepsToday, goal: store.stepsGoal)
                    } else if store.isLoading {
                        LoadingPlaceholder()
                    }
                }
                .padding(16)
                // Platz fuer die schwebende Tab-Leiste. Ohne den endet der
                // Inhalt genau hinter ihr: das letzte Element - die
                // Schritte-Karte - steht angeschnitten da, und es gibt nichts
                // mehr zu scrollen, was es hervorholen koennte. Vom UI-Test
                // gefunden, nachdem drei Wischversuche wirkungslos blieben.
                .padding(.bottom, 60)
            }
            .safeAreaInset(edge: .top, spacing: 0) { OfflineBanner(backend: .weight) }
            .onChange(of: OfflineStatus.shared.pending) { before, after in
                if before > 0, after == 0 { Task { await store.load() } }
            }
            .navigationTitle("Gewicht")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Ziel anpassen …") { showingTarget = true }
                        Button("Schrittziel …") { showingStepsGoal = true }
                        if HealthSync.shared.isAvailable {
                            Button("Aus Health holen") {
                                Task {
                                    await HealthSync.shared.requestPermission()
                                    await HealthSync.shared.syncNow()
                                    await store.load()
                                }
                            }
                        }
                        if !store.addableWidgets.isEmpty {
                            Menu("Kachel hinzufügen") {
                                ForEach(store.addableWidgets) { widget in
                                    Button(widget.label) {
                                        Task { await store.addWidget(widget) }
                                    }
                                }
                            }
                        }
                        Divider()
                        Button("Zugang …") { SetupPresenter.shared.isPresented = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await HealthSync.shared.syncNow()
                await HealthSync.shared.syncSteps()
                await store.load()
            }
            .task {
                // Erlaubnis im Zusammenhang erfragen, nicht beim ersten Start
                // der App: hier ist erkennbar, wofuer sie gebraucht wird. iOS
                // zeigt seine Nachfrage ohnehin nur einmal.
                await HealthSync.shared.requestPermission()
                await HealthSync.shared.syncNow()
                await HealthSync.shared.syncSteps()
                await store.load()
            }
            .sheet(isPresented: $showingEntry) { WeightEntrySheet(store: store) }
            .sheet(isPresented: $showingTarget) { WeightTargetSheet(store: store) }
            .sheet(isPresented: $showingStepsGoal) { StepsGoalSheet(store: store) }
        }
    }

    private func tiles(_ summary: WeightSummary) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(store.widgets) { widget in
                VStack(alignment: .leading, spacing: 4) {
                    Text(widget.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(widget.value(summary))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(widget.tone(summary)?.color ?? .primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                // Jede Kachel laesst sich entfernen, auch die vier frueher
                // festen - und auch alle auf einmal. Hinzufuegen geht ueber
                // das Menue oben, das immer da ist.
                .contextMenu {
                    Button("Entfernen", role: .destructive) {
                        Task { await store.removeWidget(widget) }
                    }
                }
            }
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Zeitraum", selection: Binding(
                get: { store.range },
                set: { range in Task { await store.select(range) } })) {
                ForEach(WeightRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)

            WeightChartView(points: store.points,
                            vacations: store.vacations,
                            corridor: store.summary?.activeCorridor,
                            kcalByDay: store.kcalByDay,
                            kcalTarget: store.kcalTarget,
                            visible: store.visibleSeries)

            // Die Umschalter sind zugleich die Legende - eine zweite Liste
            // mit denselben Farben waere Wiederholung.
            HStack(spacing: 8) {
                ForEach(WeightSeries.offered) { series in
                    if store.range.availableSeries.contains(series) {
                        SeriesChip(title: series.title,
                                   color: series.color,
                                   isOn: store.visibleSeries.contains(series)) {
                            if store.visibleSeries.contains(series) {
                                store.visibleSeries.remove(series)
                            } else {
                                store.visibleSeries.insert(series)
                            }
                        }
                    }
                }
            }
        }
    }
}
