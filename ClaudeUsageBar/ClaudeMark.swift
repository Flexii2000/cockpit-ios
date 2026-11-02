import SwiftUI

/// Das Strahlen-Zeichen in der Menüleiste und im Kopf - elf Strahlen in leicht
/// verschiedener Länge, wie das Claude-Zeichen. Als `Canvas`, damit es auch im
/// `ImageRenderer` (Vorlagenbild der Menüleiste) gezeichnet wird.
struct ClaudeMark: View {
    var color: Color = .primary

    private static let lengths: [CGFloat] = [1, 0.78, 0.93, 0.82, 0.98, 0.76, 0.9, 0.85, 1, 0.8, 0.94]

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let width = radius * 0.2
            for (index, length) in Self.lengths.enumerated() {
                let angle = CGFloat(index) / CGFloat(Self.lengths.count) * 2 * .pi - .pi / 2
                let direction = CGPoint(x: cos(angle), y: sin(angle))
                let inner: CGFloat = 0
                let outer = radius * length - width / 2
                var path = Path()
                path.move(to: CGPoint(x: center.x + direction.x * inner, y: center.y + direction.y * inner))
                path.addLine(to: CGPoint(x: center.x + direction.x * outer, y: center.y + direction.y * outer))
                context.stroke(path, with: .color(color),
                               style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Farben der App: Terrakotta wie Claude für den Normalfall, ab 75 % Orange,
/// ab 90 % Rot - dieselben Stufen wie die Mitteilungen (dazu 50 und 100).
enum ClaudePalette {

    static let accent = Color(red: 0.851, green: 0.467, blue: 0.341)

    static func level(_ percent: Double?) -> Color {
        guard let percent else { return .secondary }
        if percent >= 90 { return .red }
        if percent >= 75 { return .orange }
        return accent
    }

    /// Die Anteile der Woche: Claude Code in Terrakotta, der Rest in Systemfarben.
    static func share(_ key: String) -> Color {
        switch key {
        case "claude_code": accent
        case "chat": .blue
        case "cowork": .teal
        case "other": .gray
        default: .indigo
        }
    }

    static let track = Color.primary.opacity(0.09)
}

// MARK: - Glas

extension EnvironmentValues {
    /// Nur für die Bilder (`Snapshot`): `ImageRenderer` zeichnet Liquid Glass
    /// nicht, die Karten wären leer oder deckend weiß. Dann eine flache Fläche.
    @Entry var flatGlass = false
}

extension View {
    /// Eine Karte in Liquid Glass, optional leicht eingefärbt.
    func glassCard(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, tint: tint))
    }
}

private struct GlassCard: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?

    @Environment(\.flatGlass) private var flat

    func body(content: Content) -> some View {
        if flat {
            content
                .background((tint ?? .primary).opacity(0.07), in: .rect(cornerRadius: cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.primary.opacity(0.08)))
        } else {
            content
                .glassEffect(tint.map { Glass.regular.tint($0) } ?? .regular, in: .rect(cornerRadius: cornerRadius))
        }
    }
}
