import SwiftUI

/// Farben und Balken, die Vault und die Menüleiste teilen - damit eine Kategorie
/// auf dem Mac dieselbe Farbe hat wie auf dem iPhone. Nur SwiftUI-Systemfarben:
/// sie gibt es auf beiden Plattformen und in hell wie dunkel.
enum AWSUsagePalette {

    static func color(for key: String) -> Color {
        switch AWSCategoryKey(rawValue: key) {
        case .llm: .purple
        case .hytale: .green
        case .hosting: .blue
        case .other, nil: .gray
        }
    }

    /// Die Prozentzahl färbt sich ab 75 % orange, ab 90 % rot - dieselben Stufen,
    /// bei denen der Dienst Pushes schickt (dazu 50 und 100).
    static func percentColor(_ percent: Double?) -> Color {
        guard let percent else { return .secondary }
        if percent >= 90 { return .red }
        if percent >= 75 { return .orange }
        return .primary
    }

    static let track = Color.primary.opacity(0.08)
}

/// Ein Stück Balken: abgerechnet voll, live schraffiert.
struct AWSBarPiece: View {
    let color: Color
    let live: Bool

    var body: some View {
        if live {
            Rectangle()
                .fill(color.opacity(0.3))
                .overlay { AWSHatch().stroke(color, lineWidth: 1.5) }
                .clipped()
        } else {
            Rectangle().fill(color)
        }
    }
}

/// Schräge Striche - die Markierung für „läuft, noch nicht abgerechnet“.
struct AWSHatch: Shape {
    var spacing: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}

/// Der Budget-Balken: die Kategorien nebeneinander in ihren Farben, je mit dem
/// Live-Anteil schraffiert dahinter. Voll ist das Budget.
struct AWSBudgetBar: View {
    let usage: AWSUsage
    var height: CGFloat = 12

    var body: some View {
        let segments = usage.barSegments()
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    AWSBarPiece(color: AWSUsagePalette.color(for: segment.key), live: segment.live)
                        .frame(width: max(0, geometry.size.width * segment.fraction))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(AWSUsagePalette.track)
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel("Budget")
        .accessibilityValue(AWSUsageFormat.percent(usage.percent))
    }
}

/// Der Balken einer Kategorie, gemessen am Budget (ohne Budget an der Summe) -
/// so sind die vier Balken untereinander vergleichbar und zusammen der große.
struct AWSCategoryBar: View {
    let category: AWSCategory
    /// Was ein voller Balken bedeutet, in Dollar.
    let scale: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let color = AWSUsagePalette.color(for: category.key)
            let whole = scale > 0 ? scale : 1
            let billed = min(category.billed / whole, 1)
            let live = min(category.live / whole, max(0, 1 - billed))
            HStack(spacing: 0) {
                AWSBarPiece(color: color, live: false)
                    .frame(width: geometry.size.width * billed)
                if live > 0 {
                    AWSBarPiece(color: color, live: true)
                        .frame(width: geometry.size.width * live)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(AWSUsagePalette.track)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// Der Farbpunkt vor einer Kategorie.
struct AWSCategoryDot: View {
    let key: String
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(AWSUsagePalette.color(for: key))
            .frame(width: size, height: size)
    }
}

/// Ein Vormonat als dünner Balken aus den vier Kategorien.
struct AWSMonthBar: View {
    let month: AWSMonth
    /// Was ein voller Balken bedeutet - das größere von Budget und teuerstem Monat,
    /// damit die Monate untereinander vergleichbar sind.
    let scale: Double
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(month.parts, id: \.key) { part in
                    if part.amount > 0 {
                        Rectangle()
                            .fill(AWSUsagePalette.color(for: part.key))
                            .frame(width: geometry.size.width * min(part.amount / max(scale, 0.000_001), 1))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(AWSUsagePalette.track)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

extension AWSUsage {

    /// Was ein voller Kategorie-Balken bedeutet: das Budget, ohne Budget die Summe.
    var categoryScale: Double {
        if let limit = budget?.limit, limit > 0 { return limit }
        return max(spent, 0.01)
    }

    /// Maßstab der Vormonate: das größere von Budget und teuerstem Monat.
    var monthScale: Double {
        max(budget?.limit ?? 0, months.map(\.total).max() ?? 0, 0.01)
    }
}
