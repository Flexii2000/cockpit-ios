import SwiftUI

/// Die Karten des Dashboards. Jede zeigt eine Zusammenfassung und fuehrt
/// dorthin, wo das Einzelne steht - die Zahlen kommen fertig aus den Diensten.

/// Der Rahmen aller Karten: dieselbe Flaeche wie die Kacheln im Gewicht-Tab.
private struct DashboardCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

extension View {
    func dashboardCard() -> some View { modifier(DashboardCardStyle()) }
}

/// Ueberschrift einer Karte mit dem Pfeil, der sagt: hier geht es weiter.
private struct CardTitle: View {
    let title: String

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Recovery: der Ring mit dem Score in der Farbe des Bands, daneben
/// „HRV 58 ms · RHF 49 · 7:41 h".
struct RecoveryCard: View {

    let day: RecoveryDay

    var body: some View {
        HStack(spacing: 14) {
            RecoveryRing(day: day, lineWidth: 9, mainFont: .title2)
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 6) {
                CardTitle(title: "Recovery")
                if let line = RecoveryFormat.summaryLine(day) {
                    Text(line)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .dashboardCard()
    }
}

/// Energie (Vertrag §5, Felix 09.10.: „Balken + Woche"): gross die Bilanz
/// von heute, darunter der Bilanzbalken, unten die Woche. Was wohin gehoert,
/// rechnet `EnergyCardModel`; hier wird nur gezeichnet.
struct EnergyCard: View {

    let model: EnergyCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(title: "Energie")
            if let headline = model.headline {
                let color = headline.isSurplus ? Palette.surplus : Palette.deficit
                Text("\(headline.word) \(Text(headline.amount).foregroundStyle(color))")
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let bar = model.bar {
                EnergyBalanceBar(bar: bar)
            }
            if let week = model.week {
                EnergyWeek(week: week)
                    .padding(.top, model.bar == nil ? 0 : 4)
            }
        }
        .dashboardCard()
    }
}

/// Gegessen gegen Verbrauch als ein Balken: gelb bis „gegessen", die Luecke
/// bis zum Verbrauch in Defizit-Farbe, was darueber hinausgeht, in
/// Ueberschuss-Farbe, und eine Marke beim Verbrauch.
private struct EnergyBalanceBar: View {

    let bar: EnergyCardModel.BalanceBar

    private let barHeight: CGFloat = 10
    /// Die Marke steht oben und unten etwas ueber - sonst verschwaende sie am
    /// Ende des Balkens im Gelb.
    private let markHeight: CGFloat = 18

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        Rectangle().fill(Palette.kcal).frame(width: width * bar.eaten)
                        Rectangle().fill(Palette.deficit).frame(width: width * bar.gap)
                        Rectangle().fill(Palette.surplus).frame(width: width * bar.overflow)
                    }
                    .frame(height: barHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    Capsule()
                        .fill(Palette.expenditure)
                        .frame(width: 3, height: markHeight)
                        .offset(x: min(max(width * bar.mark - 1.5, 0), width - 3))
                }
                .frame(width: width, height: markHeight)
            }
            .frame(height: markHeight)
            HStack {
                Text(bar.eatenLabel)
                Spacer(minLength: 8)
                Text(bar.expenditureLabel)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}

/// Die Woche: sieben Balken von einer Nulllinie aus - Defizit nach oben,
/// Ueberschuss nach unten, heute blasser -, darunter die Wochentage, rechts
/// „⌀ 7 T".
private struct EnergyWeek: View {

    let week: EnergyCardModel.Week

    private let plotHeight: CGFloat = 52
    private let barWidth: CGFloat = 14

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 4) {
                GeometryReader { geometry in
                    plot(in: geometry.size)
                }
                .frame(height: plotHeight)
                HStack(spacing: 0) {
                    ForEach(week.bars) { bar in
                        Text(bar.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("⌀ 7 T")
                    .font(.caption)
                Text(week.average)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            .fixedSize()
        }
    }

    private func plot(in size: CGSize) -> some View {
        let column = size.width / CGFloat(max(week.bars.count, 1))
        let zero = size.height * week.zeroLine
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: size.width, height: 1)
                .offset(y: min(max(zero - 0.5, 0), size.height - 1))
            ForEach(Array(week.bars.enumerated()), id: \.element.id) { index, bar in
                if let share = bar.height, share > 0 {
                    let length = size.height * share
                    RoundedRectangle(cornerRadius: 2)
                        .fill((bar.isSurplus ? Palette.surplus : Palette.deficit)
                            .opacity(bar.isProjected ? 0.45 : 1))
                        .frame(width: barWidth, height: length)
                        .offset(x: column * (CGFloat(index) + 0.5) - barWidth / 2,
                                y: bar.isSurplus ? zero : zero - length)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// Halbe Karte: das 7-Tage-Mittel des Gewichts und das Residuum dazu, in der
/// Farbe der Kachel im Gewicht-Tab.
struct WeightHalfCard: View {

    let summary: WeightSummary

    var body: some View {
        let input = TileInput(weight: summary)
        VStack(alignment: .leading, spacing: 4) {
            Text("Gewicht ⌀ 7")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(summary.avg7.kg)
                .font(.title3.weight(.semibold))
            if summary.residual7 != nil {
                Text("Residuum " + summary.residual7.signedKg)
                    .font(.caption)
                    .foregroundStyle(WeightWidget.residual7.tone(input)?.color ?? .secondary)
            }
        }
        .dashboardCard()
    }
}

/// Halbe Karte: was vom kcal-Ziel heute noch uebrig ist, und die Schritte.
struct FoodHalfCard: View {

    let day: DaySummary
    let steps: Int?

    var body: some View {
        let over = day.remaining.kcal < 0
        VStack(alignment: .leading, spacing: 4) {
            Text(over ? "kcal drüber" : "kcal übrig")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(GermanNumber.string(abs(day.remaining.kcal)))
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
            if let steps {
                Text(GermanNumber.string(Double(steps)) + " Schritte")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .dashboardCard()
    }

    /// Wie der Tacho im Essen-Tab: bis 100 kcal drueber orange, darueber rot.
    private var color: Color {
        switch NutritionTone.kcalTone(consumed: day.consumed, targets: day.targets) {
        case .warn: Tone.warn.color
        case .bad:  Tone.bad.color
        default:    .primary
        }
    }
}

/// Logbook: „gestern offen", bis zu drei der staerksten Effekte und der Weg
/// zu allen. Ohne Verhaltensweise und ohne Effekt nur der Weg zum Anlegen.
struct LogbookCard: View {

    let overview: LogbookOverview
    let insights: LogbookInsights?
    /// Tage, deren Speichern im Postausgang wartet - die gelten als gespeichert.
    let queued: Set<CalendarDate>

    private var yesterday: CalendarDate { .today().adding(days: -1) }

    var body: some View {
        let strongest = insights?.strongest ?? []
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(title: "Logbook")
            if !overview.active.isEmpty {
                if overview.day(yesterday) != nil || queued.contains(yesterday) {
                    Label("gestern gespeichert", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Label("gestern offen", systemImage: "circle.dashed")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Tone.warn.color)
                }
            }
            ForEach(strongest) { predictor in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    LogbookSourceIcon(source: predictor.source)
                    Text(predictor.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let effect = LogbookFormat.effectLine(predictor) {
                        Text(effect)
                            .font(.subheadline.monospacedDigit())
                            .fixedSize()
                    }
                }
            }
            if !strongest.isEmpty {
                Text("› alle Effekte")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tint)
            } else if overview.active.isEmpty {
                Text("Verhalten anlegen")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tint)
            }
        }
        .dashboardCard()
    }
}
