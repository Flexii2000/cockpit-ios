import Charts
import SwiftUI

/// Eine eigene Skala klein innen am Rand - wenn aussen schon eine andere steht
/// (Vertrag §5): das Defizit rechts (kcal im Gewicht-Diagramm, kg im
/// Essen-Verlauf), „Distanz z. Target" links, weil innen rechts dann schon das
/// Defizit steht.
///
/// Nur 0 und die beiden runden Raender, ohne Titel: mehr Zahlen im Diagramm
/// verdeckten die Kurven. Innen statt als zweite Achse, weil Swift Charts auf
/// einer Seite nur eine Spalte Beschriftungen setzt - zwei Skalen ueberdeckten
/// sich dort. Gehoert in `chartBackground`: im Overlay laegen die Zahlen ueber
/// der Sprechblase.
struct InsideScaleLabels: View {

    let scale: ZeroLineScale
    /// Der Wertebereich des Diagramms, in den die Skala hineingerechnet ist.
    let target: ClosedRange<Double>
    let proxy: ChartProxy
    /// Die Zeichenflaeche im Koordinatenraum des Hintergrunds.
    let plot: CGRect
    let color: Color
    let edge: HorizontalEdge
    let format: (Double) -> String

    /// Halbe Hoehe einer Beschriftung - so weit bleibt sie vom Rand weg.
    private let halfHeight: CGFloat = 7

    var body: some View {
        let width = max(plot.width - 4, 0)
        ForEach(scale.insideTicks, id: \.self) { tick in
            if let y = proxy.position(forY: scale.position(tick, in: target)) {
                Text(format(tick))
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
                    .fixedSize()
                    .frame(width: width, alignment: edge == .leading ? .leading : .trailing)
                    // Knapp ueber der eigenen Hoehe, damit die Zahl auf der
                    // Nulllinie steht statt sie zu durchkreuzen; am oberen
                    // Rand darunter.
                    .position(x: plot.minX + (edge == .leading ? 4 : 0) + width / 2,
                              y: plot.minY + min(max(y - halfHeight, halfHeight),
                                                 plot.height - halfHeight))
            }
        }
        .allowsHitTesting(false)
    }
}
