import AppIntents
import SwiftUI
import WidgetKit

// Die Kachel-Ansichten (Entwurf S. 18). Liegen in CohabitShared, damit die
// App sie in ihrer Vorschau (COCKPIT_TAB=widget) mit echten Daten zeigen kann.

/// „Stand 14:02" - wenn der Stand nicht frisch ist.
private struct StaleNote: View {
    let date: Date?

    var body: some View {
        if let date {
            Text("Stand \(Self.format(date))")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Ink.muted)
        }
    }

    static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm" : "dd.MM., HH:mm"
        return formatter.string(from: date)
    }
}

/// „Kein Zugang" / „Nicht erreichbar".
struct WidgetHint: View {
    let state: CohabitWidgetState

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: state == .noAccess ? "link" : "wifi.slash")
                .font(.title3)
            Text(state == .noAccess ? "Kein Zugang" : "Nicht erreichbar")
                .font(.caption)
        }
        .foregroundStyle(Ink.muted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Klein

/// Ein Co-Habit in seiner Farbe: Name, Kennzahl, Unterzeile, rechts unten der
/// Knopf - Haken (direkt abhaken) oder Kamera (oeffnet das Beweisfoto-Blatt).
struct SmallCohabitWidgetView: View {
    let item: WidgetData.Item
    var staleSince: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.ref.name)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Ink.ink)
                .lineLimit(1)
                .padding(.trailing, 28)
            Text(item.value)
                .font(.figure(46))
                .foregroundStyle(Ink.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, 4)
            Text(item.sub)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Ink.ink)
                .lineLimit(2)
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                StaleNote(date: staleSince)
                Spacer(minLength: 0)
                button
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var button: some View {
        if item.quickCheckIn {
            Button(intent: CheckInIntent(cohabitId: item.ref.id)) {
                circle(symbol: "checkmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Abhaken")
        } else if item.photoRequired && item.status == .open,
                  let url = URL(string: "cohabit://cohabit/\(item.ref.id)/checkin") {
            Link(destination: url) {
                circle(symbol: "camera")
            }
            .accessibilityLabel("Beweisfoto & abhaken")
        } else if item.status == .done {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Ink.ink.opacity(0.5))
                .frame(width: 40, height: 40)
        }
    }

    private func circle(symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Ink.onInk)
            .frame(width: 42, height: 42)
            .background(Ink.ink, in: Circle())
    }
}

/// Der Hintergrund der kleinen Kachel: Flaeche in der Co-Habit-Farbe mit Kreis.
struct SmallCohabitBackground: View {
    let color: PaletteKey

    var body: some View {
        ZStack {
            color.colors.surface
            CornerCircle(color: color.colors.accent.opacity(0.6), corner: .topTrailing, size: 80, inset: 0.3)
        }
    }
}

// MARK: - Mittel

/// „Heute · 2 offen": Farbpunkt, Name, rechts „offen" oder die Kennzahl.
struct TodayWidgetView: View {
    let data: WidgetData
    var staleSince: Date?
    var rows = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Heute")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Ink.ink)
                Spacer()
                Text(data.openCount == 1 ? "1 offen" : "\(data.openCount) offen")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Ink.muted)
            }
            .padding(.bottom, 6)
            if data.cohabits.isEmpty {
                Spacer()
                Text("Noch keine Co-Habits")
                    .font(.caption)
                    .foregroundStyle(Ink.muted)
                Spacer()
            }
            ForEach(Array(data.cohabits.prefix(rows).enumerated()), id: \.element.id) { index, item in
                if index > 0 { Spacer(minLength: 2) }
                Link(destination: URL(string: "cohabit://cohabit/\(item.ref.id)")!) {
                    TodayWidgetRow(item: item)
                }
            }
            Spacer(minLength: 0)
            StaleNote(date: staleSince)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct TodayWidgetRow: View {
    let item: WidgetData.Item

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(item.ref.typeColor.colors.accent).frame(width: 9, height: 9)
            Text(item.ref.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            if item.status == .open {
                Text(item.statusText)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Ink.onInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Ink.ink, in: Capsule())
            } else {
                Text(item.statusText)
                    .font(.system(size: 12, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Gross

/// Challenge-Rangliste, Teamziel, offener Streak.
struct BoardWidgetView: View {
    let data: WidgetData
    var staleSince: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let challenge = data.challenge {
                Link(destination: URL(string: "cohabit://cohabit/\(challenge.ref.id)")!) {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(["Challenge", challenge.endsText].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Ink.ink)
                            Text(challenge.ref.name)
                                .font(.system(size: 20, weight: .heavy))
                                .foregroundStyle(Ink.ink)
                                .lineLimit(1)
                        }
                        VStack(spacing: 6) {
                            ForEach(challenge.leaderboard.prefix(3)) { entry in
                                ChallengeWidgetRow(entry: entry, color: challenge.ref.typeColor,
                                                   best: challenge.leaderboard.map(\.score).max() ?? 1)
                            }
                        }
                        .padding(10)
                        .background(Ink.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            } else {
                TodayWidgetView(data: data, staleSince: nil, rows: 5)
                    .frame(maxHeight: 150)
            }
            if let goal = data.teamGoal {
                Link(destination: URL(string: "cohabit://cohabit/\(goal.ref.id)")!) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(goal.ref.name) · Team")
                                .font(.system(size: 13, weight: .heavy))
                                .lineLimit(1)
                            Spacer()
                            Text("\(goal.percent)%")
                                .font(.figure(18))
                        }
                        .foregroundStyle(Ink.ink)
                        WidgetBar(fraction: Double(goal.percent) / 100)
                    }
                    .padding(10)
                    .background(goal.ref.typeColor.colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            if let streak = data.openStreak {
                Link(destination: URL(string: "cohabit://cohabit/\(streak.ref.id)")!) {
                    HStack {
                        Text(streak.text)
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Ink.ink)
                            .lineLimit(1)
                        Spacer()
                        Text("offen")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Ink.onInk)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Ink.ink, in: Capsule())
                    }
                    .padding(10)
                    .background(streak.ref.typeColor.colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            Spacer(minLength: 0)
            StaleNote(date: staleSince)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Ein Balken ohne Geometrie-Tricks - Kacheln rendern statisch.
private struct WidgetBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.surface)
                Capsule().fill(Ink.ink).frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 8)
    }
}

struct ChallengeWidgetRow: View {
    let entry: WidgetData.ChallengeEntry
    let color: PaletteKey
    let best: Double

    var body: some View {
        HStack(spacing: 8) {
            Text("\(entry.rank)")
                .font(.system(size: 13, weight: .heavy).monospacedDigit())
                .frame(width: 14, alignment: .leading)
            // Vorname - „Lena Kraus" passte nur als „Lena…" in die Spalte.
            Text(entry.me ? "Du" : (entry.name.split(separator: " ").first.map(String.init) ?? entry.name))
                .font(.system(size: 13, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 58, alignment: .leading)
            GeometryReader { proxy in
                Capsule()
                    .fill(entry.me ? Ink.ink : color.colors.accent)
                    .frame(width: max(8, proxy.size.width * (best > 0 ? entry.score / best : 0)))
            }
            .frame(height: 8)
            Text(Self.score(entry.score))
                .font(.system(size: 13, weight: .heavy).monospacedDigit())
        }
        .foregroundStyle(Ink.ink)
    }

    nonisolated static func score(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Sperrbildschirm

/// Rund: Kennzahl mit Einheitskuerzel und Name („6W", „Laufen").
struct CircularCohabitView: View {
    let item: WidgetData.Item

    var body: some View {
        ZStack {
            Circle().strokeBorder(lineWidth: 4)
            VStack(spacing: -1) {
                Text(Self.compact(item))
                    .font(.system(size: 17, weight: .heavy).monospacedDigit())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(item.ref.name)
                    .font(.system(size: 8, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 6)
        }
        .widgetAccentable()
    }

    /// „6W", „23T", „#2", „68%". Ein Kuerzel der Einheit ist Formatieren,
    /// kein Rechnen.
    nonisolated static func compact(_ item: WidgetData.Item) -> String {
        let value = item.value
        guard !item.unit.isEmpty, value.allSatisfy({ $0.isNumber }) else { return value }
        let unit = item.unit.lowercased()
        let short = unit.hasPrefix("mal") ? "×" : String(item.unit.prefix(1)).uppercased()
        return value + short
    }
}

/// Rechteckig: die Challenge - Name, „Platz 2", wann sie endet.
struct ChallengeRectView: View {
    let challenge: WidgetData.ChallengeBoard

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(challenge.ref.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text(challenge.myRank.map { "Platz \($0)" } ?? "–")
                .font(.system(size: 22, weight: .heavy))
                .widgetAccentable()
            if let ends = challenge.endsText {
                Text(ends)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Beispieldaten

extension WidgetData {
    /// Fuer die Galerie und den Platzhalter - die Werte aus dem Entwurf.
    static let sample = WidgetData(
        generatedAt: nil, openCount: 2,
        cohabits: [
            Item(ref: CohabitRef(id: "s1", name: "Laufen", color: .peach, type: .streak), value: "6", unit: "Wochen",
                 sub: "Wochen · 2/3", status: .open, statusText: "offen", photoRequired: true, quickCheckIn: false),
            Item(ref: CohabitRef(id: "c1", name: "Wer kocht öfter?", color: .butter, type: .challenge), value: "#2",
                 unit: "Platz", sub: "noch 2 bis Lena", status: .open, statusText: "offen", photoRequired: false,
                 quickCheckIn: true),
            Item(ref: CohabitRef(id: "a1", name: "Ohne Zucker", color: .mint, type: .abstinence), value: "23",
                 unit: "Tage", sub: "Tage · Rekord 41", status: .running, statusText: "23 T", photoRequired: false,
                 quickCheckIn: false),
            Item(ref: CohabitRef(id: "g1", name: "100k Schritte", color: .periwinkle, type: .goal), value: "68%",
                 unit: "", sub: "Teamziel", status: .running, statusText: "68%", photoRequired: false,
                 quickCheckIn: false),
        ],
        challenge: ChallengeBoard(
            ref: CohabitRef(id: "c1", name: "Wer kocht öfter?", color: .butter, type: .challenge),
            endsText: "endet heute", myRank: 2,
            leaderboard: [ChallengeEntry(rank: 1, name: "Lena", score: 9, me: false),
                          ChallengeEntry(rank: 2, name: "Du", score: 7, me: true),
                          ChallengeEntry(rank: 3, name: "Max", score: 5, me: false)]),
        teamGoal: TeamGoal(ref: CohabitRef(id: "g1", name: "100k Schritte", color: .periwinkle, type: .goal), percent: 68),
        openStreak: OpenStreak(ref: CohabitRef(id: "s1", name: "Laufen", color: .peach, type: .streak),
                               text: "Laufen · 6 Wochen"))
}
