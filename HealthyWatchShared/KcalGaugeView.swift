import SwiftUI

/// Die kcal-Komplikation (Felix, 14.10.) im Stil der Temperatur-Komplikation:
/// ein Bogen mit Verlauf von Gruen nach Orange, links „0“, rechts das
/// Tagesziel; der Bogen fuellt sich mit dem, was heute gegessen ist, und bleibt
/// ueber dem Ziel voll. In der Mitte steht seit 23.10., was noch uebrig ist
/// (Felix) - vorher das Gegessene.
///
/// Liegt in `HealthyWatchShared`, damit auch die Kachel-Vorschau der iPhone-App
/// sie zeigen kann - den Uhren-Simulator kann niemand aufs Zifferblatt legen.
struct KcalGaugeView: View {

    /// `nil`: unbekannt (etwa nach Mitternacht ohne Netz) - nie eine erfundene Zahl.
    let consumed: Double?
    let target: Double?

    var body: some View {
        if let consumed, let target, target > 0 {
            Gauge(value: min(consumed, target), in: 0...target) {
                Text("kcal")
            } currentValueLabel: {
                Text(Self.center(consumed: consumed, target: target))
            } minimumValueLabel: {
                // Die Grenzen muessen reine `Text` sein - der Stil verkleinert sie selbst.
                Text("0").foregroundStyle(.green)
            } maximumValueLabel: {
                Text(String(Int(target.rounded()))).foregroundStyle(.orange)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [.green, .yellow, .orange]))
            .accessibilityLabel("Kalorien")
            .accessibilityValue(Self.spokenRest(consumed: consumed, target: target))
        } else {
            Gauge(value: 0) {
                Text("kcal")
            } currentValueLabel: {
                Text("–")
            }
            .gaugeStyle(.accessoryCircular)
        }
    }

    /// Der Rest in der Mitte, drueber mit Plus davor - wie der runde kcal-Ring auf
    /// dem iPhone-Sperrbildschirm: fuer „drüber“ ist kein Platz.
    static func center(consumed: Double, target: Double) -> String {
        let rest = Int((target - consumed).rounded())
        return rest < 0 ? "+\(-rest)" : "\(rest)"
    }

    private static func spokenRest(consumed: Double, target: Double) -> String {
        let rest = Int((target - consumed).rounded())
        return rest < 0 ? "\(-rest) kcal drüber" : "\(rest) kcal übrig"
    }
}
