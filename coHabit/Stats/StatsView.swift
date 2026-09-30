import SwiftUI

@MainActor
@Observable
final class StatsStore {
    private(set) var stats: Stats?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    var range: StatsRange = StatsStore.initialRange {
        didSet { if range != oldValue { Task { await load() } } }
    }

    func load() async {
        isLoading = stats == nil
        defer { isLoading = false }
        do {
            stats = try await Session.shared.api().get("/stats", query: [
                URLQueryItem(name: "range", value: range.rawValue),
                URLQueryItem(name: "anchor", value: CalendarDate.today().iso),
            ])
            errorMessage = nil
        } catch {
            if await Session.shared.handle(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    private static var initialRange: StatsRange {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["COCKPIT_STATS_RANGE"] {
        case "week": return .week
        case "year": return .year
        default: break
        }
        #endif
        return .month
    }
}

/// Die Statistik (Entwurf S. 4): Umschalter, Erfuellungsquote, laengste
/// Serie, Heatmap, Fortschritt je Co-Habit.
struct StatsView: View {

    @State private var store = StatsStore()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Text("Statistik")
                        .font(.heading(34))
                        .foregroundStyle(Ink.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    CapsuleSegments(options: StatsRange.allCases.map { ($0, $0.title, nil) },
                                    selection: $store.range, height: 44, compact: true)
                }
                .padding(.top, 8)
                SyncLine()
                if let message = store.errorMessage, store.stats == nil {
                    ErrorLine(message: message)
                }
                if let stats = store.stats {
                    HStack(alignment: .top, spacing: 12) {
                        rateCard(stats)
                        longestCard(stats)
                    }
                    HeatmapCard(stats: stats)
                    ForEach(stats.cohabits) { row in
                        HStack(spacing: 12) {
                            Circle().fill(row.ref.color.colors.accent).frame(width: 12, height: 12)
                            Text(row.ref.name)
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(Ink.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .frame(width: 130, alignment: .leading)
                            ProgressTrack(fraction: row.fraction, fill: Ink.ink, track: Ink.track, height: 8)
                            Text(row.progressText)
                                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Ink.ink)
                                .frame(minWidth: 44, alignment: .trailing)
                        }
                        .card(padding: 16)
                    }
                } else if store.isLoading {
                    ProgressView().padding(.vertical, 60)
                }
                TabBarSpacer()
            }
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .refreshable { await store.load() }
        .task { await store.load() }
        .onChange(of: DataBus.shared.revision) { Task { await store.load() } }
    }

    private func rateCard(_ stats: Stats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Erfüllungsquote")
                .font(.system(size: 15, weight: .bold))
            Text(stats.fulfillmentRate.map { "\($0)%" } ?? "–")
                .font(.figure(50))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(stats.label)
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .card(Color(hex: 0x5B3FD9), circle: .white.opacity(0.1), circleSize: 110, padding: 18)
        .accessibilityIdentifier("statsRate")
    }

    private func longestCard(_ stats: Stats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Längste Serie")
                .font(.system(size: 15, weight: .bold))
            Text(stats.longestStreak?.short ?? "–")
                .font(.figure(40))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(stats.longestStreak?.cohabit.name ?? "")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Ink.muted)
                .lineLimit(1)
        }
        .foregroundStyle(Ink.ink)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .card(padding: 18)
    }
}

/// Die Heatmap: Monat als Kalender Mo–So, Woche als Zeile, Jahr als zwoelf
/// Monatsbloecke (Vertrag §5.2.4). Die Stufe 0–4 kommt vom Dienst.
struct HeatmapCard: View {
    let stats: Stats

    private var byDate: [CalendarDate: Stats.HeatDay] {
        Dictionary(stats.heatmap.days.map { ($0.date, $0) }, uniquingKeysWith: { $1 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(stats.label)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Ink.ink)
                Spacer()
                Text("erledigte Haken pro Tag")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.muted)
            }
            switch stats.range {
            case .year: yearGrid
            case .week: weekRow
            case .month: monthGrid
            }
            HStack(spacing: 6) {
                Spacer()
                Text("weniger").font(.system(size: 13, weight: .medium)).foregroundStyle(Ink.muted)
                ForEach(1...4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Self.color(level: level))
                        .frame(width: 16, height: 16)
                }
                Text("mehr").font(.system(size: 13, weight: .medium)).foregroundStyle(Ink.muted)
            }
        }
        .card(padding: 18)
        .accessibilityIdentifier("heatmap")
    }

    static func color(level: Int) -> Color {
        switch level {
        case ..<1: Ink.track
        case 1: Color(hex: 0x5B3FD9).opacity(0.22)
        case 2: Color(hex: 0x5B3FD9).opacity(0.45)
        case 3: Color(hex: 0x5B3FD9).opacity(0.72)
        default: Color(hex: 0x5B3FD9)
        }
    }

    private static let weekdayLetters = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    /// Wochentag des Tages, 0 = Montag.
    private static func weekdayIndex(_ day: CalendarDate) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let weekday = calendar.component(.weekday, from: day.startOfDay())
        return (weekday + 5) % 7
    }

    private var monthGrid: some View {
        let first = stats.heatmap.from
        let last = stats.heatmap.to
        var days: [CalendarDate] = []
        var day = first
        while day <= last && days.count < 42 {
            days.append(day)
            day = day.adding(days: 1)
        }
        let offset = Self.weekdayIndex(first)
        let cells: [CalendarDate?] = Array(repeating: nil, count: offset) + days.map { Optional($0) }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Self.weekdayLetters, id: \.self) { letter in
                Text(letter)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.muted)
            }
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day, showsNumber: true)
                } else {
                    Color.clear.aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    private var weekRow: some View {
        var days: [CalendarDate] = []
        var day = stats.heatmap.from
        while day <= stats.heatmap.to && days.count < 7 {
            days.append(day)
            day = day.adding(days: 1)
        }
        return HStack(spacing: 8) {
            ForEach(days, id: \.self) { day in
                VStack(spacing: 6) {
                    Text(Formats.weekdayShort(day))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.muted)
                    dayCell(day, showsNumber: true)
                }
            }
        }
    }

    private var yearGrid: some View {
        let year = stats.heatmap.from.year
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(1...12, id: \.self) { month in
                monthBlock(year: year, month: month)
            }
        }
    }

    private func monthBlock(year: Int, month: Int) -> some View {
        let first = CalendarDate(year: year, month: month, day: 1)
        var days: [CalendarDate] = []
        var day = first
        while day.month == month && days.count < 31 {
            days.append(day)
            day = day.adding(days: 1)
        }
        let cells: [CalendarDate?] = Array(repeating: nil, count: Self.weekdayIndex(first)) + days.map { Optional($0) }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        let name = Formats.monthShort(month)
        return VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Ink.ink)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(day.map { Self.color(level: byDate[$0]?.level ?? 0) } ?? .clear)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    private func dayCell(_ day: CalendarDate, showsNumber: Bool) -> some View {
        let entry = byDate[day]
        let level = entry?.level ?? 0
        let future = day > CalendarDate.today()
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(future ? Color.clear : Self.color(level: level))
            if showsNumber {
                Text("\(day.day)")
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(level >= 3 ? Color.white : Ink.ink)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("\(day.day).: \(entry?.count ?? 0)")
    }
}

extension Formats {
    static func monthShort(_ month: Int) -> String {
        let names = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]
        return names[max(0, min(11, month - 1))]
    }
}
