import AppKit
import SwiftUI

/// Das Ausklappfenster unter der Wolke - aufgebaut wie die Claude Usage Bar:
/// oben die Prozentzahl mit Balken, darunter die Teile, unten Stand und Knöpfe.
/// Zwei Abschnitte untereinander: AWS (Dollar), darunter Verda (Euro, seit 02.11.) -
/// ohne gemeinsame Summe, die Währungen bleiben getrennt (Felix).
struct PopoverView: View {

    let model: UsageModel
    /// `false` nur fuer `Snapshot`: `ImageRenderer` zeichnet keine ScrollView (AppKit).
    var scrolls = true

    @State private var tokenText = ""
    /// Hoehe der Abschnitte ueber dem Fuss, gemessen - danach richtet sich die ScrollView.
    @State private var sectionsHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if scrolls {
                // Mit Verda ist das Fenster hoeher als ein Laptop-Bildschirm (02.11.:
                // gut 1.000 pt) - ohne Scrollen laegen Fuss und Verda-Budget unter
                // der Bildschirmkante. Passt alles, scrollt nichts.
                ScrollView(.vertical) {
                    sections
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sectionsHeight = $0 }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: sectionsHeight > 0 ? min(sectionsHeight, maxSectionsHeight) : nil)
            } else {
                sections
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

    /// Bildschirm unter der Menueleiste, abzueglich Fuss (Schalter, Stand, Knoepfe)
    /// und Rand - so bleiben die Knoepfe immer erreichbar.
    private var maxSectionsHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return max(320, screen - 220)
    }

    /// Alles ueber dem Fuss: AWS, darunter Verda.
    private var sections: some View {
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
                if let spot = usage.spot, !spot.types.isEmpty || spot.problem != nil {
                    Divider()
                    spotSection(spot)
                }
                Divider()
                BudgetRow(value: usage.budget?.limit, unit: "$", placeholder: "Dollar",
                          isSaving: model.isSaving) { limit in
                    Task { await model.setBudget(limit) }
                }
                if let problem = usage.problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let verda = usage.verda {
                    Divider()
                    VerdaSection(verda: verda, model: model)
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
        }
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("AWS")
                .font(.headline)
            Spacer()
            if let month = model.usage?.month {
                Text(CloudUsageFormat.monthTitle(month))
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
                Text(CloudUsageFormat.percent(usage.percent))
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(CloudUsagePalette.percentColor(usage.percent))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(spentLine(usage))
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                    Text("Prognose \(usage.forecast.map(CloudUsageFormat.dollars) ?? "–")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            AWSBudgetBar(usage: usage, height: 10)
            HStack {
                Text("Abgerechnet \(CloudUsageFormat.dollars(usage.billed))")
                Spacer()
                Text("Live \(CloudUsageFormat.dollars(usage.live))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    private func spentLine(_ usage: AWSUsage) -> String {
        guard let limit = usage.budget?.limit else { return CloudUsageFormat.dollars(usage.spent) }
        return "\(CloudUsageFormat.dollars(usage.spent)) von \(CloudUsageFormat.limit(limit))"
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
                            Text("+\(CloudUsageFormat.dollars(category.live)) live")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(CloudUsageFormat.dollars(category.amount))
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
                            Text(CloudUsageFormat.lifecycle(instance))
                                .foregroundStyle(instance.isSpot ? Color.secondary : Color.orange)
                            Text("·")
                            Text(CloudUsageFormat.perHour(instance.pricePerHour))
                            Text("·")
                            Text(CloudUsageFormat.runtime(from: instance.launchedAt))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("≈ \(CloudUsageFormat.dollars(instance.estimate))")
                        .font(.callout)
                }
                .monospacedDigit()
            }
        }
    }

    // MARK: - Spot

    /// Wie viele Spot-Instanzen fürs LLM zu haben wären. Typen, für die die
    /// Spot-Quota nicht reicht, grau - mit dem vCPU-Bedarf daneben (Felix, 02.11.).
    private func spotSection(_ spot: AWSSpot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Spot · \(CloudUsageFormat.regionName(spot.region))")
                Spacer()
                if let quota = spot.quotaVcpus {
                    Text("Quota \(quota) vCPU")
                        .monospacedDigit()
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(spot.types) { type in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(type.type)
                            .font(.callout)
                        if let vcpus = type.vcpus {
                            Text("\(vcpus) vCPU")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(CloudUsageFormat.spotCount(type.estimate, max: spot.maxCount))
                            .font(.callout.weight(.medium))
                            .foregroundStyle(type.estimate > 0 && type.isLaunchable ? Color.green : Color.secondary)
                    }
                    HStack {
                        Text(CloudUsageFormat.spotZones(type.zones))
                        Spacer()
                        Text(CloudUsageFormat.perHour(type.pricePerHour))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .monospacedDigit()
                .opacity(type.isLaunchable ? 1 : 0.4)
            }
            if let problem = spot.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
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
        let billed = usage.billedAt.map { CloudUsageFormat.time($0) } ?? "–"
        let live = usage.liveAt.map { CloudUsageFormat.time($0) } ?? "–"
        var line = "Cost Explorer \(billed) · Instanzen \(live)"
        if let spot = usage.spot {
            line += " · Spot \(spot.checkedAt.map { CloudUsageFormat.time($0) } ?? "–")"
        }
        if let verda = usage.verda {
            line += " · Verda \(verda.checkedAt.map { CloudUsageFormat.time($0) } ?? "–")"
        }
        return line
    }
}

/// Budget ansehen und ändern - für AWS in Dollar (`PUT api/budget`, das echte
/// AWS-Budget), für Verda in Euro (`PUT api/verda/budget`, das des Dienstes).
struct BudgetRow: View {

    /// `nil`, wenn keins gesetzt ist.
    let value: Double?
    let unit: String
    let placeholder: String
    let isSaving: Bool
    let save: (Double) -> Void

    @State private var editing = false
    @State private var text = ""

    var body: some View {
        if editing {
            HStack(spacing: 6) {
                Text("Budget")
                    .font(.callout)
                TextField(placeholder, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .onSubmit(commit)
                Text(unit)
                Spacer()
                Button("Abbrechen") { editing = false }
                Button("Speichern", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(CloudUsageFormat.parseLimit(text) == nil || isSaving)
            }
        } else {
            HStack(spacing: 6) {
                Text("Budget")
                    .font(.callout)
                Spacer()
                if isSaving {
                    ProgressView().controlSize(.small)
                }
                Text(value.map { CloudUsageFormat.limit($0, unit: unit) } ?? "–")
                    .font(.callout)
                    .monospacedDigit()
                Button {
                    text = value.map(CloudUsageFormat.limitInput) ?? ""
                    editing = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Budget ändern")
            }
        }
    }

    private func commit() {
        guard let limit = CloudUsageFormat.parseLimit(text) else { return }
        editing = false
        save(limit)
    }
}
