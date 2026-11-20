import SwiftUI
import WidgetKit

/// Die grosse Komplikation (Felix, 20.11.): drei Ringe nebeneinander, unter jedem
/// die Zahl - wie die grosse Sperrbildschirm-Kachel des iPhones, nur mit Strain
/// als drittem Ring. Fuer die Mitte des Modular-Zifferblatts
/// (`accessoryRectangular`); was gezeigt wird, steht in `HealthRings`.
///
/// Liegt in `HealthyWatchShared`, damit auch die Kachel-Vorschau der iPhone-App
/// sie zeigen kann - den Uhren-Simulator kann niemand aufs Zifferblatt legen.
struct HealthRingsView: View {

    let rings: HealthRings

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            ForEach(rings.all) { ring in
                HealthRingColumn(ring: ring)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Ein Ring samt Zahl. Auf einem einfarbigen Zifferblatt faerbt watchOS die Ringe
/// in der Farbe des Zifferblatts (`widgetAccentable`), die Zahlen bleiben weiss;
/// auf „Mehrfarbig“ hat jeder Ring seine Farbe.
struct HealthRingColumn: View {

    let ring: HealthRings.Ring

    private static let lineWidth: CGFloat = 4.5

    var body: some View {
        VStack(spacing: 1) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.25), lineWidth: Self.lineWidth)
                Circle()
                    .trim(from: 0, to: ring.fill)
                    .stroke(fillStyle, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
            }
            .padding(Self.lineWidth / 2)
            .aspectRatio(1, contentMode: .fit)
            .widgetAccentable()
            Text(ring.value)
                .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ring.kind.title)
        .accessibilityValue(ring.spoken)
    }

    private var symbol: String {
        switch ring.kind {
        case .kcal:   "fork.knife"
        case .steps:  "figure.walk"
        case .strain: "heart.fill"
        }
    }

    /// kcal wie der runde kcal-Ring (gruen bis orange), Strain in der Farbe der
    /// App und ueber dem Ziel in deren „über Ziel“-Orange (dunkle Toene, das
    /// Zifferblatt ist schwarz).
    private var color: Color {
        switch ring.kind {
        case .kcal:   .green
        case .steps:  Color(red: 0x3B / 255, green: 0xC9 / 255, blue: 0xDB / 255)
        case .strain: ring.over ? Color(red: 1, green: 0x92 / 255, blue: 0x2B / 255)
                                : Color(red: 0x4D / 255, green: 0xAB / 255, blue: 0xF7 / 255)
        }
    }

    private var fillStyle: AnyShapeStyle {
        guard ring.kind == .kcal else { return AnyShapeStyle(color) }
        // Der Verlauf liegt ueber dem ganzen Ring, der Bogen zeigt den Teil bis
        // zum Gegessenen - beim halben Tag also gruen bis gelb, wie der Bogen der
        // runden Komplikation. Ein paar Grad vor null, damit die runde Kappe am
        // Anfang nicht das Orange vom Ende bekommt.
        return AnyShapeStyle(AngularGradient(colors: [.green, .yellow, .orange], center: .center,
                                             startAngle: .degrees(-6), endAngle: .degrees(354)))
    }
}
