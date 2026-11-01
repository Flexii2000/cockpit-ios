import AppKit
import SwiftUI

/// Das Ausklappfenster unter der Wolke - aufgebaut wie die Claude Usage Bar:
/// oben die Prozentzahl mit Balken, darunter die Teile, unten Stand und Knöpfe.
struct PopoverView: View {

    let model: UsageModel

    @State private var editingBudget = false
    @State private var budgetText = ""
    @State private var tokenText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.hasToken == false || model.isAccessProblem {
                tokenEntry
            }
            if let usage = model.usage {
                budget(usage)
                Divider()
                categories(usage)
                if !usage.running.isEmpty {
                    Divider()
                    running(usage)
                }
                Divider()
                budgetRow(usage)
                if let problem = usage.problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Toggle("Beim Anmelden starten", isOn: Binding(
                get: { model.launchesAtLogin },
                set: { model.setLaunchesAtLogin($0) }))
                .toggleStyle(.checkbox)
                .font(.callout)
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            model.readLaunchAtLogin()
            Task { await model.refresh(ifOlderThan: 30) }
        }
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("AWS")
                .font(.headline)
            Spacer()
            if let month = model.usage?.month {
                Text(AWSUsageFormat.monthTitle(month))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tokenEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("fh_private")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                SecureField("Token", text: $tokenText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveToken)
                Button("Speichern", action: saveToken)
                    .disabled(tokenText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func saveToken() {
        let text = tokenText
        tokenText = ""
        Task { await model.saveToken(text) }
    }

    // MARK: - Budget

    private func budget(_ usage: AWSUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(AWSUsageFormat.percent(usage.percent))
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(AWSUsagePalette.percentColor(usage.percent))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(spentLine(usage))
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                    Text("Prognose \(usage.forecast.map(AWSUsageFormat.dollars) ?? "–")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            AWSBudgetBar(usage: usage, height: 10)
            HStack {
                Text("Abgerechnet \(AWSUsageFormat.dollars(usage.billed))")
                Spacer()
                Text("Live \(AWSUsageFormat.dollars(usage.live))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    private func spentLine(_ usage: AWSUsage) -> String {
        guard let limit = usage.budget?.limit else { return AWSUsageFormat.dollars(usage.spent) }
        return "\(AWSUsageFormat.dollars(usage.spent)) von \(AWSUsageFormat.limit(limit))"
    }

    // MARK: - Kategorien

    private func categories(_ usage: AWSUsage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(usage.categories) { category in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        AWSCategoryDot(key: category.key)
                        Text(category.name)
                            .font(.callout)
                        Spacer()
                        if category.live > 0 {
                            Text("+\(AWSUsageFormat.dollars(category.live)) live")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(AWSUsageFormat.dollars(category.amount))
                            .font(.callout)
                    }
                    .monospacedDigit()
                    AWSCategoryBar(category: category, scale: usage.categoryScale)
                }
            }
        }
    }

    // MARK: - Läuft

    private func running(_ usage: AWSUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Läuft")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(usage.running) { instance in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    AWSCategoryDot(key: instance.category)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(instance.name)
                            .font(.callout)
                        HStack(spacing: 3) {
                            Text(instance.type)
                            Text("·")
                            Text(AWSUsageFormat.lifecycle(instance))
                                .foregroundStyle(instance.isSpot ? Color.secondary : Color.orange)
                            Text("·")
                            Text(AWSUsageFormat.perHour(instance.pricePerHour))
                            Text("·")
                            Text(AWSUsageFormat.runtime(from: instance.launchedAt))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("≈ \(AWSUsageFormat.dollars(instance.estimate))")
                        .font(.callout)
                }
                .monospacedDigit()
            }
        }
    }

    // MARK: - Budget ändern

    @ViewBuilder
    private func budgetRow(_ usage: AWSUsage) -> some View {
        if editingBudget {
            HStack(spacing: 6) {
                Text("Budget")
                    .font(.callout)
                TextField("Dollar", text: $budgetText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onSubmit(saveBudget)
                Text("$")
                Spacer()
                Button("Abbrechen") { editingBudget = false }
                Button("Speichern", action: saveBudget)
                    .keyboardShortcut(.defaultAction)
                    .disabled(AWSUsageFormat.parseLimit(budgetText) == nil || model.isSaving)
            }
        } else {
            HStack(spacing: 6) {
                Text("Budget")
                    .font(.callout)
                Spacer()
                if model.isSaving {
                    ProgressView().controlSize(.small)
                }
                Text(usage.budget.map { AWSUsageFormat.limit($0.limit) } ?? "–")
                    .font(.callout)
                    .monospacedDigit()
                Button {
                    budgetText = usage.budget.map { AWSUsageFormat.limitInput($0.limit) } ?? ""
                    editingBudget = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Budget ändern")
            }
        }
    }

    private func saveBudget() {
        guard let limit = AWSUsageFormat.parseLimit(budgetText) else { return }
        editingBudget = false
        Task { await model.setBudget(limit) }
    }

    // MARK: - Fuß

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let usage = model.usage {
                Text(statusLine(usage))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack {
                Button("Aktualisieren") {
                    Task { await model.refresh() }
                }
                .disabled(model.isLoading)
                Spacer()
                Button("Beenden") { NSApplication.shared.terminate(nil) }
            }
        }
    }

    private func statusLine(_ usage: AWSUsage) -> String {
        let billed = usage.billedAt.map { AWSUsageFormat.time($0) } ?? "–"
        let live = usage.liveAt.map { AWSUsageFormat.time($0) } ?? "–"
        return "Cost Explorer \(billed) · Instanzen \(live)"
    }
}
