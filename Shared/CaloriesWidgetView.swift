import SwiftUI
import WidgetKit

/// Was die Kachel zeigt.
///
/// Drei Zustaende, und keiner davon ist eine erfundene Zahl.
enum WidgetState: Equatable, Sendable {
    case noAccess
    case value(RemainingCalories)
    /// Server nicht erreichbar - mit dem letzten bekannten Stand, falls es
    /// einen gibt.
    case unreachable(RemainingCalories?)

    var calories: RemainingCalories? {
        switch self {
        case .value(let value):       value
        case .unreachable(let value): value
        case .noAccess:               nil
        }
    }
}

/// Die Darstellung.
///
/// `family` kommt als Parameter statt aus `@Environment(\.widgetFamily)`:
/// so kann ein Debug-Bildschirm der App dieselbe Ansicht in allen Groessen
/// zeigen - der Simulator kann keine Kachel auf den Homebildschirm legen.
struct CaloriesWidgetView: View {

    let family: WidgetFamily
    let state: WidgetState

    var body: some View {
        switch family {
        case .systemMedium:         medium
        case .accessoryCircular:    circular
        case .accessoryRectangular: rectangular
        default:                    small
        }
    }

    // MARK: - Sperrbildschirm

    /// Ein Ring mit dem Rest in der Mitte. Der Sperrbildschirm faerbt selbst
    /// (alles einfarbig), deshalb hier keine eigene Tonlage - „drueber" steht
    /// als Plus davor, mehr Platz gibt es nicht.
    private var circular: some View {
        Group {
            if let value {
                Gauge(value: min(value.consumed.kcal, value.targets.kcal),
                      in: 0...max(value.targets.kcal, 1)) {
                    Image(systemName: "fork.knife")
                } currentValueLabel: {
                    Text(value.isOver ? "+\(abs(value.remaining.kcal).whole)" : abs(value.remaining.kcal).whole)
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                }
                .gaugeStyle(.accessoryCircular)
                .opacity(value.isStale() ? 0.5 : 1)
            } else {
                Image(systemName: state == .noAccess ? "lock" : "wifi.slash")
                    .font(.title3)
            }
        }
    }

    /// Rest, Balken, Makros - drei Zeilen, so viel passt.
    private var rectangular: some View {
        Group {
            if let value {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "fork.knife").font(.caption2)
                        Text(value.isOver
                             ? "\(abs(value.remaining.kcal).whole) kcal drüber"
                             : "Noch \(abs(value.remaining.kcal).whole) kcal")
                            .font(.headline.monospacedDigit())
                        if value.isStale() {
                            Text(value.date.short).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Gauge(value: min(value.consumed.kcal, value.targets.kcal),
                          in: 0...max(value.targets.kcal, 1)) { EmptyView() }
                        .gaugeStyle(.accessoryLinear)
                    Text(Macro.allCases.map {
                        "\($0.short) \($0.value(value.consumed).whole)"
                    }.joined(separator: " · ") + " g")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .opacity(value.isStale() ? 0.6 : 1)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: state == .noAccess ? "lock" : "wifi.slash")
                    Text(state == .noAccess ? "Kein Zugang" : "Nicht erreichbar").font(.caption)
                }
            }
        }
    }

    private var value: RemainingCalories? { state.calories }

    private var small: some View {
        Group {
            if let value {
                gauge(value)
            } else {
                hint
            }
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            if let value {
                gauge(value)
                    .frame(width: 108)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Macro.allCases) { macro in
                        HStack(spacing: 6) {
                            Text(macro.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Text(macro.value(value.consumed).whole)
                                .font(.caption.monospacedDigit().weight(.medium))
                            Text("/ \(macro.value(value.targets).whole) g")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                hint
            }
        }
    }

    private func gauge(_ value: RemainingCalories) -> some View {
        VStack(spacing: 2) {
            GaugeView(ratio: value.ratio,
                      tone: NutritionTone.kcalTone(consumed: value.consumed,
                                                   targets: value.targets),
                      main: abs(value.remaining.kcal).whole,
                      sub: value.isOver ? "kcal drüber" : "kcal übrig",
                      lineWidth: 8,
                      mainFont: .title2)
            if value.isStale() {
                // Gedaempft und beschriftet statt einfach angezeigt: der Rest
                // von gestern ist keine alte Wahrheit, sondern eine falsche
                // Aussage ueber heute.
                Text("Stand: \(value.date.short)")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(value.isStale() ? 0.5 : 1)
    }

    /// Kein Platzhalterwert, keine Null: „0 kcal übrig" waere eine
    /// Falschaussage, und eine Kachel, die luegt, ist schlechter als eine,
    /// die schweigt.
    private var hint: some View {
        VStack(spacing: 6) {
            Image(systemName: state == .noAccess ? "lock" : "wifi.slash")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(state == .noAccess ? "Kein Zugang" : "Nicht erreichbar")
                .font(.caption)
                .foregroundStyle(.secondary)
            if state == .noAccess {
                Text("In der App einrichten")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
