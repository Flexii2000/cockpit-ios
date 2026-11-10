import SwiftUI

/// Strain im Dashboard (Vertrag §5, Felix 10.11.): gross der Strain von heute,
/// daneben das Ziel, darunter der Balken von 0 bis 21 mit der Zielmarke, unten
/// die sieben Tage bis heute. Was wohin gehoert, rechnet `StrainCardModel`;
/// hier wird nur gezeichnet.
///
/// Ein Balken und kein Ring: direkt darueber steht die Recovery als Ring, und
/// zwei Ringe uebereinander laesen sich wie dieselbe Art Zahl. Der Balken hat
/// ausserdem Platz fuer die Marke - um die geht es (Ziel gegen Stand).
struct StrainCard: View {

    let model: StrainCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Strain")
            HStack(alignment: .firstTextBaseline) {
                Text(model.value ?? "–")
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .accessibilityIdentifier("strainValue")
                Spacer(minLength: 8)
                if let target = model.target {
                    Text(target)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("strainTarget")
                }
            }
            if let bar = model.bar {
                StrainBar(bar: bar)
            }
            if let week = model.week {
                StrainWeek(bars: week)
                    .padding(.top, model.bar == nil ? 0 : 4)
            }
        }
        .dashboardCard()
    }
}

/// Der Stand von heute auf der Skala 0–21: in der Strain-Farbe bis zum Strain,
/// der Teil hinter der Zielmarke in der Farbe „über Ziel“, die Marke ein
/// senkrechter Strich - wie der Bilanzbalken der Energie-Karte.
private struct StrainBar: View {

    let bar: StrainCardModel.Bar

    private let barHeight: CGFloat = 10
    /// Die Marke steht oben und unten etwas ueber - sonst verschwaende sie in
    /// der Fuellung.
    private let markHeight: CGFloat = 18

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: barHeight)
                HStack(spacing: 0) {
                    Rectangle().fill(Palette.strain).frame(width: width * bar.base)
                    Rectangle().fill(Palette.strainOver).frame(width: width * bar.over)
                }
                .frame(width: width, height: barHeight, alignment: .leading)
                .clipShape(Capsule())
                if let target = bar.target {
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: 3, height: markHeight)
                        .offset(x: min(max(width * target - 1.5, 0), width - 3))
                }
            }
            .frame(width: width, height: markHeight)
        }
        .frame(height: markHeight)
        .accessibilityHidden(true)
    }
}

/// Die sieben Tage bis heute als Balken auf derselben Skala 0–21, heute
/// blasser - der Tag laeuft noch. Ein Tag ohne Wert bleibt leer.
private struct StrainWeek: View {

    let bars: [StrainCardModel.WeekBar]

    private let plotHeight: CGFloat = 44
    private let barWidth: CGFloat = 14

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                plot(in: geometry.size)
            }
            .frame(height: plotHeight)
            HStack(spacing: 0) {
                ForEach(bars) { bar in
                    Text(bar.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func plot(in size: CGSize) -> some View {
        let column = size.width / CGFloat(max(bars.count, 1))
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: size.width, height: 1)
                .offset(y: size.height - 1)
            ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
                if let share = bar.height {
                    let length = CGFloat(StrainCardModel.barLength(share, in: size.height))
                    RoundedRectangle(cornerRadius: min(2, length / 2))
                        .fill(Palette.strain.opacity(bar.isToday ? 0.55 : 1))
                        .frame(width: barWidth, height: length)
                        .offset(x: column * (CGFloat(index) + 0.5) - barWidth / 2, y: size.height - length)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}
