import SwiftUI

// Die Kennzahl eines Co-Habits ausgeschrieben (Felix, 2026-10-05): nie die
// Kurzform des Dienstes („3 Wo.", „17 T"), sondern die Zahl gross und die
// Einheit klein daneben - „17" „Tage", „3" „Wochen", „#2" „dein Platz".

extension Headline {
    /// Die Einheit in ganzen Worten - `nil`, wenn es keine gibt (Ziel: „68%").
    var spelledUnit: String? {
        let unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return unit.isEmpty ? nil : unit
    }

    /// Fuer VoiceOver: „17 Tage", „68%".
    var spokenText: String {
        [value, spelledUnit].compactMap { $0 }.joined(separator: " ")
    }
}

/// Zahl gross, Einheit klein auf derselben Grundlinie - passt beides nicht
/// nebeneinander, steht die Einheit darunter.
struct HeadlineFigure: View {
    let headline: Headline
    let valueFont: Font
    let unitFont: Font
    var color: Color = Ink.ink

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                value
                unit
            }
            VStack(alignment: .leading, spacing: 0) {
                value
                unit
            }
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(headline.spokenText)
    }

    private var value: some View {
        Text(headline.value)
            .font(valueFont)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    @ViewBuilder
    private var unit: some View {
        if let unit = headline.spelledUnit {
            Text(unit)
                .font(unitFont)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
