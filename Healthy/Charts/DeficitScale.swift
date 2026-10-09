import Foundation

/// Die eigene Skala der Kurve „Defizit ⌀" (Vertrag §5).
///
/// Auf der kcal-Achse ginge es nicht: die beginnt bei 1.500, ein Defizit von
/// 300 laege darunter. Die Kurve bekommt deshalb eigene Grenzen und wird in den
/// Wertebereich des Diagramms hineingerechnet - wie das Gewicht im
/// Essen-Verlauf. Die Grenzen schliessen 0 immer ein (die Nulllinie trennt
/// Defizit und Ueberschuss) und liegen auf runden Schritten: dieselbe Rechnung
/// wie `deficitScale` in der Weboberflaeche des Weight Trackers, damit beide
/// dieselben Marken zeigen.
struct DeficitScale: Equatable, Sendable {

    let domain: ClosedRange<Double>
    /// 250 kcal; ab einer Spanne von mehr als 1.500 kcal 500.
    let step: Double

    init(values: [Double]) {
        let low = min(0, values.min() ?? 0)
        let high = max(0, values.max() ?? 0)
        let step: Double = high - low > 1500 ? 500 : 250
        let lower = (low / step).rounded(.down) * step
        // Mindestens zwei Schritte - sonst klebte eine flache Kurve am Rand,
        // und ohne Werte gaebe es keinen Bereich.
        let upper = max((high / step).rounded(.up) * step, lower + 2 * step)
        domain = lower...upper
        self.step = step
    }

    /// Die Beschriftung, wenn die rechte Seite frei ist: jeder Schritt, aussen
    /// wie die kg-Skala.
    var ticks: [Double] {
        Array(stride(from: domain.lowerBound, through: domain.upperBound, by: step))
    }

    /// Die Beschriftung innen am rechten Rand, wenn aussen schon eine andere
    /// Skala steht: nur 0 und hoechstens zwei runde Werte - die Raender.
    var insideTicks: [Double] {
        Set([domain.lowerBound, 0, domain.upperBound]).sorted()
    }

    /// Wo ein Wert dieser Skala im Wertebereich des Diagramms liegt.
    func position(_ value: Double, in target: ClosedRange<Double>) -> Double {
        target.lowerBound + (value - domain.lowerBound) / (domain.upperBound - domain.lowerBound)
            * (target.upperBound - target.lowerBound)
    }

    /// Umgekehrt: welcher Wert an einer Stelle des Diagramms steht.
    func value(at position: Double, in target: ClosedRange<Double>) -> Double {
        guard target.upperBound > target.lowerBound else { return domain.lowerBound }
        return domain.lowerBound + (position - target.lowerBound) / (target.upperBound - target.lowerBound)
            * (domain.upperBound - domain.lowerBound)
    }
}
