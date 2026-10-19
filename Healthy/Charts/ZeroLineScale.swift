import Foundation

/// Eine eigene Skala mit Nulllinie, in den Wertebereich eines Diagramms
/// hineingerechnet (Vertrag §5): „Defizit ⌀" und „Distanz z. Target".
///
/// Auf der Achse des Diagramms ginge es nicht: die kcal-Achse beginnt bei
/// 1.500, ein Defizit von 300 laege darunter; die kg-Achse reicht ueber ein paar
/// Kilogramm, ein Abstand von 0,4 kg zur Zielkurve waere darauf ein flacher
/// Strich. Die Kurve bekommt deshalb eigene Grenzen und wird in den
/// Wertebereich des Diagramms hineingerechnet - wie das Gewicht im
/// Essen-Verlauf. Die Grenzen schliessen 0 immer ein (die Nulllinie trennt
/// Defizit und Ueberschuss bzw. ueber und unter der Zielkurve) und liegen auf
/// runden Schritten: dieselbe Rechnung wie `deficitScale` in der
/// Weboberflaeche des Weight Trackers, damit beide dieselben Marken zeigen.
struct ZeroLineScale: Equatable, Sendable {

    let domain: ClosedRange<Double>
    let step: Double

    /// - Parameter step: der Schritt zur Spanne der Werte (samt 0).
    init(values: [Double], step stepForSpan: (Double) -> Double) {
        let low = min(0, values.min() ?? 0)
        let high = max(0, values.max() ?? 0)
        let step = stepForSpan(high - low)
        let lower = (low / step).rounded(.down) * step
        // Mindestens zwei Schritte - sonst klebte eine flache Kurve am Rand,
        // und ohne Werte gaebe es keinen Bereich.
        let upper = max((high / step).rounded(.up) * step, lower + 2 * step)
        domain = lower...upper
        self.step = step
    }

    /// „Defizit ⌀": 250 kcal; ab einer Spanne von mehr als 1.500 kcal 500.
    static func deficit(_ values: [Double]) -> ZeroLineScale {
        ZeroLineScale(values: values) { $0 > 1500 ? 500 : 250 }
    }

    /// „Distanz z. Target": 0,5 kg; bei einer Spanne ueber 3 kg 1 kg, ueber
    /// 8 kg 2 kg - in „Alles" liegen Jahre zwischen den Raendern.
    static func targetDistance(_ values: [Double]) -> ZeroLineScale {
        ZeroLineScale(values: values) { $0 > 8 ? 2 : $0 > 3 ? 1 : 0.5 }
    }

    /// Die Beschriftung, wenn die rechte Seite frei ist: jeder Schritt, aussen
    /// wie die kg-Skala.
    var ticks: [Double] {
        Array(stride(from: domain.lowerBound, through: domain.upperBound, by: step))
    }

    /// Die Beschriftung innen am Rand, wenn aussen schon eine andere Skala
    /// steht: nur 0 und hoechstens zwei runde Werte - die Raender.
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
