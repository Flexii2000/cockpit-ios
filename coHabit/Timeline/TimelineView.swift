import SwiftUI

/// Was die Timeline zeigt (`GET /timeline`, Vertrag §3.7) - ohne die
/// Co-Habits, die der Filter ausblendet (`exclude`).
@MainActor
@Observable
final class TimelineStore {

    private(set) var items: [TimelineItem] = []
    private(set) var hasMore = false
    /// Die aktiven Co-Habits der Person - die Liste im Filter-Blatt.
    private(set) var cohabits: [CohabitRef] = []
    /// Ob `cohabits` schon geladen ist. Vorher laesst sich nicht sagen, welche
    /// der gemerkten Ausblendungen noch gelten.
    private(set) var knowsCohabits = false
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private(set) var filter: TimelineFilter
    /// Zaehlt jedes Laden - eine Antwort, die ein spaeteres Laden ueberholt hat
    /// (schnell hintereinander abgewaehlt), wird verworfen.
    private var generation = 0

    private let makeAPI: @MainActor () -> CohabitAPI
    private let defaults: UserDefaults

    init(makeAPI: @escaping @MainActor () -> CohabitAPI = { Session.shared.api() },
         defaults: UserDefaults = .standard) {
        self.makeAPI = makeAPI
        self.defaults = defaults
        filter = TimelineFilter.load(from: defaults)
    }

    /// Was beim Laden ausgeblendet wird: die ausgeblendeten unter den aktiven.
    /// Solange die Liste fehlt, alle gemerkten - unbekannte ignoriert der Dienst.
    var excluded: Set<String> {
        knowsCohabits ? filter.excluded(from: cohabits) : filter.hidden
    }

    var isFiltered: Bool { !filter.allVisible(cohabits) }

    var filterLabel: String { filter.label(for: cohabits) }

    /// Alles ausgeblendet - dann gibt es nichts zu laden.
    var nothingSelected: Bool {
        knowsCohabits && !cohabits.isEmpty && filter.visibleCount(of: cohabits) == 0
    }

    /// Wirkt sofort: der Haken springt um, gemerkt wird gleich, dann laedt die
    /// Timeline dahinter neu.
    func toggle(_ id: String) async {
        filter.toggle(id)
        await filterChanged()
    }

    func toggleAll() async {
        filter.toggleAll(cohabits)
        await filterChanged()
    }

    private func filterChanged() async {
        filter.save(to: defaults)
        await load()
    }

    func load() async {
        generation += 1
        let current = generation
        isLoading = items.isEmpty
        defer { if current == generation { isLoading = false } }
        let api = makeAPI()
        do {
            let guess = excluded
            async let listRequest: [CohabitSummary] = api.get("/cohabits")
            var page: TimelinePage? = nothingSelected
                ? nil : try await api.get("/timeline", query: TimelineFilter.query(exclude: guess))
            if let list = try? await listRequest {
                cohabits = list.map(\.ref)
                knowsCohabits = true
            }
            if nothingSelected {
                page = nil
            } else if page == nil || excluded != guess {
                // Die Liste kam erst jetzt - mit dem, was wirklich gilt, noch einmal.
                page = try await api.get("/timeline", query: TimelineFilter.query(exclude: excluded))
            }
            guard current == generation else { return }
            items = page?.items ?? []
            hasMore = page?.hasMore ?? false
            errorMessage = nil
            if !nothingSelected { await markSeen(api: api, excluded: excluded) }
        } catch {
            if await Session.shared.handle(error) { return }
            guard current == generation else { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadMore() async {
        guard hasMore, let last = items.last else { return }
        let current = generation
        let query = TimelineFilter.query(exclude: excluded, before: last.id)
        guard let page: TimelinePage = try? await makeAPI().get("/timeline", query: query),
              current == generation else { return }
        items += page.items.filter { item in !items.contains { $0.id == item.id } }
        hasMore = page.hasMore
    }

    /// „neue Beweisfotos" auf „Heute" gelten mit dem Blick in die Timeline als
    /// gesehen. Ist etwas ausgeblendet, zaehlt das neueste Ereignis ueberhaupt:
    /// sonst stuende auf „Heute" fuer immer, was der Filter nie zeigt.
    private func markSeen(api: CohabitAPI, excluded: Set<String>) async {
        var newest = items.first
        if !excluded.isEmpty {
            let page: TimelinePage? = try? await api.get("/timeline", query: [URLQueryItem(name: "limit", value: "1")])
            newest = page?.items.first
        }
        guard let newest else { return }
        try? await api.sendIgnoringResponse("POST", "/timeline/seen", body: SeenRequest(lastEventId: newest.id))
    }

    /// Wie im Chat: ein Emoji setzt, das eigene noch einmal nimmt zurueck.
    func react(_ emoji: String, on item: TimelineItem) async {
        await Reactions.choose(emoji, target: item.reactionTarget, current: item.reactions) { [weak self] list in
            guard let self, let index = self.items.firstIndex(where: { $0.id == item.id }) else { return }
            self.items[index] = self.items[index].with(reactions: list)
        }
    }

    func removeReaction(on item: TimelineItem) async {
        guard let mine = Reactions.mine(in: item.reactions) else { return }
        await react(mine, on: item)
    }
}

struct SeenRequest: Encodable {
    let lastEventId: String
}

extension TimelineItem {
    func with(reactions: [ReactionView]) -> TimelineItem {
        TimelineItem(id: id, day: day, at: at, cohabit: cohabit, kind: kind, person: person, title: title,
                     subtitle: subtitle, photoId: photoId, caption: caption, reactionTarget: reactionTarget,
                     reactions: reactions, canReply: canReply, photoIds: photoIds)
    }
}

/// Die Timeline (Entwurf S. 3): oben der Filter, Abschnitte je Tag,
/// Beweisfotos gross, der Rest kompakt.
struct TimelineView: View {

    @State private var store = TimelineStore()
    @State private var showsFilter = false
    /// Langer Druck bzw. Smiley: die Leiste fuer dieses Ereignis.
    @State private var menuTarget: TimelineItem?
    @State private var afterMenu: (@MainActor () -> Void)?
    /// Das Blatt „Reaktionen".
    @State private var reactionsTarget: TimelineItem?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("Timeline")
                    .font(.heading(34))
                    .foregroundStyle(Ink.ink)
                    .padding(.top, 8)
                    .padding(.horizontal, Metrics.gutter)
                VStack(alignment: .leading, spacing: 10) {
                    filterButton
                    if store.nothingSelected {
                        Text("Keine Habits ausgewählt")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Ink.muted)
                            .accessibilityIdentifier("noHabitsSelected")
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                VStack(alignment: .leading, spacing: 12) {
                    SyncLine()
                    if let message = store.errorMessage, store.items.isEmpty {
                        ErrorLine(message: message)
                    }
                    let groups = Dictionary(grouping: store.items, by: \.day)
                    ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                        SectionLabel(text: Formats.dayTitle(day))
                        ForEach(groups[day] ?? []) { item in
                            TimelineCard(item: item,
                                         openMenu: { menuTarget = item },
                                         openReactions: { reactionsTarget = item })
                        }
                    }
                    if store.hasMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .onAppear { Task { await store.loadMore() } }
                    }
                    if store.items.isEmpty && !store.isLoading && store.errorMessage == nil && !store.nothingSelected {
                        EmptyState(text: "Noch nichts passiert")
                    }
                    if store.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                    TabBarSpacer()
                }
                .padding(.horizontal, Metrics.gutter)
            }
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .statusBarScrim()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .refreshable { await store.load() }
        .task { await store.load() }
        .onChange(of: DataBus.shared.revision) { Task { await store.load() } }
        .sheet(isPresented: $showsFilter) {
            TimelineFilterSheet(store: store)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: menuTarget?.id) { _, new in new != nil }
        .sheet(item: $menuTarget, onDismiss: {
            afterMenu?()
            afterMenu = nil
        }) { item in
            ReactionActionsSheet(current: Reactions.mine(in: item.reactions),
                                 actions: item.canReply ? [ReactionMenuAction(
                                     title: "Antworten", systemImage: "bubble.left", identifier: "menuReply") {
                                         Router.shared.push(.cohabit(item.cohabit.id, .chat))
                                     }] : [],
                                 react: { emoji in Task { await store.react(emoji, on: item) } },
                                 afterDismiss: { afterMenu = $0 })
        }
        .sheet(item: $reactionsTarget) { target in
            let item = store.items.first { $0.id == target.id } ?? target
            ReactionsListSheet(reactions: item.reactions) {
                Task { await store.removeReaction(on: item) }
            }
        }
    }

    /// Der aktuelle Filter als Knopf - „Alle Habits", ein Name oder „2 von 5
    /// Habits". Gefiltert in Tinte, wie frueher der gewaehlte Chip.
    private var filterButton: some View {
        let filtered = store.isFiltered
        return Button {
            showsFilter = true
        } label: {
            HStack(spacing: 8) {
                Text(store.filterLabel)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .heavy))
                    .accessibilityHidden(true)
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(filtered ? Ink.onInk : Ink.ink)
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(filtered ? Ink.ink : Ink.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("timelineFilter")
    }
}

/// Ein Ereignis: mit Foto gross, sonst kompakt.
struct TimelineCard: View {
    let item: TimelineItem
    /// Die Leiste mit den Emojis (langer Druck, Smiley).
    let openMenu: () -> Void
    /// Tipp auf die Pille.
    let openReactions: () -> Void

    @Environment(\.meId) private var meId

    var body: some View {
        Group {
            if !item.photos.isEmpty {
                photoCard
            } else {
                compactCard
            }
        }
        .onLongPressGesture(minimumDuration: 0.35, perform: openMenu)
        .accessibilityAction(named: "Reagieren", openMenu)
    }

    private var title: Text {
        // Den Namen am Anfang fett, wie im Entwurf („**Lena** hat Laufen abgehakt").
        let name = item.person?.displayName ?? (item.kind == .health ? "Health" : nil)
        if let name, item.title.hasPrefix(name) {
            let rest = String(item.title.dropFirst(name.count))
            return Text("\(Text(name).fontWeight(.heavy))\(rest)")
        }
        return Text(item.title)
    }

    private var leading: some View {
        Group {
            if item.kind == .health {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Ink.ink)
                    .frame(width: 40, height: 40)
                    .background(PaletteKey.periwinkle.colors.surface, in: Circle())
            } else if let person = item.person {
                AvatarView(person: person, size: 40, ring: nil)
            } else {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Ink.ink)
                    .frame(width: 40, height: 40)
                    .background(item.cohabit.typeColor.colors.surface, in: Circle())
            }
        }
    }

    private var photoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Ink.ink)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Ink.muted)
                    }
                }
                Spacer(minLength: 4)
                Chip(text: item.cohabit.name, fill: item.cohabit.typeColor.colors.surface,
                     foreground: item.cohabit.typeColor.colors.onSurface, weight: .bold)
            }
            PhotoCarousel(ids: item.photos, height: 220, placeholder: item.cohabit.typeColor.colors.surface)
            if let caption = item.caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Ink.ink)
            }
            HStack(alignment: .center, spacing: 12) {
                if !item.reactions.isEmpty {
                    ReactionPill(reactions: item.reactions, open: openReactions)
                }
                Spacer(minLength: 4)
                smileyButton
                if item.canReply {
                    replyButton
                }
            }
        }
        .card(padding: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("event-\(item.id)")
    }

    private var compactCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                leading
                VStack(alignment: .leading, spacing: 2) {
                    title
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Ink.ink)
                    Text([item.subtitle].compactMap { $0 }.joined())
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.muted)
                }
                Spacer(minLength: 0)
            }
            if !item.reactions.isEmpty {
                ReactionPill(reactions: item.reactions, open: openReactions)
                    .padding(.leading, 52)
            }
        }
        .card(padding: 14)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("event-\(item.id)")
    }

    /// Neben „Antworten": oeffnet die Leiste wie der lange Druck.
    private var smileyButton: some View {
        Button(action: openMenu) {
            Image(systemName: "face.smiling")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Ink.muted)
                .frame(width: 36, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reagieren")
        .accessibilityIdentifier("smiley-\(item.id)")
    }

    private var replyButton: some View {
        Button("Antworten") {
            Router.shared.push(.cohabit(item.cohabit.id, .chat))
        }
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(Ink.accent)
        .accessibilityIdentifier("reply-\(item.id)")
    }
}
