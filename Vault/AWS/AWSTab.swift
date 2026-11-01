import SwiftUI

/// Die AWS-Kosten des Monats - dieselben Zahlen wie in der Menüleisten-App.
///
/// Oben, wofür man den Tab aufmacht: Betrag, Prozent am Budget, Balken. Darunter
/// die vier Kategorien mit ihren Posten, was gerade läuft, und die Vormonate.
struct AWSTab: View {

    @Environment(Access.self) private var access
    let lock: BiometricLock

    @State private var store = AWSStore()
    @State private var editingBudget = false
    @State private var budgetText = ""
    @State private var expanded: Set<String> = []

    private var setup: SetupPresenter { SetupPresenter.shared }

    var body: some View {
        NavigationStack {
            Group {
                if lock.isUnlocked {
                    content
                } else {
                    LockScreen(title: "AWS ist gesperrt", failure: lock.lastFailure) {
                        await unlockAndLoad()
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { OfflineBanner(backend: .aws) }
            .navigationTitle("AWS")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AccessButton() }
            }
        }
        .task { await unlockAndLoad() }
        .alert("Budget", isPresented: $editingBudget) {
            TextField("Dollar", text: $budgetText)
                .keyboardType(.decimalPad)
            Button("Speichern") {
                guard let limit = AWSUsageFormat.parseLimit(budgetText) else { return }
                Task { await store.setBudget(limit, access: access) }
            }
            .disabled(AWSUsageFormat.parseLimit(budgetText) == nil)
            Button("Abbrechen", role: .cancel) {}
        } message: {
            if let name = store.usage?.budget?.name { Text(name) }
        }
    }

    private func unlockAndLoad() async {
        await lock.unlock()
        guard lock.isUnlocked else { return }
        await store.load(access: access)
    }

    // MARK: - Inhalt

    @ViewBuilder
    private var content: some View {
        if access.privateToken == nil {
            VStack(spacing: 16) {
                ErrorBanner(message: "Kein fh_private.", isAccessProblem: true)
                Button("Zugang") { setup.isPresented = true }
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)
        } else if let usage = store.usage {
            List {
                if let error = store.error {
                    ErrorBanner(message: error, isAccessProblem: store.isAccessProblem)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                budget(usage)
                categories(usage)
                running(usage)
                months(usage)
                status(usage)
            }
            .refreshable { await store.load(access: access) }
        } else if store.isLoading {
            LoadingPlaceholder()
        } else {
            VStack(spacing: 16) {
                if let error = store.error {
                    ErrorBanner(message: error, isAccessProblem: store.isAccessProblem)
                }
                Button("Erneut versuchen") {
                    Task { await store.load(access: access) }
                }
            }
            .padding()
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Budget

    private func budget(_ usage: AWSUsage) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(AWSUsageFormat.monthTitle(usage.month))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(AWSUsageFormat.dollars(usage.spent))
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                    if let limit = usage.budget?.limit {
                        Text("von \(AWSUsageFormat.limit(limit))")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(AWSUsageFormat.percent(usage.percent))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(AWSUsagePalette.percentColor(usage.percent))
                }
                AWSBudgetBar(usage: usage)
            }
            .padding(.vertical, 4)
            if let problem = usage.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            LabeledContent("Abgerechnet", value: AWSUsageFormat.dollars(usage.billed))
                .monospacedDigit()
            LabeledContent("Live", value: AWSUsageFormat.dollars(usage.live))
                .monospacedDigit()
            LabeledContent("Prognose", value: usage.forecast.map(AWSUsageFormat.dollars) ?? "–")
                .monospacedDigit()
            Button {
                budgetText = usage.budget.map { AWSUsageFormat.limitInput($0.limit) } ?? ""
                editingBudget = true
            } label: {
                HStack {
                    Text("Budget")
                        .foregroundStyle(.primary)
                    Spacer()
                    if store.isSaving {
                        ProgressView()
                    } else {
                        Text(usage.budget.map { AWSUsageFormat.limit($0.limit) } ?? "–")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Image(systemName: "pencil")
                        .foregroundStyle(.tint)
                }
            }
            .disabled(store.isSaving)
        }
    }

    // MARK: - Kategorien

    private func categories(_ usage: AWSUsage) -> some View {
        Section("Kategorien") {
            ForEach(usage.categories) { category in
                DisclosureGroup(isExpanded: binding(for: category.key)) {
                    if category.items.isEmpty {
                        Text("Keine Posten")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(category.items) { item in
                        HStack {
                            Text(item.label)
                                .foregroundStyle(item.live ? .secondary : .primary)
                            Spacer()
                            Text(AWSUsageFormat.dollars(item.amount))
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            AWSCategoryDot(key: category.key)
                            Text(category.name)
                            Spacer()
                            if category.live > 0 {
                                Text("+\(AWSUsageFormat.dollars(category.live)) live")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Text(AWSUsageFormat.dollars(category.amount))
                                .monospacedDigit()
                        }
                        AWSCategoryBar(category: category, scale: usage.categoryScale)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func binding(for key: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(key) },
            set: { open in
                if open { expanded.insert(key) } else { expanded.remove(key) }
            })
    }

    // MARK: - Läuft

    @ViewBuilder
    private func running(_ usage: AWSUsage) -> some View {
        if !usage.running.isEmpty {
            Section("Läuft") {
                ForEach(usage.running) { instance in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            AWSCategoryDot(key: instance.category)
                            Text(instance.name)
                                .fontWeight(.medium)
                            Spacer()
                            Text("≈ \(AWSUsageFormat.dollars(instance.estimate))")
                                .monospacedDigit()
                        }
                        HStack(spacing: 4) {
                            Text(instance.type)
                            Text("·")
                            // On-Demand kostet beim LLM das Dreifache von Spot - das
                            // soll man auch hier sofort sehen, wie im Banner von `llm`.
                            Text(AWSUsageFormat.lifecycle(instance))
                                .foregroundStyle(instance.isSpot ? Color.secondary : Color.orange)
                            Text("·")
                            Text(AWSUsageFormat.perHour(instance.pricePerHour))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        Text("seit \(AWSUsageFormat.time(instance.launchedAt)) · \(AWSUsageFormat.runtime(from: instance.launchedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Vormonate

    @ViewBuilder
    private func months(_ usage: AWSUsage) -> some View {
        if !usage.months.isEmpty {
            Section("Vormonate") {
                ForEach(usage.months) { month in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(AWSUsageFormat.monthTitle(month.month))
                            Spacer()
                            Text(AWSUsageFormat.dollars(month.total))
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                        AWSMonthBar(month: month, scale: usage.monthScale)
                        HStack(spacing: 0) {
                            ForEach(month.parts, id: \.key) { part in
                                HStack(spacing: 4) {
                                    AWSCategoryDot(key: part.key, size: 6)
                                    Text(AWSUsageFormat.dollars(part.amount))
                                        .monospacedDigit()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(AWSCategoryKey.name(for: part.key)) \(AWSUsageFormat.dollars(part.amount))")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Stand

    private func status(_ usage: AWSUsage) -> some View {
        Section {
            LabeledContent("Cost Explorer", value: usage.billedAt.map { AWSUsageFormat.time($0) } ?? "–")
            LabeledContent("Instanzen", value: usage.liveAt.map { AWSUsageFormat.time($0) } ?? "–")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
