import SwiftUI

/// Verbrauch und Defizit eines Tages, unter „von … kcal" im Essen-Tab:
///
///     Verbrauch ≈ 2.610 kcal · Uhr 2.840 · −8 %
///     Defizit ≈ 460 kcal
///
/// Die Zahlen kommen fertig vom Weight Tracker; hier wird nur gesetzt.
struct EnergyLines: View {

    let day: EnergyDay

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let line = EnergyFormat.expenditureLine(day), let expenditure = EnergyFormat.expenditure(day) {
                // Neben dem grossen Tacho ist die Spalte schmal. Passt die
                // Zeile nicht, bricht sie vor „Uhr" um - nicht mitten in einer
                // Zahl.
                ViewThatFits(in: .horizontal) {
                    Text(line).lineLimit(1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(expenditure)
                        if let watch = EnergyFormat.watch(day) { Text(watch) }
                    }
                }
                .foregroundStyle(.secondary)
            }
            if let balance = EnergyFormat.balanceLine(day) {
                Text(balance)
                    .fontWeight(.medium)
            }
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("energyLines")
    }
}
