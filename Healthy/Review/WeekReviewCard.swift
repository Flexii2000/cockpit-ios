import SwiftUI

/// Der Wochenrueckblick ganz unten im Dashboard (Vertrag §5, Felix 10.11.):
/// sechs Felder in zwei Spalten, je mit Pfeil gegen die Vorwoche. Was dasteht,
/// rechnet `WeekReviewCardModel`; hier wird nur gezeichnet.
struct WeekReviewCard: View {

    let model: WeekReviewCardModel

    private let columns = [GridItem(.flexible(), spacing: 12, alignment: .topLeading),
                           GridItem(.flexible(), spacing: 12, alignment: .topLeading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Wochenrückblick").font(.headline)
                Spacer(minLength: 8)
                Text(model.range)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(model.cells) { cell in
                    WeekReviewCell(cell: cell)
                }
            }
        }
        .dashboardCard()
        // Als Behaelter: die Kennung gehoert der Karte, nicht jedem Feld darin.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weekReviewCard")
    }
}

private struct WeekReviewCell: View {

    let cell: WeekReviewCardModel.Cell

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cell.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if let protein = cell.protein {
                    dot(.good, protein.green)
                    dot(.warn, protein.yellow)
                } else {
                    Text(cell.value)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
                if let arrow = cell.arrow {
                    // In Textfarbe: eine Richtung, keine Wertung.
                    Image(systemName: arrow.systemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(arrow.word)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func dot(_ tone: MacroTone, _ count: Int) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tone.gradient.last ?? .secondary)
                .frame(width: 8, height: 8)
            Text("\(count)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
    }
}
