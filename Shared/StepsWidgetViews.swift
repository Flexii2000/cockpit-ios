import SwiftUI

/// Die Schritte als Ring auf dem Sperrbildschirm (14.10.): Schritte gegen das
/// Tagesziel, die Zahl in der Mitte. Der Sperrbildschirm faerbt selbst - keine
/// eigenen Toene.
struct StepsCircleView: View {

    let reading: StepsReading

    var body: some View {
        Gauge(value: reading.ratio) {
            Image(systemName: "figure.walk")
        } currentValueLabel: {
            Text(reading.steps.map(String.init) ?? "–")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                // Fuenf Stellen passen sonst nicht zwischen den Bogen.
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel("Schritte")
        .accessibilityValue(reading.steps.map { "\($0) von \(reading.goal)" } ?? "unbekannt")
    }
}

/// Die grosse Sperrbildschirm-Kachel (14.10., Felix' Wahl „zwei Ringe
/// nebeneinander“): links kcal gegessen gegen das Ziel, rechts Schritte gegen
/// das Ziel. Unter dem kcal-Ring steht seit 23.10. der Rest statt des
/// Gegessenen (Felix) - der Ring fuellt sich weiter mit dem Gegessenen wie der
/// runde kcal-Ring, sonst liefe er gegen den Schritte-Ring daneben.
struct TodayOverviewView: View {

    let calories: WidgetState
    let steps: StepsReading

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            column(icon: "fork.knife", ratio: kcalRatio, value: kcalText,
                   unit: calories.calories?.remainingUnit ?? "kcal",
                   dimmed: calories.calories?.isStale() ?? false)
                .frame(maxWidth: .infinity)
            column(icon: "figure.walk", ratio: steps.ratio, value: steps.steps.map(String.init) ?? "–",
                   unit: "Schritte", dimmed: false)
                .frame(maxWidth: .infinity)
        }
    }

    private var kcalRatio: Double {
        guard let value = calories.calories, value.targets.kcal > 0 else { return 0 }
        return min(value.consumed.kcal / value.targets.kcal, 1)
    }

    private var kcalText: String {
        switch calories {
        case .noAccess: "–"
        default: calories.calories?.remainingValue ?? "–"
        }
    }

    private func column(icon: String, ratio: Double, value: String, unit: String, dimmed: Bool) -> some View {
        VStack(spacing: 2) {
            Gauge(value: ratio) {
                Image(systemName: icon)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .scaleEffect(0.78)
            .frame(width: 44, height: 44)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .opacity(dimmed ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unit)
        .accessibilityValue(value)
    }
}
