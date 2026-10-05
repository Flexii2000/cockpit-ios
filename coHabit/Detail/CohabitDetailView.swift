import SwiftUI

/// Die Detailseite eines Co-Habits: Kopf in seiner Farbe, Umschalter
/// „Übersicht | Chat", unten der Abhak-Knopf (Vertrag §5.2.6–10).
struct CohabitDetailView: View {

    let cohabitId: String

    @State private var store: CohabitDetailStore
    @State private var section: DetailSection
    @State private var sheet: DetailSheet?
    @State private var confirmLeave = false
    @State private var confirmDelete = false
    @State private var dialogDismissed: Set<String> = []
    /// Hoehe des Kopfs und was gerade unter der Statusleiste liegt.
    @State private var headerHeight: CGFloat = 0
    @State private var scrim = Scrim.none

    /// Der Streifen hinter der Statusleiste: in Ruhe keiner (der Kopf reicht
    /// mit seinem Kreis bis oben), beim Scrollen in der Farbe des Kopfs,
    /// sobald der ganz durch ist in der des Hintergrunds.
    private enum Scrim: Equatable { case none, header, page }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.meId) private var meId

    init(cohabitId: String, initialSection: DetailSection) {
        self.cohabitId = cohabitId
        _store = State(initialValue: CohabitDetailStore(cohabitId: cohabitId))
        _section = State(initialValue: initialSection)
    }

    enum DetailSheet: String, Identifiable {
        case edit, members, pauses, invite, notifications, entries
        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if let detail = store.detail {
                content(detail)
            } else if let message = store.errorMessage {
                VStack(spacing: 16) {
                    backRow
                    ErrorLine(message: message)
                    Spacer()
                }
                .padding(Metrics.gutter)
            } else {
                VStack {
                    backRow.padding(Metrics.gutter)
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .screenBackground()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task { await store.load() }
        .onChange(of: DataBus.shared.revision) { Task { await store.load() } }
        .onChange(of: CohabitSync.shared.flushCount) { Task { await store.load() } }
        .onChange(of: store.isGone) { _, gone in if gone { dismiss() } }
        .onChange(of: store.detail?.id) { _, id in
            // cohabit://cohabit/{id}/checkin: das Abhaken oeffnen, sobald bekannt ist, wie.
            guard let id, Router.shared.pendingCheckIn == id, let detail = store.detail else { return }
            Router.shared.pendingCheckIn = nil
            if detail.summary.canCheckIn {
                CheckInController.shared.start(CheckInTarget(detail: detail, meId: meId))
            }
        }
        .task(id: "tick") {
            // „endet in 9 Std. 41 Min." rechnet der Dienst - einmal pro Minute holen.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if !Task.isCancelled, section == .overview { await store.load() }
            }
        }
    }

    private var backRow: some View {
        HStack {
            Button { dismiss() } label: { CircleButtonLabel(systemImage: "chevron.left") }
                .accessibilityLabel("Zurück")
            Spacer()
        }
    }

    @ViewBuilder
    private func content(_ detail: CohabitDetail) -> some View {
        // Der Kopf reicht bis unter die Statusleiste; wie hoch die ist,
        // haengt am Geraet (Dynamic Island, Home-Taste) - daher gemessen.
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top
            // Wie weit man scrollen muss, bis der Kopf unter der Leiste durch ist.
            let headerLeft = headerHeight - top
            ZStack {
            VStack(spacing: 0) {
                if section == .overview {
                    ScrollView {
                        VStack(spacing: 14) {
                            DetailHeader(detail: detail, section: $section, compact: false, topInset: top,
                                         back: { dismiss() }, menu: { menu(detail) })
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                            SyncLine()
                                .padding(.horizontal, Metrics.gutter)
                            overview(detail)
                                .padding(.horizontal, Metrics.gutter)
                            Color.clear.frame(height: 90)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .ignoresSafeArea(edges: .top)
                    .onScrollGeometryChange(for: Scrim.self) { geometry in
                        let offset = geometry.contentOffset.y + geometry.contentInsets.top
                        if offset <= 1 { return .none }
                        return headerLeft > 0 && offset > headerLeft ? .page : .header
                    } action: { _, phase in
                        withAnimation(.easeOut(duration: 0.15)) { scrim = phase }
                    }
                    .refreshable { await store.load() }
                    .safeAreaInset(edge: .bottom) { bottomAction(detail) }
                } else {
                    // Kopf und Chat gemeinsam ab Bildschirmoberkante: ignoriert nur
                    // der Kopf die Leiste, haelt der Stapel ihm trotzdem die volle
                    // Hoehe ab der sicheren Zone frei - eine Luecke von Leistenhoehe.
                    VStack(spacing: 0) {
                        DetailHeader(detail: detail, section: $section, compact: true, topInset: top,
                                     back: { dismiss() }, menu: { menu(detail) })
                        ChatView(detail: detail)
                    }
                    .ignoresSafeArea(edges: .top)
                }
            }
            // Am VStack, nicht an der ScrollView: der liegt innerhalb der
            // sicheren Zone, so reicht der Streifen genau bis unter die Leiste.
            .statusBarScrim(scrim != .none && section == .overview,
                            color: scrim == .page ? Ink.background : detail.ref.typeColor.colors.surface)
            if let dialog = detail.dialog, !dialogDismissed.contains(dialog.id) {
                FinishedDialogView(dialog: dialog, color: detail.ref.typeColor,
                                   toTimeline: {
                                       close(dialog)
                                       Router.shared.tab = .timeline
                                   },
                                   congratulate: {
                                       close(dialog)
                                       section = .chat
                                       Task { await ChatStore.congratulate(cohabitId: detail.id, dialog: dialog) }
                                   })
                    .transition(.opacity)
            }
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .edit: EditCohabitSheet(store: store, detail: detail)
            case .members: MembersSheet(store: store)
            case .pauses: PausesSheet(store: store)
            case .invite: InviteSheet(cohabitId: detail.id, name: detail.ref.name)
            case .notifications: CohabitSettingsSheet(store: store)
            case .entries: EntriesSheet(store: store)
            }
        }
        .confirmationDialog("„\(detail.ref.name)“ verlassen?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Verlassen", role: .destructive) { Task { await store.leave() } }
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog("„\(detail.ref.name)“ löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen – mit Einträgen, Chat und Fotos", role: .destructive) { Task { await store.delete() } }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private func close(_ dialog: FinishedDialog) {
        withAnimation { _ = dialogDismissed.insert(dialog.id) }
        Task { await store.markDialogSeen(dialog) }
    }

    // MARK: - Menue

    @ViewBuilder
    private func menu(_ detail: CohabitDetail) -> some View {
        Menu {
            if detail.isAdmin && !detail.summary.archived {
                Button("Bearbeiten", systemImage: "pencil") { sheet = .edit }
            }
            Button("Mitglieder", systemImage: "person.2") { sheet = .members }
            if detail.ref.type == .streak && !detail.summary.archived {
                Button("Pausen", systemImage: "pause.circle") { sheet = .pauses }
            }
            if detail.canInvite && !detail.summary.archived {
                Button("Einladen", systemImage: "person.badge.plus") { sheet = .invite }
            }
            Button("Benachrichtigungen", systemImage: "bell") { sheet = .notifications }
            if let from = detail.backfillFrom, !detail.summary.archived, detail.config.auto == nil,
               from < CheckInTarget(detail: detail, meId: meId).today {
                // Auch wenn heute schon erledigt ist und der Knopf deshalb aus ist.
                Button(detail.ref.type == .abstinence ? "Unterbrechung nachtragen …" : "Nachtragen …",
                       systemImage: "calendar.badge.plus") {
                    let target = CheckInTarget(detail: detail, meId: meId)
                    if detail.ref.type == .abstinence {
                        CheckInController.shared.valueTarget = target
                    } else {
                        CheckInController.shared.startBackfill(target)
                    }
                }
            }
            if !detail.myCheckins.isEmpty {
                Button("Meine Einträge", systemImage: "list.bullet") { sheet = .entries }
            }
            Divider()
            if detail.isAdmin {
                Button(detail.summary.archived ? "Wiederherstellen" : "Archivieren",
                       systemImage: detail.summary.archived ? "tray.and.arrow.up" : "archivebox") {
                    Task { await store.archive(!detail.summary.archived) }
                }
            }
            if !detail.isAdmin || detail.members.count > 1 {
                Button("Verlassen", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    confirmLeave = true
                }
            }
            if detail.isAdmin {
                Button("Löschen", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        } label: {
            CircleButtonLabel(systemImage: "ellipsis")
        }
        .accessibilityLabel("Menü")
        .accessibilityIdentifier("detailMenu")
    }

    // MARK: - Uebersicht

    @ViewBuilder
    private func overview(_ detail: CohabitDetail) -> some View {
        switch detail.ref.type {
        case .streak: StreakOverview(detail: detail, setHealthyConsent: setHealthyConsent)
        case .abstinence: AbstinenceOverview(detail: detail)
        case .goal: GoalOverview(detail: detail, enableHealth: { Task { await store.enableHealth() } },
                                 setHealthyConsent: setHealthyConsent)
        case .challenge: ChallengeOverview(detail: detail, setHealthyConsent: setHealthyConsent)
        }
    }

    /// kcal aus Healthy: nur die Einwilligung beim Dienst, keine Apple-Health-Abfrage.
    private func setHealthyConsent(_ on: Bool) async {
        await store.setHealthyConsent(on)
    }

    /// Unten fest: der Knopf mit `checkInLabel` (Vertrag §5.3). Bei Abstinenz
    /// umrandet, weil eine Unterbrechung nichts ist, das man gern antippt.
    @ViewBuilder
    private func bottomAction(_ detail: CohabitDetail) -> some View {
        if !detail.summary.archived, detail.config.auto == nil {
            let target = CheckInTarget(detail: detail, meId: meId)
            let checkIns = CheckInController.shared
            let pending = CohabitSync.shared.pendingCheckins.contains(detail.id)
            let label = pending ? "Wartet auf Netz" : (detail.summary.checkInLabel ?? "Abhaken")
            Group {
                if detail.ref.type == .abstinence {
                    Button { checkIns.start(target) } label: { Text(label) }
                        .buttonStyle(OutlineButtonStyle())
                } else {
                    Button { checkIns.start(target) } label: {
                        HStack(spacing: 10) {
                            if checkIns.busy.contains(detail.id) {
                                ProgressView().tint(Ink.onInk)
                            } else if pending {
                                Image(systemName: "clock")
                            } else if detail.config.photoRequired && detail.summary.canCheckIn {
                                Image(systemName: "camera")
                            }
                            Text(label)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .disabled(!detail.summary.canCheckIn || pending || checkIns.busy.contains(detail.id))
            .contextMenu {
                if detail.backfillFrom != nil, detail.backfillFrom != target.today, detail.ref.type != .abstinence {
                    Button("Für einen anderen Tag …", systemImage: "calendar") { checkIns.startBackfill(target) }
                }
            }
            .accessibilityIdentifier("detailCheckIn")
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(
                LinearGradient(colors: [Ink.background.opacity(0), Ink.background], startPoint: .top, endPoint: .center)
                    .ignoresSafeArea()
            )
        }
    }
}

// MARK: - Kopf

/// Der Kopf in der Co-Habit-Farbe mit Zurueck, Typzeile, Menue, den grossen
/// Zahlen und dem Umschalter.
struct DetailHeader<MenuContent: View>: View {
    let detail: CohabitDetail
    @Binding var section: DetailSection
    let compact: Bool
    var topInset: CGFloat = 52
    let back: () -> Void
    @ViewBuilder let menu: () -> MenuContent

    @Environment(\.meId) private var meId

    private var colors: PaletteColor { detail.ref.typeColor.colors }

    var body: some View {
        VStack(spacing: 16) {
            if compact {
                compactTop
            } else {
                HStack {
                    Button(action: back) { CircleButtonLabel(systemImage: "chevron.left") }
                        .accessibilityLabel("Zurück")
                    Spacer()
                    Text(typeLine)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Ink.ink)
                        .lineLimit(1)
                    Spacer()
                    menu()
                }
                figures
            }
            CapsuleSegments(options: [(DetailSection.overview, "Übersicht", nil),
                                      (DetailSection.chat, "Chat", detail.unreadMessages)],
                            selection: $section, height: 52)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("detailSegments")
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, topInset + 6)
        .padding(.bottom, 18)
        .background {
            ZStack {
                colors.surface
                CornerCircle(color: colors.accent.opacity(0.5), corner: .topTrailing, size: compact ? 150 : 220, inset: 0.3)
                if detail.ref.type == .abstinence && !compact {
                    CornerCircle(color: colors.accent.opacity(0.35), corner: .bottomLeading, size: 200, inset: 0.3)
                }
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 36, bottomTrailingRadius: 36, style: .continuous))
        }
    }

    private var typeLine: String {
        switch detail.ref.type {
        case .goal: detail.goal?.typeLine ?? detail.summary.typeLine
        case .challenge:
            if let period = detail.challenge?.periodLabel, !period.isEmpty { "Challenge · \(period)" } else { detail.summary.typeLine }
        default: detail.summary.typeLine
        }
    }

    /// Kompakt im Chat: Name, wer mitmacht, die Kennzahl.
    private var compactTop: some View {
        HStack(spacing: 12) {
            Button(action: back) { CircleButtonLabel(systemImage: "chevron.left") }
                .accessibilityLabel("Zurück")
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.ref.name)
                    .font(.heading(24))
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)
                Text(detail.members.map { $0.person.shortLabel(me: meId) }.joined(separator: ", "))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.ink)
                    .lineLimit(1)
            }
            Spacer()
            HeadlineFigure(headline: detail.summary.headline, valueFont: .figure(26),
                           unitFont: .system(size: 13, weight: .bold))
                .fixedSize()
        }
    }

    @ViewBuilder
    private var figures: some View {
        switch detail.ref.type {
        case .streak:
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(detail.ref.name)
                        .font(.heading(34))
                        .foregroundStyle(Ink.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    if let text = detail.streak?.remainingText ?? detail.summary.unavailableText {
                        Text(text)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Ink.ink)
                    }
                }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(detail.streak.map { "\($0.current)" } ?? detail.summary.headline.value)
                        .font(.figure(68))
                        .foregroundStyle(Ink.ink)
                    Text(detail.streak?.unitLabel ?? detail.summary.headline.unit)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Ink.ink)
                }
                // Die Zahl bricht nie um („10" / „3" bei 103 Wochen neben einem
                // langen Namen) - eher wird der Name kleiner.
                .fixedSize()
                .accessibilityIdentifier("streakFigure")
            }
        case .abstinence:
            VStack(spacing: 4) {
                Text(detail.ref.name)
                    .font(.heading(26))
                    .foregroundStyle(Ink.ink)
                    .multilineTextAlignment(.center)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(detail.abstinence?.currentDays ?? 0)")
                        .font(.figure(104))
                        .foregroundStyle(Ink.ink)
                    Text((detail.abstinence?.currentDays ?? 0) == 1 ? "Tag" : "Tage")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Ink.ink)
                }
                if let block = detail.abstinence {
                    Text(recordLine(block))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Ink.ink)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        case .goal:
            if let goal = detail.goal {
                VStack(spacing: 12) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(detail.ref.name)
                                .font(.heading(30))
                                .foregroundStyle(Ink.ink)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                            Text(goal.totalText)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Ink.ink)
                        }
                        Spacer(minLength: 8)
                        Text("\(goal.percent)%")
                            .font(.figure(64))
                            .foregroundStyle(Ink.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    ProgressTrack(fraction: Double(goal.percent) / 100, fill: Ink.ink, track: Ink.surface, height: 14)
                    HStack {
                        if let delta = goal.planDeltaText {
                            Chip(text: delta, fill: Ink.surface, weight: .bold)
                        }
                        if let finished = goal.finished {
                            Chip(text: finished.text, fill: Ink.ink, foreground: Ink.onInk, weight: .bold)
                        }
                        Spacer()
                        if let remaining = goal.remainingText {
                            Text(remaining)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Ink.ink)
                        }
                    }
                }
            }
        case .challenge:
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(detail.ref.name)
                        .font(.heading(34))
                        .foregroundStyle(Ink.ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                    if let ends = detail.challenge?.endsInText {
                        Text(ends)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Ink.ink)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(detail.summary.headline.value)
                        .font(.figure(64))
                        .foregroundStyle(Ink.ink)
                    Text(detail.summary.headline.unit)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Ink.ink)
                }
            }
        }
    }

    private func recordLine(_ block: AbstinenceBlock) -> String {
        let record = "Rekord \(block.record) \(block.record == 1 ? "Tag" : "Tage")"
        guard let toRecord = block.toRecordText, !toRecord.isEmpty else { return record }
        return "\(record) · \(toRecord)"
    }
}
