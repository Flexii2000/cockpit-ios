import SwiftUI

/// Die Startseite (Vertrag §5.2.1 und §5.2.2, Entwurf S. 1 und 2).
struct TodayView: View {

    enum Mode: String {
        case dashboard, list
    }

    @State private var store = TodayStore()
    /// Die Wahl gilt je Geraet (Vertrag §5.2.1).
    @AppStorage("today.mode") private var mode: Mode = TodayView.initialMode
    @Environment(\.meId) private var meId

    private var router: Router { Router.shared }
    private var session: Session { Session.shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                if let today = store.today {
                    HStack(alignment: .center) {
                        Text(today.headline)
                            .font(.heading(22))
                            .foregroundStyle(Ink.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .accessibilityIdentifier("todayHeadline")
                        Spacer(minLength: 8)
                        CapsuleSegments(options: [(Mode.dashboard, "Dashboard", nil), (Mode.list, "Liste", nil)],
                                        selection: $mode, height: 44, compact: true)
                    }
                }
                SyncLine()
                if let message = store.errorMessage, store.today == nil {
                    ErrorLine(message: message)
                }
                ForEach(store.nudges) { nudge in
                    NudgeBanner(nudge: nudge,
                                back: { Task { await store.nudgeBack(nudge) } },
                                hide: { Task { await store.hide(nudge) } })
                }
                if let today = store.today {
                    ForEach(today.invitations) { invitation in
                        InvitationCard(invitation: invitation) {
                            router.invitation = .pending(invitation)
                        }
                    }
                    if today.cohabits.isEmpty {
                        EmptyState(text: "Noch keine Co-Habits",
                                   action: ("Co-Habit anlegen", { router.showsCreate = true }))
                    } else if mode == .dashboard {
                        DashboardGrid(cohabits: today.cohabits)
                    } else {
                        TodayList(cohabits: today.cohabits, newPhotos: today.newPhotos)
                    }
                } else if store.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                }
                TabBarSpacer()
            }
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .statusBarScrim()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .refreshable { await store.load() }
        .task { await store.load() }
        .onChange(of: DataBus.shared.revision) { Task { await store.load() } }
        .onChange(of: CohabitSync.shared.flushCount) { Task { await store.load() } }
        .task(id: "tick") {
            // „endet heute", Stupser, neue Fotos: einmal pro Minute nachsehen
            // genuegt (Vertrag §3.4 - gezaehlt wird im Dienst).
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if !Task.isCancelled { await store.load() }
            }
        }
    }

    private var header: some View {
        HStack {
            CohabitLogo(size: 30)
            Spacer()
            Button {
                router.tab = .profile
            } label: {
                if let me = session.me?.person {
                    AvatarView(person: me, size: 46, ring: nil)
                } else {
                    Circle().fill(Ink.ink).frame(width: 46, height: 46)
                }
            }
            .accessibilityLabel("Profil")
        }
        .padding(.top, 8)
    }

    private static var initialMode: Mode {
        #if DEBUG
        if ProcessInfo.processInfo.environment["COCKPIT_TODAY_MODE"] == "list" { return .list }
        #endif
        return .dashboard
    }
}

// MARK: - Dashboard

/// In der Reihenfolge der klassischen Liste (Felix, 2026-10-05): grosse
/// Karten fuer die Streaks, darunter Ziele und Challenges als kleine Karten
/// paarweise, dann Abstinenz und zuletzt die automatischen, wieder gross.
struct DashboardGrid: View {
    let cohabits: [CohabitSummary]

    var body: some View {
        let groups = Dictionary(grouping: cohabits.typeOrder, by: \.ref.todayGroup)
        let small = groups[.goalsAndChallenges] ?? []
        VStack(spacing: 14) {
            ForEach(groups[.streak] ?? []) { summary in
                DashboardCard(summary: summary)
            }
            ForEach(Array(stride(from: 0, to: small.count, by: 2)), id: \.self) { index in
                HStack(alignment: .top, spacing: 14) {
                    SmallCard(summary: small[index])
                    if index + 1 < small.count {
                        SmallCard(summary: small[index + 1])
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
            ForEach((groups[.abstinence] ?? []) + (groups[.automatic] ?? [])) { summary in
                DashboardCard(summary: summary)
            }
        }
    }
}

/// Der Abhak-Knopf einer Karte oder Zeile - mit Uhr, solange ein Haken
/// wartet, und drehend, solange er unterwegs ist.
struct SummaryCheckButton: View {
    let summary: CohabitSummary
    var size: CGFloat = 56
    var style: CheckButtonLabel.Style = .filled

    @Environment(\.meId) private var meId

    var body: some View {
        let checkIns = CheckInController.shared
        let pending = CohabitSync.shared.pendingCheckins.contains(summary.id)
        Button {
            checkIns.start(CheckInTarget(summary: summary, meId: meId))
        } label: {
            if checkIns.busy.contains(summary.id) {
                ProgressView()
                    .tint(style == .filled ? Ink.onInk : Ink.ink)
                    .frame(width: size, height: size)
                    .background(style == .filled ? Ink.ink : Color.clear, in: Circle())
            } else {
                CheckButtonLabel(photo: summary.photoRequired, pending: pending, size: size, style: style)
            }
        }
        .buttonStyle(.plain)
        .disabled(pending)
        .accessibilityLabel(summary.checkInLabel ?? "Abhaken")
        .accessibilityIdentifier("check-\(summary.id)")
    }
}

/// Ob eine Karte einen Abhak-Knopf bekommt: nur, was heute offen ist -
/// laufende Ziele und Abstinenzen hakt man auf ihrer Detailseite ab.
extension CohabitSummary {
    var showsCheckButton: Bool { canCheckIn && status == .open }
}

struct DashboardCard: View {
    let summary: CohabitSummary

    private var colors: PaletteColor { summary.ref.typeColor.colors }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: Route.cohabit(summary.id, .overview)) {
                if summary.ref.type == .abstinence {
                    abstinenceLayout
                } else {
                    streakLayout
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("card-\(summary.id)")
            if summary.showsCheckButton {
                SummaryCheckButton(summary: summary)
                    .padding(16)
            } else if summary.status == .done {
                CheckButtonLabel(photo: false, done: true, size: 44)
                    .padding(18)
                    .accessibilityLabel("Heute erledigt")
            }
        }
    }

    private var typeLine: String { "\(summary.ref.name) · \(summary.ref.type.title)" }

    private var streakLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(typeLine)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(colors.onSurface)
                .lineLimit(1)
                .padding(.trailing, 64)
            HeadlineFigure(headline: summary.headline, valueFont: .figure(64),
                           unitFont: .system(size: 20, weight: .bold))
                .opacity(summary.status == .unavailable ? 0.4 : 1)
            if case .bar(let fraction) = summary.gauge {
                ProgressTrack(fraction: fraction, fill: Ink.ink, track: Ink.surface.opacity(0.7), height: 10)
                    .padding(.bottom, 4)
            }
            HStack(alignment: .center) {
                AvatarStack(people: summary.members, total: summary.memberCount, size: 34)
                Spacer(minLength: 8)
                Text(summary.status == .unavailable ? (summary.unavailableText ?? "") : (summary.subline ?? ""))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Ink.ink)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
        .card(colors.surface, circle: colors.accent.opacity(0.55), circleSize: 150, padding: 18)
    }

    private var abstinenceLayout: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 12) {
                Text(typeLine)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(colors.onSurface)
                    .lineLimit(1)
                AvatarStack(people: summary.members, total: summary.memberCount, size: 34)
            }
            Spacer(minLength: 8)
            HeadlineFigure(headline: summary.headline, valueFont: .figure(56),
                           unitFont: .system(size: 18, weight: .bold))
                .fixedSize()
        }
        .card(colors.surface, circle: colors.accent.opacity(0.45), corner: .bottomLeading,
              circleSize: 110, padding: 18)
    }
}

struct SmallCard: View {
    let summary: CohabitSummary

    private var colors: PaletteColor { summary.ref.typeColor.colors }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink(value: Route.cohabit(summary.id, .overview)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.ref.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(colors.onSurface)
                        .lineLimit(2)
                        .padding(.trailing, summary.showsCheckButton ? 40 : 0)
                    HeadlineFigure(headline: summary.headline, valueFont: .figure(44),
                                   unitFont: .system(size: 15, weight: .bold))
                    if case .bar(let fraction) = summary.gauge {
                        ProgressTrack(fraction: fraction, fill: Ink.ink, track: Ink.surface.opacity(0.7), height: 8)
                            .padding(.vertical, 2)
                    }
                    Text(summary.subline ?? summary.listLine ?? "")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 112, alignment: .topLeading)
                .card(colors.surface, circle: colors.accent.opacity(0.55),
                      corner: summary.ref.type == .goal ? .bottomTrailing : .topTrailing,
                      circleSize: 90, padding: 16)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("card-\(summary.id)")
            if summary.showsCheckButton {
                SummaryCheckButton(summary: summary, size: 40)
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Liste

/// Eine Liste ohne Abschnitte (Felix, 2026-10-05): nach Typ geordnet wie die
/// klassische - Streaks, Ziele und Challenges, Abstinenz, automatische -,
/// darin nach Anlegedatum. Was man abhakt, bleibt an seinem Platz und zeigt
/// den Haken statt des Pfeils.
struct TodayList: View {
    let cohabits: [CohabitSummary]
    let newPhotos: NewPhotos?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(cohabits.typeOrder) { TodayRow(summary: $0) }
            if let newPhotos, newPhotos.count > 0 {
                NewPhotosRow(newPhotos: newPhotos)
                    .padding(.top, 8)
            }
        }
    }
}

struct TodayRow: View {
    let summary: CohabitSummary

    private var colors: PaletteColor { summary.ref.typeColor.colors }

    var body: some View {
        ZStack(alignment: .trailing) {
            NavigationLink(value: Route.cohabit(summary.id, .overview)) {
                HStack(spacing: 12) {
                    HeadlineFigure(headline: summary.headline,
                                   valueFont: .system(size: 24, weight: .black).monospacedDigit(),
                                   unitFont: .system(size: 13, weight: .bold))
                        .frame(width: 84, alignment: .leading)
                        .opacity(summary.status == .unavailable ? 0.4 : 1)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(summary.ref.name)
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(Ink.ink)
                            .lineLimit(1)
                        secondLine
                    }
                    Spacer(minLength: 56)
                }
                .padding(.leading, 18)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                .background(colors.surface, in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("row-\(summary.id)")
            if summary.showsCheckButton {
                SummaryCheckButton(summary: summary, size: 48,
                                   style: summary.photoRequired ? .filled : .outlined)
                    .padding(.trailing, 12)
            } else if summary.status == .done {
                // Wie auf der Karte: erledigt bleibt stehen, mit Haken.
                CheckButtonLabel(photo: false, done: true, size: 44)
                    .padding(.trailing, 14)
                    .allowsHitTesting(false)
                    .accessibilityLabel("Heute erledigt")
                    .accessibilityIdentifier("done-\(summary.id)")
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Ink.ink)
                    .padding(.trailing, 24)
                    .allowsHitTesting(false)
            }
        }
    }

    private var lineText: String {
        summary.status == .unavailable ? (summary.unavailableText ?? "") : (summary.listLine ?? "")
    }

    @ViewBuilder
    private var secondLine: some View {
        switch summary.gauge {
        case .bar(let fraction):
            VStack(alignment: .leading, spacing: 6) {
                if !lineText.isEmpty {
                    Text(lineText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.ink)
                        .lineLimit(2)
                }
                ProgressTrack(fraction: fraction, fill: Ink.ink, track: Ink.surface, height: 8)
                    .frame(maxWidth: 220)
            }
        case .weekDots(let done, let goal):
            HStack(spacing: 6) {
                WeekDots(done: done, goal: goal)
                Text(lineText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.ink)
                    .lineLimit(2)
            }
        case .none:
            Text(lineText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.ink)
                .lineLimit(2)
        }
    }
}

/// „●●○" - erledigt gegen Soll im laufenden Zeitraum.
struct WeekDots: View {
    let done: Int
    let goal: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<goal, id: \.self) { index in
                Circle()
                    .fill(index < done ? Ink.ink : Color.clear)
                    .overlay(Circle().strokeBorder(Ink.ink, lineWidth: 1.4))
                    .frame(width: 9, height: 9)
            }
        }
        .accessibilityLabel("\(done) von \(goal)")
    }
}

/// „2 neue Beweisfotos in der Timeline".
struct NewPhotosRow: View {
    let newPhotos: NewPhotos

    var body: some View {
        Button {
            Router.shared.tab = .timeline
        } label: {
            HStack(spacing: 14) {
                HStack(spacing: -14) {
                    ForEach(Array(newPhotos.photoIds.prefix(2)), id: \.self) { id in
                        PhotoView(id: id, size: .thumb, placeholder: PaletteKey.peach.colors.surface)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Ink.surface, lineWidth: 2))
                    }
                }
                Text("\(Text(newPhotos.count == 1 ? "1 neues Beweisfoto" : "\(newPhotos.count) neue Beweisfotos").fontWeight(.heavy)) in der Timeline")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Ink.ink)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Ink.ink)
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("newPhotos")
    }
}

/// „Max hat dich angestupst: Heute noch kochen?" + „Zurückstupsen".
struct NudgeBanner: View {
    let nudge: Nudge
    let back: () -> Void
    let hide: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(person: nudge.from, size: 40, ring: nil)
            Text("\(Text(nudge.from.shortLabel(me: nil)).fontWeight(.heavy)) hat dich angestupst: \(nudge.text)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: back) {
                Text("Zurückstupsen")
                    .lineLimit(1)
                    .fixedSize()
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color(hex: 0x1C1B2E))
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(.white, in: Capsule())
            .accessibilityIdentifier("nudgeBack-\(nudge.id)")
        }
        .padding(16)
        .background(Color(hex: 0x5B3FD9), in: RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
        .contextMenu {
            Button("Ausblenden", systemImage: "eye.slash", action: hide)
        }
    }
}

/// Eine offene Einladung - ein Tipp oeffnet den Einladungsdialog.
struct InvitationCard: View {
    let invitation: InvitationView
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                AvatarView(person: invitation.from, size: 40, ring: nil)
                Text("\(Text(invitation.from.shortLabel(me: nil)).fontWeight(.heavy)) lädt dich zu „\(invitation.cohabit.ref.name)“ ein")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Ink.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Ink.ink)
            }
            .card(invitation.cohabit.ref.typeColor.colors.surface,
                  circle: invitation.cohabit.ref.typeColor.colors.accent.opacity(0.5), circleSize: 70, padding: 14)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("invitation-\(invitation.id)")
    }
}
