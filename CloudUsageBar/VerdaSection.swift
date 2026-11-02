import SwiftUI

/// Der Verda-Abschnitt im Ausklappfenster - aufgebaut wie der von AWS darüber:
/// Prozent am eigenen Budget mit Balken, was läuft, was sonst Geld kostet,
/// Vormonate, Budget. Alles in Euro (Felix, 02.11.).
struct VerdaSection: View {

    let verda: VerdaUsage
    let model: UsageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Verda")
                .font(.headline)
            month
            if !verda.running.isEmpty {
                Divider()
                running
            }
            if !verda.volumes.isEmpty {
                volumes
            }
            if !verda.buckets.isEmpty {
                Divider()
                buckets
            }
            if !verda.months.isEmpty {
                Divider()
                months
            }
            Divider()
            BudgetRow(value: verda.budget?.limit, unit: "€", placeholder: "Euro",
                      isSaving: model.isSavingVerda) { limit in
                Task { await model.setVerdaBudget(limit) }
            }
            if let problem = verda.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Monat

    private var month: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(CloudUsageFormat.percent(verda.percent))
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(CloudUsagePalette.percentColor(verda.percent))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(spentLine)
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                    Text("Guthaben \(CloudUsageFormat.euros(verda.balance))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            VerdaBudgetBar(verda: verda, height: 10)
            HStack {
                Text("Aufladungen \(CloudUsageFormat.euros(verda.topUps))")
                Spacer()
                // Nur im ersten Monat: davor kennt der Dienst keine Ausgaben.
                if verda.startedThisMonth, let since = verda.trackingSince {
                    Text("Messung seit \(CloudUsageFormat.time(since))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }

    private var spentLine: String {
        guard let limit = verda.budget?.limit else { return CloudUsageFormat.euros(verda.spent) }
        return "\(CloudUsageFormat.euros(verda.spent)) von \(CloudUsageFormat.euroLimit(limit))"
    }

    // MARK: - Läuft

    private var running: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Läuft")
            ForEach(verda.running) { instance in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Circle()
                        .fill(CloudUsagePalette.verda)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(instance.name)
                            .font(.callout)
                        HStack(spacing: 3) {
                            Text(instance.type)
                            Text("·")
                            Text(instance.location)
                            Text("·")
                            LifecycleBadge(isSpot: instance.isSpot)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Text(detail(instance))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("≈ \(CloudUsageFormat.euros(instance.estimate))")
                        .font(.callout)
                }
                .monospacedDigit()
            }
        }
    }

    /// „9,87 €/h · 1:05 h · ready“ - Preis, dazu Laufzeit und Phase, soweit bekannt.
    /// Eine eigene Zeile: mit Typ und Ort zusammen würde die On-Demand-Marke gekürzt.
    private func detail(_ instance: VerdaInstance) -> String {
        [CloudUsageFormat.euroPerHour(instance.pricePerHour),
         instance.launchedAt.map { CloudUsageFormat.runtime(from: $0) },
         instance.phase]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    // MARK: - Vergessene Volumes

    /// Nur, wenn es welche gibt - dann als Warnung: sie kosten, ohne dass etwas läuft.
    private var volumes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Vergessene Volumes", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
            ForEach(verda.volumes) { volume in
                HStack(alignment: .firstTextBaseline) {
                    Text(volume.name)
                        .font(.callout)
                    Text(volume.status)
                        .font(.caption)
                    Spacer()
                    Text(CloudUsageFormat.gigabytes(volume.sizeGb))
                        .font(.callout)
                }
                .monospacedDigit()
            }
        }
        .foregroundStyle(.orange)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Buckets

    private var buckets: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Buckets")
            ForEach(verda.buckets) { bucket in
                HStack {
                    Text(bucket.name)
                    Spacer()
                    Text(CloudUsageFormat.gigabytes(bucket.sizeGb))
                }
                .font(.callout)
                .monospacedDigit()
            }
        }
    }

    // MARK: - Vormonate

    private var months: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Vormonate")
            ForEach(verda.months) { month in
                HStack {
                    Text(CloudUsageFormat.monthTitle(month.month))
                    Spacer()
                    Text(CloudUsageFormat.euros(month.spent))
                }
                .font(.callout)
                .monospacedDigit()
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
