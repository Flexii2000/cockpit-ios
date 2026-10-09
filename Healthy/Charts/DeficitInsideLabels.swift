import Charts
import SwiftUI

/// Die Defizit-Skala klein innen am rechten Rand - wenn aussen schon eine
/// andere steht (Vertrag §5: kcal im Gewicht-Diagramm, kg im Essen-Verlauf).
///
/// Nur 0 und die beiden runden Raender, ohne Titel: mehr Zahlen im Diagramm
/// verdeckten die Kurven. Innen statt als zweite Achse, weil Swift Charts auf
/// einer Seite nur eine Spalte Beschriftungen setzt - zwei Skalen ueberdeckten
/// sich dort. Gehoert in `chartBackground`: im Overlay laegen die Zahlen ueber
/// der Sprechblase.
struct DeficitInsideLabels: View {

    let scale: DeficitScale
    /// Der Wertebereich des Diagramms, in den das Defizit hineingerechnet ist.
    let target: ClosedRange<Double>
    let proxy: ChartProxy
    /// Die Zeichenflaeche im Koordinatenraum des Hintergrunds.
    let plot: CGRect

    /// Halbe Hoehe einer Beschriftung - so weit bleibt sie vom Rand weg.
    private let halfHeight: CGFloat = 7

    var body: some View {
        ForEach(scale.insideTicks, id: \.self) { tick in
            if let y = proxy.position(forY: scale.position(tick, in: target)) {
                Text(GermanNumber.string(tick))
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.deficit)
                    .fixedSize()
                    .frame(width: max(plot.width - 4, 0), alignment: .trailing)
                    // Knapp ueber der eigenen Hoehe, damit die Zahl auf der
                    // Nulllinie steht statt sie zu durchkreuzen; am oberen
                    // Rand darunter.
                    .position(x: plot.minX + max(plot.width - 4, 0) / 2,
                              y: plot.minY + min(max(y - halfHeight, halfHeight),
                                                 plot.height - halfHeight))
            }
        }
        .allowsHitTesting(false)
    }
}
