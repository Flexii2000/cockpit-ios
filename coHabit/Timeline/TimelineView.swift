import SwiftUI

/// Was die Timeline zeigt (`GET /timeline`, Vertrag §3.7).
@MainActor
@Observable
final class TimelineStore {

    private(set) var items: [TimelineItem] = []
    private(set) var hasMore = false
    private(set) var cohabits: [CohabitRef] = []
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    var filter: String? {
        didSet { if filter != oldValue { Task { await load() } } }
    }

    private var api: CohabitAPI { Session.shared.api() }

    func load() async {
        isLoading = items.isEmpty
        defer { isLoading = false }
        var query = [URLQueryItem(name: "limit", value: "30")]
        if let filter { query.append(URLQueryItem(name: "cohabitId", value: filter)) }
        do {
            async let pageRequest: TimelinePage = api.get("/timeline", query: query)
            async let listRequest: [CohabitSummary] = api.get("/cohabits")
            let page = try await pageRequest
            items = page.items
            hasMore = page.hasMore
            if let list = try? await listRequest { cohabits = list.map(\.ref) }
            errorMessage = nil
            if filter == nil, let first = items.first {
                // „neue Beweisfotos" auf „Heute" gelten damit als gesehen.
                try? await api.sendIgnoringResponse("POST", "/timeline/seen", body: SeenRequest(lastEventId: first.id))
            }
        } catch {
            if await Session.shared.handle(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadMore() async {
        guard hasMore, let last = items.last else { return }
        var query = [URLQueryItem(name: "limit", value: "30"), URLQueryItem(name: "before", value: last.id)]
        if let filter { query.append(URLQueryItem(name: "cohabitId", value: filter)) }
        guard let page: TimelinePage = try? await api.get("/timeline", query: query) else { return }
        items += page.items.filter { item in !items.contains { $0.id == item.id } }
        hasMore = page.hasMore
    }

    func toggle(_ reaction: ReactionKind, on item: TimelineItem) async {
        let mine = item.reactions.first { $0.reaction == reaction }?.mine ?? false
        let updated = await Reactions.toggle(reaction, target: item.reactionTarget, current: item.reactions, mine: mine)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = items[index].with(reactions: updated)
        }
    }
}

struct SeenRequest: Encodable {
    let lastEventId: String
}

extension TimelineItem {
    func with(reactions: [ReactionView]) -> TimelineItem {
        TimelineItem(id: id, day: day, at: at, cohabit: cohabit, kind: kind, person: person, title: title,
                     subtitle: subtitle, photoId: photoId, caption: caption, reactionTarget: reactionTarget,
                     reactions: reactions, canReply: canReply)
    }
}

/// Die Timeline (Entwurf S. 3): Filter je Co-Habit, Abschnitte je Tag,
/// Beweisfotos gross, der Rest kompakt.
struct TimelineView: View {

    @State private var store = TimelineStore()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("Timeline")
                    .font(.heading(34))
                    .foregroundStyle(Ink.ink)
                    .padding(.top, 8)
                    .padding(.horizontal, Metrics.gutter)
                chips
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
                                         react: { reaction in Task { await store.toggle(reaction, on: item) } })
                        }
                    }
                    if store.hasMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .onAppear { Task { await store.loadMore() } }
                    }
                    if store.items.isEmpty && !store.isLoading && store.errorMessage == nil {
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
    }

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                filterChip(title: "Alle", id: nil, color: nil)
                ForEach(store.cohabits) { ref in
                    filterChip(title: ref.name, id: ref.id, color: ref.color)
                }
            }
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
    }

    private func filterChip(title: String, id: String?, color: PaletteKey?) -> some View {
        let selected = store.filter == id
        return Button {
            store.filter = id
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(selected ? Ink.onInk : Ink.ink)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(selected ? Ink.ink : (color?.colors.surface ?? Ink.surface), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filter-\(id ?? "all")")
    }
}

/// Ein Ereignis: mit Foto gross, sonst kompakt.
struct TimelineCard: View {
    let item: TimelineItem
    let react: (ReactionKind) -> Void

    @Environment(\.meId) private var meId

    var body: some View {
        if item.photoId != nil {
            photoCard
        } else {
            compactCard
        }
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
                    .background(item.cohabit.color.colors.surface, in: Circle())
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
                Chip(text: item.cohabit.name, fill: item.cohabit.color.colors.surface,
                     foreground: item.cohabit.color.colors.onSurface, weight: .bold)
            }
            if let photo = item.photoId {
                PhotoView(id: photo, size: .full, placeholder: item.cohabit.color.colors.surface)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            if let caption = item.caption, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Ink.ink)
            }
            HStack(alignment: .center, spacing: 8) {
                ReactionChips(reactions: item.reactions, react: react)
                AddReactionMenu(react: react)
                Spacer(minLength: 4)
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
                ReactionChips(reactions: item.reactions, react: react)
                    .padding(.leading, 52)
            }
        }
        .card(padding: 14)
        .contextMenu {
            ForEach(ReactionKind.allCases) { reaction in
                Button(reaction.label) { react(reaction) }
            }
            if item.canReply {
                Button("Antworten", systemImage: "bubble.left") {
                    Router.shared.push(.cohabit(item.cohabit.id, .chat))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("event-\(item.id)")
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
