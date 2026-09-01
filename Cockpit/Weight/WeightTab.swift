import SwiftUI

/// Gewicht - nativ seit M1. Die Weboberflaeche stapelt vier Diagramme
/// untereinander; hier ist es eines mit Umschalter, weil vier Diagramme auf
/// einem Handy vor allem Scrollweg bedeuten.
struct WeightTab: View {

    @State private var store = WeightStore()
    @State private var showingEntry = false
    @State private var showingTarget = false

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
                    } else if store.isLoading {
                        LoadingPlaceholder()
                    }
                }
                .padding(16)
            }
            .navigationTitle("Gewicht")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Ziel anpassen …") { showingTarget = true }
                        if !store.addableWidgets.isEmpty {
                            Menu("Kachel hinzufügen") {
                                ForEach(store.addableWidgets) { widget in
                                    Button(widget.label) {
                                        Task { await store.addWidget(widget) }
                                    }
                                }
                            }
                        }
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
            .refreshable { await store.load() }
            .task { await store.load() }
            .sheet(isPresented: $showingEntry) { WeightEntrySheet(store: store) }
            .sheet(isPresented: $showingTarget) { WeightTargetSheet(store: store) }
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
                .contextMenu {
                    // Die vier Basis-Kacheln lassen sich nicht entfernen -
                    // dann steht dort auch kein Menuepunkt.
                    if !WeightWidget.base.contains(widget) {
                        Button("Entfernen", role: .destructive) {
                            Task { await store.removeWidget(widget) }
                        }
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
                            visible: store.visibleSeries)

            // Die Umschalter sind zugleich die Legende - eine zweite Liste
            // mit denselben Farben waere Wiederholung.
            HStack(spacing: 8) {
                ForEach(WeightSeries.offered) { series in
                    if store.range.availableSeries.contains(series) {
                        let isOn = store.visibleSeries.contains(series)
                        Button {
                            if isOn { store.visibleSeries.remove(series) }
                            else { store.visibleSeries.insert(series) }
                        } label: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(series.color)
                                    .frame(width: 8, height: 8)
                                Text(series.title).font(.caption)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(isOn ? series.color.opacity(0.18) : Color.clear,
                                        in: Capsule())
                            .overlay(Capsule().strokeBorder(.quaternary, lineWidth: isOn ? 0 : 1))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isOn ? .primary : .secondary)
                    }
                }
            }
        }
    }
}
