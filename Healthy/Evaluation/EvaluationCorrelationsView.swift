import SwiftUI

/// Die Zusammenhaenge je Frage-Paar: oben am selben Tag, darunter um einen Tag
/// versetzt (links heute, rechts morgen). Die Fragen stehen als ihre Farbpunkte
/// da - als ganze Saetze waeren neun Zeilen kaum zu lesen; die Legende darueber
/// sagt, welche Farbe welche Frage ist.
struct EvaluationCorrelationsView: View {

    typealias Statistics = EvaluationStatistics

    let results: [Statistics.Result]
    let color: (UUID) -> Color
    let title: (UUID) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Zusammenhänge")
                    .font(.headline)
                Text("Spearman ρ · Pearson r · p nach Holm · n_eff nach Bartlett")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            group("Gleicher Tag", kind: .sameDay)
            group("Am Folgetag", kind: .nextDay)
        }
    }

    @ViewBuilder
    private func group(_ heading: String, kind: Statistics.Kind) -> some View {
        let rows = results.filter { $0.kind == kind }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(heading)
                    .font(.subheadline.weight(.medium))
                ForEach(rows) { row($0) }
            }
        }
    }

    private func row(_ result: Statistics.Result) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                dot(result.first)
                Image(systemName: result.kind == .sameDay ? "arrow.left.and.right" : "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                dot(result.second)
                Spacer()
                Text("n \(result.n)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                ForEach(Statistics.Measure.allCases, id: \.self) { measure in
                    estimateRow(measure, result.estimates[measure])
                }
            }
            .font(.caption.monospacedDigit())
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityTitle(result))
    }

    @ViewBuilder
    private func estimateRow(_ measure: Statistics.Measure, _ estimate: Statistics.Estimate?) -> some View {
        if let estimate {
            let significant = (estimate.adjustedP ?? 1) < 0.05
            GridRow {
                Text(measure.symbol).foregroundStyle(.secondary)
                Text(estimate.coefficient.formatted(
                    .number.precision(.fractionLength(2)).sign(strategy: .always(includingZero: false))))
                    .fontWeight(significant ? .semibold : .regular)
                Text("p \(Self.pText(estimate.adjustedP))")
                Text(estimate.adjustedP.map(Statistics.stars) ?? "")
                    .fontWeight(.semibold)
                Text("n_eff \(Int(estimate.effectiveN.rounded()))")
                    .foregroundStyle(.secondary)
            }
        } else {
            GridRow {
                Text(measure.symbol).foregroundStyle(.secondary)
                Text("–")
            }
        }
    }

    private func dot(_ question: UUID) -> some View {
        Circle()
            .fill(color(question))
            .frame(width: 10, height: 10)
    }

    private func accessibilityTitle(_ result: Statistics.Result) -> String {
        let link = result.kind == .sameDay ? "und" : "heute, am Folgetag"
        return "\(title(result.first)) \(link) \(title(result.second))"
    }

    static func pText(_ p: Double?) -> String {
        guard let p else { return "–" }
        if p < 0.001 { return "< " + 0.001.formatted(.number.precision(.fractionLength(3))) }
        return p.formatted(.number.precision(.fractionLength(3)))
    }
}
