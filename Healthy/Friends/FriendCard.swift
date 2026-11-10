import SwiftUI

/// Ein Freund (Vertrag §10.4): Name, die drei Punkte von heute und der
/// Stupser; darunter die Serien mit den zwei Marken fuer heute (ich, Freund);
/// darunter die Schritte der Woche als Balkenpaare. Welche Seite welche ist,
/// steht einmal darueber: „Ich“ und der Anfangsbuchstabe des Freundes - wie in
/// der Android-App, damit beide Handys dasselbe zeigen.
struct FriendCard: View {

    let friend: Friend
    let today: CalendarDate
    let isNudging: Bool
    let onNudge: () -> Void

    /// Die Spalte einer Marke - Kopf und Marken stehen so untereinander.
    private static let markSlot: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(friend.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                TodayDots(today: friend.today)
                Button(action: onNudge) {
                    Image(systemName: "hand.wave")
                        .font(.body.weight(.medium))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(friend.nudge.allowed && !isNudging ? Color.accentColor : Color.secondary.opacity(0.45))
                .disabled(!friend.nudge.allowed || isNudging)
                .accessibilityLabel("Anstupsen")
                .accessibilityIdentifier("nudge-\(friend.id)")
            }
            let streaks = friend.shownStreaks
            if !streaks.isEmpty {
                VStack(spacing: 8) {
                    // Wer welche Marke ist, einmal ueber den Spalten.
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        markHeader(FriendsFormat.me)
                        markHeader(FriendsFormat.initial(friend.name))
                    }
                    ForEach(streaks) { streak in
                        StreakRow(streak: streak, slot: Self.markSlot)
                    }
                }
            }
            if let week = FriendsStepsWeek(friend.steps, today: today) {
                Divider()
                StepsWeek(week: week, friend: FriendsFormat.initial(friend.name))
            }
        }
        .dashboardCard()
        // Keine Kennung an der Karte selbst: SwiftUI reichte sie an alles darin
        // weiter und ueberschriebe die des Stupser-Knopfs und der Serien.
    }

    private func markHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(width: Self.markSlot)
    }
}

/// Heute auf einen Blick, ohne Zahlen: getrackt (gefuellt oder leer), Recovery
/// und Strain in der Farbe ihres Bands - ohne Wert grau.
private struct TodayDots: View {

    let today: FriendToday

    private let size: CGFloat = 10

    var body: some View {
        HStack(spacing: 6) {
            if today.tracked {
                Circle().fill(Color.primary).frame(width: size, height: size)
            } else {
                Circle().strokeBorder(Color.primary.opacity(0.5), lineWidth: 1.5).frame(width: size, height: size)
            }
            Circle().fill(recovery ?? Self.grey).frame(width: size, height: size)
            Circle().fill(strain ?? Self.grey).frame(width: size, height: size)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([
            today.tracked ? "heute getrackt" : "heute noch nicht getrackt",
            recovery != nil ? "Recovery da" : "keine Recovery",
            strain != nil ? "Strain da" : "kein Strain",
        ].joined(separator: ", "))
    }

    private static let grey = Color.secondary.opacity(0.3)

    private var recovery: Color? {
        switch today.recoveryBand {
        case .green, .yellow, .red: RecoveryFormat.tone(today.recoveryBand).gradient.last
        default: nil
        }
    }

    private var strain: Color? {
        switch today.strainBand {
        case .light, .moderate, .high, .allOut: Palette.strainBand(today.strainBand)
        default: nil
        }
    }
}

/// Eine Serie: Name und Rekord, der Stand („12 Tage“), die zwei Marken fuer heute.
private struct StreakRow: View {

    let streak: FriendStreak
    let slot: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(FriendsFormat.label(streak.type) ?? "")
                    .font(.subheadline)
                    .lineLimit(1)
                Text(FriendsFormat.record(streak.best))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(FriendsFormat.days(streak.current))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                // Eine Serie, die heute zu reissen droht, faellt auf - ohne ein Wort dazu.
                .foregroundStyle(streak.atRisk ? Tone.warn.color : Color.primary)
                .lineLimit(1)
                .padding(.horizontal, 10)
            StreakMark(side: streak.me, who: "ich").frame(width: slot)
            StreakMark(side: streak.friend, who: "Freund").frame(width: slot)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("streak-\(streak.type.rawValue)")
    }
}

/// Wie eine Seite heute steht: erfuellt, offen, verfehlt (nur Kalorienziel)
/// oder unbekannt.
private struct StreakMark: View {

    let side: StreakSide
    let who: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 18))
            .foregroundStyle(color)
            .accessibilityLabel("\(who) heute \(word)")
    }

    private var symbol: String {
        switch side {
        case .done:    "checkmark.circle.fill"
        case .open:    "circle"
        case .failed:  "xmark.circle.fill"
        case .unknown: "minus.circle"
        }
    }

    private var color: Color {
        switch side {
        case .done:    MacroTone.good.gradient.last ?? .green
        case .open:    .secondary
        case .failed:  MacroTone.bad.gradient.last ?? .red
        case .unknown: Color.secondary.opacity(0.5)
        }
    }

    private var word: String {
        switch side {
        case .done:    "erfüllt"
        case .open:    "offen"
        case .failed:  "verfehlt"
        case .unknown: "unbekannt"
        }
    }
}

/// Die Schritte der Woche als Balkenpaare je Tag, darueber die Summen als
/// Legende; darunter, wo es sie gibt, die Vorwoche.
private struct StepsWeek: View {

    let week: FriendsStepsWeek
    let friend: String

    private static let mine = Color.accentColor
    private static let theirs = Color.secondary.opacity(0.6)
    private let plotHeight: CGFloat = 44
    private let barWidth: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Schritte").font(.subheadline)
                Spacer(minLength: 8)
                total(Self.mine, "\(FriendsFormat.me) \(week.me)")
                total(Self.theirs, "\(friend) \(week.friend)")
            }
            VStack(spacing: 4) {
                GeometryReader { geometry in
                    plot(in: geometry.size)
                }
                .frame(height: plotHeight)
                HStack(spacing: 0) {
                    ForEach(week.days) { day in
                        Text(day.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .accessibilityHidden(true)
            if let lastWeek = week.lastWeek {
                Text("Vorwoche \(lastWeek)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func total(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func plot(in size: CGSize) -> some View {
        let column = size.width / CGFloat(max(week.days.count, 1))
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: size.width, height: 1)
                .offset(y: size.height - 1)
            ForEach(Array(week.days.enumerated()), id: \.element.id) { index, day in
                let center = column * (CGFloat(index) + 0.5)
                if let share = day.me {
                    bar(share, color: Self.mine, x: center - barWidth - 1, in: size.height)
                }
                if let share = day.friend {
                    bar(share, color: Self.theirs, x: center + 1, in: size.height)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func bar(_ share: Double, color: Color, x: CGFloat, in height: CGFloat) -> some View {
        // Mindestens ein duenner Strich - sonst saehe ein ruhiger Tag aus wie einer ohne Wert.
        let length = max(CGFloat(share) * height, 2)
        return RoundedRectangle(cornerRadius: min(2, length / 2))
            .fill(color)
            .frame(width: barWidth, height: length)
            .offset(x: x, y: height - length)
    }
}
