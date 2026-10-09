import SwiftUI

/// Die Karten des Dashboards. Jede zeigt eine Zusammenfassung und fuehrt
/// dorthin, wo das Einzelne steht - die Zahlen kommen fertig aus den Diensten.

/// Der Rahmen aller Karten: dieselbe Flaeche wie die Kacheln im Gewicht-Tab.
private struct DashboardCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

extension View {
    func dashboardCard() -> some View { modifier(DashboardCardStyle()) }
}

/// Ueberschrift einer Karte mit dem Pfeil, der sagt: hier geht es weiter.
private struct CardTitle: View {
    let title: String

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Recovery: der Ring mit dem Score in der Farbe des Bands, daneben
/// „HRV 58 ms · RHF 49 · 7:41 h".
struct RecoveryCard: View {

    let day: RecoveryDay

    var body: some View {
        HStack(spacing: 14) {
            RecoveryRing(day: day, lineWidth: 9, mainFont: .title2)
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 6) {
                CardTitle(title: "Recovery")
                if let line = RecoveryFormat.summaryLine(day) {
                    Text(line)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .dashboardCard()
    }
}

/// Energie: „Verbrauch ≈ 2.840 · gegessen 2.150 · Defizit ≈ 690 kcal" - eine
/// Zeile, die lieber etwas kleiner wird, als nach einem „·" umzubrechen.
struct EnergyCard: View {

    let day: EnergyDay
    let foodAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(title: "Energie")
            Text(EnergyFormat.dashboardParts(day, foodAvailable: foodAvailable).joined(separator: " · "))
                .font(.subheadline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .dashboardCard()
    }
}

/// Halbe Karte: das 7-Tage-Mittel des Gewichts und das Residuum dazu, in der
/// Farbe der Kachel im Gewicht-Tab.
struct WeightHalfCard: View {

    let summary: WeightSummary

    var body: some View {
        let input = TileInput(weight: summary)
        VStack(alignment: .leading, spacing: 4) {
            Text("Gewicht ⌀ 7")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(summary.avg7.kg)
                .font(.title3.weight(.semibold))
            if summary.residual7 != nil {
                Text("Residuum " + summary.residual7.signedKg)
                    .font(.caption)
                    .foregroundStyle(WeightWidget.residual7.tone(input)?.color ?? .secondary)
            }
        }
        .dashboardCard()
    }
}

/// Halbe Karte: was vom kcal-Ziel heute noch uebrig ist, und die Schritte.
struct FoodHalfCard: View {

    let day: DaySummary
    let steps: Int?

    var body: some View {
        let over = day.remaining.kcal < 0
        VStack(alignment: .leading, spacing: 4) {
            Text(over ? "kcal drüber" : "kcal übrig")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(GermanNumber.string(abs(day.remaining.kcal)))
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
            if let steps {
                Text(GermanNumber.string(Double(steps)) + " Schritte")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .dashboardCard()
    }

    /// Wie der Tacho im Essen-Tab: bis 100 kcal drueber orange, darueber rot.
    private var color: Color {
        switch NutritionTone.kcalTone(consumed: day.consumed, targets: day.targets) {
        case .warn: Tone.warn.color
        case .bad:  Tone.bad.color
        default:    .primary
        }
    }
}
