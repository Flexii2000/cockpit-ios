import SwiftUI

/// Ein Tacho wie in der Weboberflaeche: ein Bogen ueber 270°, der bei 135°
/// beginnt, dazu eine Kerbe da, wo das Tagesziel sitzt.
struct GaugeView: View {

    let ratio: Double
    let tone: MacroTone
    let main: String
    let sub: String
    var lineWidth: CGFloat = 9
    var mainFont: Font = .title3
    var subFont: Font = .caption2

    /// Anteil des Kreises, den der Bogen einnimmt (270°).
    private let sweep = 0.75
    /// Luft ueber dem Ziel. Ohne diesen Aufschlag saesse die Zielmarke am
    /// Bogenende und waere wertlos - man saehe nie, ob man knapp oder weit
    /// darueber liegt.
    ///
    /// Oeffentlich, damit niemand daneben eine eigene 1,25 schreibt: wer den
    /// Anteil fuer diesen Tacho ausrechnet, braucht denselben Wert.
    static let headroom = 1.25
    private let headroom = GaugeView.headroom

    var body: some View {
        ZStack {
            // Nur der Bogen dreht sich - die Beschriftung steht gerade.
            ZStack {
                Circle()
                    .trim(from: 0, to: sweep)
                    .stroke(Color.primary.opacity(0.12),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                Circle()
                    .trim(from: 0, to: sweep * min(max(ratio, 0), 1))
                    .stroke(
                        LinearGradient(colors: tone.gradient,
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                // Ausserhalb des Bogens statt quer hindurch: eine Linie mitten
                // durch die Fuellung zerschneidet sie optisch, eine Kerbe
                // daneben markiert genauso gut.
                GaugeTick(fraction: sweep / headroom, inset: lineWidth / 2)
                    .stroke(Color.primary.opacity(0.55),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            .rotationEffect(.degrees(135))

            VStack(spacing: 0) {
                Text(main)
                    .font(mainFont.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(sub)
                    .font(subFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .padding(.horizontal, lineWidth + 6)
        }
        .padding(6)
    }
}

/// Die Kerbe am Zielwert, knapp ausserhalb des Bogens.
private struct GaugeTick: Shape {
    let fraction: Double
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2 - inset
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let angle = Angle.degrees(360 * fraction).radians
        func point(_ distance: Double) -> CGPoint {
            CGPoint(x: center.x + distance * cos(angle),
                    y: center.y + distance * sin(angle))
        }
        var path = Path()
        path.move(to: point(radius + inset + 1))
        path.addLine(to: point(radius + inset + 6))
        return path
    }
}
