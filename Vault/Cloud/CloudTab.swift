import SwiftUI

/// Die Cloud-Kosten des Monats - dieselben Zahlen wie in der Menüleisten-App.
///
/// Erst AWS, wie seit 01.11.: oben Betrag, Prozent am Budget, Balken, darunter die
/// vier Kategorien mit ihren Posten, was gerade läuft, und die Vormonate. Dann
/// Verda (seit 02.11.) in Euro, mit eigenem Budget - ohne gemeinsame Summe (Felix).
struct CloudTab: View {

    /// Welches Budget der Dialog gerade ändert.
    enum BudgetKind: Hashable {
        /// Dollar, das echte AWS-Budget.
        case aws
        /// Euro, das Budget des Dienstes für Verda.
        case verda
    }


    @Environment(Access.self) private var access
    let lock: BiometricLock

    @State private var store = CloudStore()
    @State private var editingBudget: BudgetKind?
    @State private var budgetText = ""
    @State private var expanded: Set<String> = []

    private var setup: SetupPresenter { SetupPresenter.shared }

    var body: some View {
        NavigationStack {
            Group {
                if lock.isUnlocked {
                    content
                } else {
                    LockScreen(title: "Cloud ist gesperrt", failure: lock.lastFailure) {
                        await unlockAndLoad()
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { OfflineBanner(backend: .cloud) }
            .navigationTitle(Backend.cloud.title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { AccessButton() }
            }
        }
        .task { await unlockAndLoad() }
        .alert("Budget", isPresented: Binding(
            get: { editingBudget != nil },
            set: { if !$0 { editingBudget = nil } }), presenting: editingBudget) { kind in
            TextField(kind == .aws ? "Dollar" : "Euro", text: $budgetText)
                .keyboardType(.decimalPad)
            Button("Speichern") {
                guard let limit = CloudUsageFormat.parseLimit(budgetText) else { return }
                switch kind {
                case .aws: Task { await store.setBudget(limit, access: access) }
                case .verda: Task { await store.setVerdaBudget(limit, access: access) }
                }
            }
            .disabled(CloudUsageFormat.parseLimit(budgetText) == nil)
            Button("Abbrechen", role: .cancel) {}
        } message: { kind in
            switch kind {
            case .aws: if let name = store.usage?.budget?.name { Text(name) }
            case .verda: Text("Verda")
            }
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
                if let verda = usage.verda {
                    verdaMonth(verda)
                    verdaRunning(verda)
                    verdaVolumes(verda)
                    verdaBuckets(verda)
                    verdaMonths(verda)
                }
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
        Section("AWS") {
            VStack(alignment: .leading, spacing: 10) {
                Text(CloudUsageFormat.monthTitle(usage.month))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(CloudUsageFormat.dollars(usage.spent))
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                    if let limit = usage.budget?.limit {
                        Text("von \(CloudUsageFormat.limit(limit))")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(CloudUsageFormat.percent(usage.percent))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(CloudUsagePalette.percentColor(usage.percent))
                }
                AWSBudgetBar(usage: usage)
            }
            .padding(.vertical, 4)
            if let problem = usage.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            LabeledContent("Abgerechnet", value: CloudUsageFormat.dollars(usage.billed))
                .monospacedDigit()
            LabeledContent("Live", value: CloudUsageFormat.dollars(usage.live))
                .monospacedDigit()
            LabeledContent("Prognose", value: usage.forecast.map(CloudUsageFormat.dollars) ?? "–")
                .monospacedDigit()
            Button {
                budgetText = usage.budget.map { CloudUsageFormat.limitInput($0.limit) } ?? ""
                editingBudget = .aws
            } label: {
                HStack {
                    Text("Budget")
                        .foregroundStyle(.primary)
                    Spacer()
                    if store.isSaving {
                        ProgressView()
                    } else {
                        Text(usage.budget.map { CloudUsageFormat.limit($0.limit) } ?? "–")
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
                            Text(CloudUsageFormat.dollars(item.amount))
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
                                Text("+\(CloudUsageFormat.dollars(category.live)) live")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Text(CloudUsageFormat.dollars(category.amount))
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
                            Text("≈ \(CloudUsageFormat.dollars(instance.estimate))")
                                .monospacedDigit()
                        }
                        HStack(spacing: 4) {
                            Text(instance.type)
                            Text("·")
                            // On-Demand kostet beim LLM das Dreifache von Spot - das
                            // soll man auch hier sofort sehen, wie im Banner von `llm`.
                            Text(CloudUsageFormat.lifecycle(instance))
                                .foregroundStyle(instance.isSpot ? Color.secondary : Color.orange)
                            Text("·")
                            Text(CloudUsageFormat.perHour(instance.pricePerHour))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        Text("seit \(CloudUsageFormat.time(instance.launchedAt)) · \(CloudUsageFormat.runtime(from: instance.launchedAt))")
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
                            Text(CloudUsageFormat.monthTitle(month.month))
                            Spacer()
                            Text(CloudUsageFormat.dollars(month.total))
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                        AWSMonthBar(month: month, scale: usage.monthScale)
                        HStack(spacing: 0) {
                            ForEach(month.parts, id: \.key) { part in
                                HStack(spacing: 4) {
                                    AWSCategoryDot(key: part.key, size: 6)
                                    Text(CloudUsageFormat.dollars(part.amount))
                                        .monospacedDigit()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(AWSCategoryKey.name(for: part.key)) \(CloudUsageFormat.dollars(part.amount))")
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
            LabeledContent("Cost Explorer", value: usage.billedAt.map { CloudUsageFormat.time($0) } ?? "–")
            LabeledContent("Instanzen", value: usage.liveAt.map { CloudUsageFormat.time($0) } ?? "–")
            if let verda = usage.verda {
                LabeledContent("Verda", value: verda.checkedAt.map { CloudUsageFormat.time($0) } ?? "–")
                LabeledContent("Verda gemessen seit",
                               value: verda.trackingSince.map { CloudUsageFormat.time($0) } ?? "–")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Verda

extension CloudTab {

    private func verdaMonth(_ verda: VerdaUsage) -> some View {
        Section("Verda") {
            VStack(alignment: .leading, spacing: 10) {
                Text(CloudUsageFormat.monthTitle(verda.month))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(CloudUsageFormat.euros(verda.spent))
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                    if let limit = verda.budget?.limit {
                        Text("von \(CloudUsageFormat.euroLimit(limit))")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(CloudUsageFormat.percent(verda.percent))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(CloudUsagePalette.percentColor(verda.percent))
                }
                VerdaBudgetBar(verda: verda)
            }
            .padding(.vertical, 4)
            if let problem = verda.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            LabeledContent("Guthaben", value: CloudUsageFormat.euros(verda.balance))
                .monospacedDigit()
            LabeledContent("Aufladungen", value: CloudUsageFormat.euros(verda.topUps))
                .monospacedDigit()
            Button {
                budgetText = verda.budget.map { CloudUsageFormat.limitInput($0.limit) } ?? ""
                editingBudget = .verda
            } label: {
                HStack {
                    Text("Budget")
                        .foregroundStyle(.primary)
                    Spacer()
                    if store.isSavingVerda {
                        ProgressView()
                    } else {
                        Text(verda.budget.map { CloudUsageFormat.euroLimit($0.limit) } ?? "–")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Image(systemName: "pencil")
                        .foregroundStyle(.tint)
                }
            }
            .disabled(store.isSavingVerda)
        }
    }

    @ViewBuilder
    private func verdaRunning(_ verda: VerdaUsage) -> some View {
        if !verda.running.isEmpty {
            Section("Verda · Läuft") {
                ForEach(verda.running) { instance in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(CloudUsagePalette.verda)
                                .frame(width: 8, height: 8)
                            Text(instance.name)
                                .fontWeight(.medium)
                            Spacer()
                            Text("≈ \(CloudUsageFormat.euros(instance.estimate))")
                                .monospacedDigit()
                        }
                        HStack(spacing: 4) {
                            Text(instance.type)
                            Text("·")
                            Text(instance.location)
                            Text("·")
                            LifecycleBadge(isSpot: instance.isSpot)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text(verdaDetail(instance))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    /// „9,87 €/h · seit 18:00 · 1:05 h · ready“ - Preis, dazu was sonst bekannt ist.
    /// Eine eigene Zeile: mit Typ und Ort zusammen würde die On-Demand-Marke gekürzt.
    private func verdaDetail(_ instance: VerdaInstance) -> String {
        var parts = [CloudUsageFormat.euroPerHour(instance.pricePerHour)]
        if let launched = instance.launchedAt {
            parts.append("seit \(CloudUsageFormat.time(launched))")
            parts.append(CloudUsageFormat.runtime(from: launched))
        }
        if let phase = instance.phase { parts.append(phase) }
        return parts.joined(separator: " · ")
    }

    /// Nur, wenn es welche gibt - dann als Warnung: sie kosten, ohne dass etwas läuft.
    @ViewBuilder
    private func verdaVolumes(_ verda: VerdaUsage) -> some View {
        if !verda.volumes.isEmpty {
            Section {
                ForEach(verda.volumes) { volume in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(volume.name)
                                .fontWeight(.medium)
                            Text(volume.status)
                                .font(.caption)
                        }
                        Spacer()
                        Text(CloudUsageFormat.gigabytes(volume.sizeGb))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.orange)
                    .listRowBackground(Color.orange.opacity(0.12))
                }
            } header: {
                Label("Verda · Vergessene Volumes", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func verdaBuckets(_ verda: VerdaUsage) -> some View {
        if !verda.buckets.isEmpty {
            Section("Verda · Buckets") {
                ForEach(verda.buckets) { bucket in
                    LabeledContent(bucket.name, value: CloudUsageFormat.gigabytes(bucket.sizeGb))
                        .monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private func verdaMonths(_ verda: VerdaUsage) -> some View {
        if !verda.months.isEmpty {
            Section("Verda · Vormonate") {
                ForEach(verda.months) { month in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(CloudUsageFormat.monthTitle(month.month))
                            Spacer()
                            Text(CloudUsageFormat.euros(month.spent))
                                .fontWeight(.medium)
                                .monospacedDigit()
                        }
                        VerdaMonthBar(month: month, scale: verda.monthScale)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
