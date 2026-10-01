import SwiftUI

// Die Uebersichten der vier Typen (Entwuerfe S. 6, 8, 9, 10). Alle Zahlen
// und Texte kommen fertig vom Dienst.

// MARK: - Streak

struct StreakOverview: View {
    let detail: CohabitDetail
    /// kcal aus Healthy: die Einwilligung (der Schalter der Health-Karte).
    var setHealthyConsent: (Bool) async -> Void = { _ in }

    @Environment(\.meId) private var meId

    var body: some View {
        VStack(spacing: 14) {
            if let week = detail.streak?.week, !week.rows.isEmpty {
                WeekGrid(week: week, color: detail.ref.color, meId: meId)
            }
            HStack(spacing: 10) {
                Tile(value: detail.streak?.fulfillmentRate.map { "\($0)%" } ?? "–", caption: "Erfüllung")
                Tile(value: detail.streak?.record?.short ?? "–",
                     caption: detail.streak?.record?.person.map { "Rekord · \($0.label(me: meId))" } ?? "Rekord")
                Tile(value: "\(detail.seats.used) / \(detail.seats.max)", caption: "Mitglieder")
            }
            // Gleich hoch, auch wenn eine Beschriftung zweizeilig wird.
            .fixedSize(horizontal: false, vertical: true)
            if let group = detail.streak?.group {
                Tile(value: "\(group.current) \(group.unitLabel)", caption: "Gruppen-Streak")
            }
            if let health = detail.health {
                if health.isFromHealthy {
                    HealthyCard(health: health, setConsent: setHealthyConsent)
                } else {
                    HealthCard(health: health, enable: nil)
                }
            }
            RulesCard(rules: detail.rules)
        }
    }
}

/// „Diese Woche": Personen x Mo–So, heute fett, der eigene offene Tag gestrichelt.
struct WeekGrid: View {
    let week: StreakBlock.Week
    let color: PaletteKey
    let meId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Diese Woche")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Ink.ink)
            Grid(horizontalSpacing: 6, verticalSpacing: 8) {
                GridRow {
                    Color.clear.frame(width: 1, height: 1)
                    ForEach(Array(week.days.enumerated()), id: \.offset) { index, day in
                        Text(Formats.weekdayShort(day))
                            .font(.system(size: 13, weight: index == week.todayIndex ? .heavy : .medium))
                            .foregroundStyle(index == week.todayIndex ? Ink.ink : Ink.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
                ForEach(week.rows) { row in
                    GridRow {
                        Text(row.person.shortLabel(me: meId))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Ink.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(width: 58, alignment: .leading)
                        ForEach(Array(row.cells.enumerated()), id: \.offset) { index, cell in
                            WeekCellView(cell: cell, color: color, mine: row.person.id == meId)
                                .accessibilityLabel("\(row.person.label(me: meId)), \(index < week.days.count ? Formats.weekdayShort(week.days[index]) : ""): \(cell.accessibilityText)")
                        }
                    }
                }
            }
        }
        .card(padding: 18)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("weekGrid")
    }
}

struct WeekCellView: View {
    let cell: WeekCell
    let color: PaletteKey
    let mine: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        ZStack {
            switch cell {
            case .done:
                shape.fill(color.colors.accent)
            case .open where mine:
                shape.fill(Color.clear)
                    .overlay(shape.strokeBorder(color.colors.accent, style: StrokeStyle(lineWidth: 2, dash: [4, 3])))
            case .missed:
                shape.fill(Ink.track)
                    .overlay(Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Ink.muted.opacity(0.6)))
            case .paused:
                shape.fill(Ink.track)
                    .overlay(Image(systemName: "pause.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(Ink.muted))
            case .notDue:
                shape.fill(Ink.track.opacity(0.45))
            case .beforeJoin:
                shape.fill(Color.clear)
            case .open, .future:
                shape.fill(Ink.track)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 38)
    }
}

extension WeekCell {
    var accessibilityText: String {
        switch self {
        case .done: "erledigt"
        case .missed: "verpasst"
        case .open: "offen"
        case .paused: "Pause"
        case .future: "kommt noch"
        case .notDue: "nicht fällig"
        case .beforeJoin: "vor dem Beitritt"
        }
    }
}

// MARK: - Abstinenz

struct AbstinenceOverview: View {
    let detail: CohabitDetail

    @Environment(\.meId) private var meId

    var body: some View {
        VStack(spacing: 14) {
            if let block = detail.abstinence {
                VStack(spacing: 0) {
                    ForEach(Array(block.members.enumerated()), id: \.element.id) { index, member in
                        if index > 0 { Divider().overlay(Ink.track) }
                        HStack(spacing: 12) {
                            AvatarView(person: member.person, size: 40, ring: nil)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.person.label(me: meId))
                                    .font(.system(size: 17, weight: .heavy))
                                    .foregroundStyle(Ink.ink)
                                if member.newPersonalRecord {
                                    Text("neuer persönlicher Rekord")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Ink.muted)
                                }
                            }
                            Spacer()
                            Text("\(member.days) T")
                                .font(.system(size: 17, weight: .heavy).monospacedDigit())
                                .foregroundStyle(Ink.ink)
                        }
                        .padding(.vertical, 10)
                    }
                }
                .card(padding: 16)

                if let group = block.group {
                    Tile(value: "\(group.days) \(group.days == 1 ? "Tag" : "Tage")", caption: "Gruppe")
                }

                if !block.series.isEmpty {
                    SeriesCard(series: block.series, color: detail.ref.color)
                }
            }
            RulesCard(rules: detail.rules)
        }
    }
}

/// „Deine Serien": fruehere Serien als Balken, die laufende in Tinte.
struct SeriesCard: View {
    let series: [AbstinenceBlock.Series]
    let color: PaletteKey

    var body: some View {
        let longest = max(1, series.map(\.days).max() ?? 1)
        VStack(alignment: .leading, spacing: 12) {
            Text("Deine Serien")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Ink.ink)
            // Ein Raster, damit die Balken buendig beginnen, auch wenn ein
            // Monatsname laenger ist als „Mai".
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(Array(series.enumerated()), id: \.offset) { _, entry in
                    GridRow {
                        Text(entry.label)
                            .font(.system(size: 15, weight: entry.current ? .heavy : .medium))
                            .foregroundStyle(Ink.ink)
                            .lineLimit(1)
                            .fixedSize()
                        GeometryReader { proxy in
                            Capsule()
                                .fill(entry.current ? Ink.ink : color.colors.accent.opacity(entry.days == longest ? 1 : 0.55))
                                .frame(width: max(10, proxy.size.width * Double(entry.days) / Double(longest)))
                        }
                        .frame(height: 12)
                        Text("\(entry.days) T")
                            .font(.system(size: 14, weight: .heavy).monospacedDigit())
                            .foregroundStyle(Ink.ink)
                            .fixedSize()
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
        }
        .card(padding: 18)
    }
}

// MARK: - Ziel

struct GoalOverview: View {
    let detail: CohabitDetail
    let enableHealth: () -> Void
    var setHealthyConsent: (Bool) async -> Void = { _ in }

    @Environment(\.meId) private var meId

    var body: some View {
        VStack(spacing: 14) {
            if let goal = detail.goal, !goal.contributions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Beiträge")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Ink.ink)
                    ForEach(goal.contributions) { contribution in
                        let mine = contribution.person.id == meId
                        HStack(spacing: 12) {
                            Text(contribution.person.shortLabel(me: meId))
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(Ink.ink)
                                .frame(width: 58, alignment: .leading)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            ProgressTrack(fraction: contribution.fraction,
                                          fill: mine ? Ink.ink : detail.ref.color.colors.accent,
                                          track: Ink.track, height: 10)
                            Text(contribution.valueText)
                                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Ink.ink)
                                .frame(minWidth: 58, alignment: .trailing)
                        }
                    }
                }
                .card(padding: 18)
            }
            if let health = detail.health {
                if health.isFromHealthy {
                    HealthyCard(health: health, setConsent: setHealthyConsent)
                } else {
                    HealthCard(health: health, enable: health.consent ? nil : enableHealth)
                }
            }
            RulesCard(rules: detail.rules)
        }
    }
}

/// „Health-Sync aktiv · zuletzt 14:02 · nur die Schrittzahl wird geteilt".
struct HealthCard: View {
    let health: HealthInfo
    let enable: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Ink.ink)
                .frame(width: 48, height: 48)
                .background(PaletteKey.periwinkle.colors.surface, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(health.consent ? "Health-Sync aktiv" : "Health-Sync aus")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Ink.ink)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.muted)
            }
            Spacer(minLength: 4)
            if let enable {
                Button("Verbinden", action: enable)
                    .buttonStyle(SmallOutlineButtonStyle())
                    .accessibilityIdentifier("healthConnect")
            }
        }
        .card(padding: 16)
    }

    private var subtitle: String {
        var parts: [String] = []
        if health.consent, let last = health.lastSyncAt {
            parts.append("zuletzt " + Formats.relativeStamp(last))
        }
        if let share = health.shareText { parts.append(share) }
        return parts.joined(separator: " · ")
    }
}

/// kcal aus Healthy (`source: HEALTHY`): die Werte holt der Dienst selbst aus
/// dem Kalorienzaehler - statt der Apple-Health-Abfrage nur die Einwilligung
/// als Schalter. Ohne Healthy-Zugang ist er gesperrt.
struct HealthyCard: View {
    let health: HealthInfo
    let setConsent: (Bool) async -> Void

    /// Der gewaehlte Stand, solange der Dienst noch nicht geantwortet hat -
    /// sonst spraenge der Schalter bis dahin zurueck. Lehnt der Dienst ab,
    /// gilt danach wieder sein Stand.
    @State private var pending: Bool?

    var body: some View {
        let access = HealthyAccess.isAvailable
        HStack(spacing: 14) {
            Image(systemName: "fork.knife")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Ink.ink)
                .frame(width: 48, height: 48)
                .background(PaletteKey.mint.colors.surface, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(health.label)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Ink.ink)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.muted)
                }
                if !access {
                    Text("Kein Healthy-Zugang")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Ink.muted)
                        .accessibilityIdentifier("healthyNoAccess")
                }
            }
            Spacer(minLength: 4)
            Toggle(health.label, isOn: Binding(get: { pending ?? health.consent }, set: { value in
                pending = value
                Task {
                    await setConsent(value)
                    pending = nil
                }
            }))
                .labelsHidden()
                .tint(Ink.accent)
                .disabled(!access)
                .accessibilityIdentifier("healthyConsent")
        }
        .card(padding: 16)
    }

    /// „nur die kcal des Tages werden geteilt · zuletzt 14:02".
    private var subtitle: String {
        var parts: [String] = []
        if let share = health.shareText { parts.append(share) }
        if health.consent, let last = health.lastSyncAt {
            parts.append("zuletzt " + Formats.relativeStamp(last))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Challenge

struct ChallengeOverview: View {
    let detail: CohabitDetail
    var setHealthyConsent: (Bool) async -> Void = { _ in }

    @Environment(\.meId) private var meId

    var body: some View {
        VStack(spacing: 14) {
            if let challenge = detail.challenge {
                VStack(spacing: 6) {
                    ForEach(challenge.leaderboard) { entry in
                        LeaderboardRow(entry: entry, mine: entry.person.id == meId,
                                       color: detail.ref.color, name: entry.person.shortLabel(me: meId))
                    }
                }
                .padding(8)
                .background(Ink.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))

                HStack(alignment: .top, spacing: 10) {
                    if let stake = challenge.stake, !stake.isEmpty {
                        Tile(value: stake, caption: "Einsatz", captionFirst: true, valueSize: 16)
                    }
                    Tile(value: challenge.scoringText, caption: "Wertung", captionFirst: true, valueSize: 16)
                }
                .fixedSize(horizontal: false, vertical: true)

                let recurrence = challenge.recurrence != "NONE" ? challenge.recurrenceText ?? "" : ""
                if !challenge.pastRounds.isEmpty || !recurrence.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        // In der ersten Runde gibt es noch keine frueheren -
                        // dann steht nur, dass es weitergeht.
                        Text(challenge.pastRounds.isEmpty
                             ? recurrence.prefix(1).uppercased() + recurrence.dropFirst()
                             : ["Frühere Runden", recurrence].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Ink.muted)
                        if !challenge.pastRounds.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(challenge.pastRounds) { round in
                                    Chip(text: "\(round.label) · \(round.winners.map { $0.shortLabel(me: meId) }.joined(separator: ", "))",
                                         fill: detail.ref.color.colors.surface, weight: .bold)
                                }
                            }
                        }
                    }
                    .card(padding: 16)
                }
            }
            if let health = detail.health {
                if health.isFromHealthy {
                    HealthyCard(health: health, setConsent: setHealthyConsent)
                } else {
                    HealthCard(health: health, enable: nil)
                }
            }
            RulesCard(rules: detail.rules)
        }
    }
}

struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let mine: Bool
    let color: PaletteKey
    let name: String

    var body: some View {
        HStack(spacing: 14) {
            Text("\(entry.rank)")
                .font(.system(size: 17, weight: .heavy).monospacedDigit())
                .frame(width: 20, alignment: .leading)
            Text(name)
                .font(.system(size: 17, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 72, alignment: .leading)
            ProgressTrack(fraction: entry.fraction, fill: color.colors.accent,
                          track: Color.clear, height: 12)
            Text(entry.scoreText)
                .font(.system(size: 17, weight: .heavy).monospacedDigit())
                .frame(minWidth: 28, alignment: .trailing)
        }
        .foregroundStyle(mine ? Ink.onInk : Ink.ink)
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background {
            if mine {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Ink.ink)
            }
        }
    }
}

// MARK: - Gemeinsames

/// Eine Kachel mit Zahl und Beschriftung.
struct Tile: View {
    let value: String
    let caption: String
    var captionFirst = false
    var valueSize: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if captionFirst {
                Text(caption)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.muted)
            }
            Text(value)
                .font(.system(size: valueSize, weight: .black))
                .foregroundStyle(Ink.ink)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            if !captionFirst {
                Text(caption)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.muted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(padding: 14)
    }
}

/// „Regeln" als Chips.
struct RulesCard: View {
    let rules: [String]

    var body: some View {
        if !rules.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Regeln")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Ink.ink)
                FlowLayout(spacing: 8) {
                    ForEach(rules, id: \.self) { rule in
                        Chip(text: rule)
                    }
                }
            }
            .card(padding: 18)
        }
    }
}
