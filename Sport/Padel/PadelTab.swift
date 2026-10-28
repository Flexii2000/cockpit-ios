import SwiftUI

/// Padel - die Autobuchung bei Playtomic (fherrmann.com/padel), nativ (Felix, 23.10.): was die
/// Seite zeigt, in derselben Reihenfolge - der naechste Termin, Kosten, Gebucht, Ergebnisse von der Uhr,
/// Geplant (ein Eintrag je Tag und Mitspieler), Serien, Plaetze und Stand. Eintraege sind in
/// der Farbe des Mitspielers hinterlegt, wo der Dienst eine mitschickt.
struct PadelTab: View {

    @State private var store = PadelStore()
    @State private var confirmation: PadelConfirmation?
    @State private var moving: PadelOccurrence?
    @State private var addingSeries = false
    @State private var addingOneOff = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Group {
                if let overview = store.overview {
                    content(overview)
                } else if store.isLoading {
                    LoadingPlaceholder()
                } else if let error = store.error {
                    VStack(spacing: 16) {
                        ErrorBanner(message: error, isAccessProblem: store.accessProblem)
                        Button("Erneut versuchen") { Task { await store.load() } }
                    }
                    .padding()
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    LoadingPlaceholder()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { OfflineBanner(backend: .padel) }
            .navigationTitle("Padel")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AccessButton() }
                if store.isOwner {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Serie …", systemImage: "repeat") { addingSeries = true }
                            Button("Einmalig …", systemImage: "calendar.badge.plus") { addingOneOff = true }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityIdentifier("padelAdd")
                    }
                }
            }
            .refreshable { await store.load() }
            .sheet(isPresented: $addingSeries) { PadelSeriesSheet(store: store) }
            .sheet(isPresented: $addingOneOff) { PadelOneOffSheet(store: store) }
            .sheet(item: $moving) { PadelMoveSheet(occurrence: $0, store: store) }
            .confirmationDialog(confirmation?.title ?? "", isPresented: Binding(
                get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
                                titleVisibility: .visible, presenting: confirmation) { pending in
                Button(pending.button, role: .destructive) { Task { await pending.action() } }
            }
        }
        .task { await store.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.load() } }
        }
    }

    private func ask(_ pending: PadelConfirmation) {
        confirmation = pending
    }

    private func content(_ overview: PadelOverview) -> some View {
        List {
            if let error = store.error {
                Section { ErrorBanner(message: error, isAccessProblem: store.accessProblem) }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            if overview.dryRun && overview.viewer.owner {
                Section { Text("Trockenlauf").font(.footnote.weight(.semibold)).foregroundStyle(.orange) }
            }
            if let next = overview.next {
                Section("Nächster Termin") {
                    PadelNextCard(next: next, occurrences: overview.occurrences, store: store, ask: ask)
                        .padelTint(overview.viewer.owner ? next.partnerColor : nil)
                }
            }
            if overview.viewer.owner {
                Section("Kosten") { costRows() }
            }
            Section("Gebucht") {
                if let message = store.bookingsError, store.bookings == nil {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                } else if let bookings = store.bookings {
                    if bookings.isEmpty {
                        Text("–").foregroundStyle(.secondary)
                    }
                    ForEach(bookings) { PadelBookingRow(booking: $0, store: store, ask: ask) }
                } else {
                    ProgressView()
                }
            }
            if let results = overview.results, !results.isEmpty {
                Section("Ergebnisse") {
                    ForEach(results) { PadelResultRow(result: $0) }
                }
            }
            Section("Geplant") {
                let days = PadelPlan.days(overview.occurrences, now: Date())
                if days.isEmpty {
                    Text("–").foregroundStyle(.secondary)
                }
                ForEach(days) { PadelDayRow(day: $0, store: store, ask: ask, moving: $moving) }
            }
            if overview.viewer.owner, let series = overview.series {
                Section("Serien") {
                    if series.isEmpty {
                        Text("–").foregroundStyle(.secondary)
                    }
                    ForEach(series) { PadelSeriesRow(series: $0, store: store, ask: ask) }
                }
            }
            Section {
                if overview.viewer.owner {
                    NavigationLink("Plätze") { PadelCourtsView(store: store) }
                }
                if let url = URL(string: overview.feedUrl) {
                    Link("Kalender abonnieren", destination: url)
                }
            } footer: {
                if let status = overview.status {
                    statusLine(status)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Dieser Monat, seine Prognose, die des Folgemonats und die Vormonate (28.10.) - wie die Karte
    /// „Kosten“ der Seite.
    @ViewBuilder
    private func costRows() -> some View {
        if let costs = store.costs {
            PadelCostRow(title: costs.label, detail: PadelFormat.matches(costs.matches), amount: costs.spent)
            PadelCostRow(title: "Prognose", detail: PadelFormat.forecastDetail(costs), amount: costs.forecast)
            if let next = costs.next {
                PadelCostRow(title: "Prognose \(next.label)", detail: PadelFormat.forecastDetail(next),
                             amount: next.forecast)
            }
            ForEach(costs.months) {
                PadelCostRow(title: $0.label, detail: PadelFormat.matches($0.matches), amount: $0.amount, past: true)
            }
        } else if let message = store.costsError {
            Text(message).font(.footnote).foregroundStyle(.secondary)
        } else {
            ProgressView()
        }
    }

    /// „Playtomic ✓ · iCloud ✓ · To-Do ✓ · Fenster 336 h · 86 Wecker“
    private func statusLine(_ status: PadelStatus) -> some View {
        let mark = { (ok: Bool, label: String) -> Text in
            Text("\(label) \(ok ? "✓" : "✗")").foregroundStyle(ok ? Color.green : Color.red)
        }
        return (mark(status.playtomicLogin, "Playtomic") + Text(" · ")
            + mark(status.calendar, "iCloud") + Text(" · ")
            + mark(status.todo, "To-Do")
            + Text(" · Fenster \(status.windowHours) h · \(status.armedReleases) Wecker"))
            .font(.footnote)
    }
}
