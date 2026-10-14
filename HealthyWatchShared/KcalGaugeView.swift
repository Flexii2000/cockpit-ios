import SwiftUI

/// Die kcal-Komplikation (Felix, 14.10.) im Stil der Temperatur-Komplikation:
/// ein Bogen mit Verlauf von Gruen nach Orange, links „0“, in der Mitte, was
/// heute gegessen ist, rechts das Tagesziel. Ueber dem Ziel bleibt der Bogen voll.
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
                Text(String(Int(consumed.rounded())))
            } minimumValueLabel: {
                // Die Grenzen muessen reine `Text` sein - der Stil verkleinert sie selbst.
                Text("0").foregroundStyle(.green)
            } maximumValueLabel: {
                Text(String(Int(target.rounded()))).foregroundStyle(.orange)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [.green, .yellow, .orange]))
            .accessibilityLabel("Kalorien")
            .accessibilityValue("\(Int(consumed.rounded())) von \(Int(target.rounded()))")
        } else {
            Gauge(value: 0) {
                Text("kcal")
            } currentValueLabel: {
                Text("–")
            }
            .gaugeStyle(.accessoryCircular)
        }
    }
}
