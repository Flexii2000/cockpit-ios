import SwiftUI

/// Neues Co-Habit in drei Schritten (Entwuerfe S. 12–14): Typ, Einstellungen,
/// wer mitmacht.
@MainActor
@Observable
final class CreateFlowModel {
    var step = 1
    var config = CohabitConfig.draft(.streak)
    var invited: Set<String> = []
    var friends: [PersonView] = []
    var results: [PersonSearchResult] = []
    /// Schon angelegt - weil der Einladungslink ein bestehendes Co-Habit braucht.
    private(set) var created: CohabitDetail?
    var busy = false
    var errorMessage: String?

    private var api: CohabitAPI { Session.shared.api() }

    func choose(_ type: CohabitType) {
        if config.type != type || config.name.isEmpty {
            let name = config.name
            config = .draft(type)
            config.name = name
        }
        step = 2
    }

    func loadFriends() async {
        guard let overview: FriendsOverview = try? await api.get("/friends") else { return }
        friends = overview.friends
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        let found: [PersonSearchResult] = (try? await api.get("/people/search", query: [URLQueryItem(name: "q", value: trimmed)])) ?? []
        results = found.filter { $0.relation != .friend && $0.relation != .selfPerson }
    }

    func request(_ person: PersonView) async {
        do {
            let _: FriendRequest = try await api.send("POST", "/friends/requests", body: UsernameRequest(username: person.username))
            Toast.shared.show("Anfrage an \(person.displayName) gesendet")
            results = results.map { $0.person.id == person.id ? PersonSearchResult(person: $0.person, relation: .requestSent) : $0 }
        } catch {
            Toast.shared.show(error)
        }
    }

    /// Legt an, falls noch nicht geschehen - der Einladungslink braucht ein Co-Habit.
    func ensureCreated() async -> CohabitDetail? {
        if let created { return created }
        busy = true
        defer { busy = false }
        do {
            let detail: CohabitDetail = try await api.send(
                "POST", "/cohabits", body: CreateCohabitRequest(config: cleaned, invitePersonIds: Array(invited)))
            created = detail
            invited = []
            DataBus.shared.changed()
            return detail
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func start() async -> CohabitDetail? {
        if let created {
            if !invited.isEmpty {
                busy = true
                defer { busy = false }
                do {
                    let _: InviteCandidates = try await api.send("POST", "/cohabits/\(created.id)/invitations",
                                                                 body: InviteRequest(personIds: Array(invited)))
                } catch {
                    errorMessage = error.localizedDescription
                    return nil
                }
            }
            DataBus.shared.changed()
            return created
        }
        return await ensureCreated()
    }

    func inviteLink() async -> URL? {
        guard let detail = await ensureCreated() else { return nil }
        do {
            let link: LinkInfo = try await api.send("POST", "/cohabits/\(detail.id)/invite-link", body: CohabitAPI.EmptyBody())
            return URL(string: link.url)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Was rausgeht: der Name ohne Rand und die eigene Farbe des Typs
    /// (Vertrag §5.2b; automatische: die von „Automatisch").
    var cleaned: CohabitConfig {
        var config = config
        config.name = config.name.trimmingCharacters(in: .whitespacesAndNewlines)
        config.color = config.typeColor(in: Session.shared.typeColors)
        return config
    }

    var seatsUsed: Int { (created?.seats.used ?? 1) + invited.count }
}

struct CreateFlowView: View {
    @State private var model = CreateFlowModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            switch model.step {
            case 1: TypeStep(model: model)
            case 2: SettingsStep(model: model)
            default: InviteStep(model: model, finish: finish)
            }
        }
        .screenBackground()
        .task {
            await model.loadFriends()
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                Button {
                    if model.step == 1 { dismiss() } else { model.step -= 1 }
                } label: {
                    CircleButtonLabel(systemImage: model.step == 1 ? "xmark" : "chevron.left")
                }
                .accessibilityLabel(model.step == 1 ? "Schließen" : "Zurück")
                .accessibilityIdentifier("createBack")
                Spacer()
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Ink.ink)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { index in
                    Capsule()
                        .fill(index <= model.step ? Ink.accent : Ink.accentSoft)
                        .frame(height: 6)
                }
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var title: String {
        switch model.step {
        case 1: "Neues Co-Habit · 1 von 3"
        case 2: "\(model.config.type.title) · 2 von 3"
        default: "\(model.config.name.isEmpty ? model.config.type.title : model.config.name) · 3 von 3"
        }
    }

    private func finish(_ detail: CohabitDetail) {
        dismiss()
        Router.shared.showCohabit(detail.id, section: .overview)
    }
}

// MARK: - Schritt 1

struct TypeStep: View {
    let model: CreateFlowModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Was wollt ihr gemeinsam verfolgen?")
                    .font(.heading(30))
                    .foregroundStyle(Ink.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
                ForEach(CohabitType.allCases) { type in
                    Button {
                        model.choose(type)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(type.title)
                                .font(.heading(24))
                            Text(Self.description(type))
                                .font(.system(size: 15, weight: .medium))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(Self.example(type))
                                .font(.system(size: 13, weight: .bold))
                                .padding(.top, 2)
                        }
                        .foregroundStyle(Ink.ink)
                        .multilineTextAlignment(.leading)
                        .card(colors(type).surface, circle: colors(type).accent.opacity(0.55),
                              corner: Self.corner(type), circleSize: 90, padding: 18)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("createType-\(type.rawValue)")
                }
                Text("Der Typ kann später nicht mehr geändert werden.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Ink.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 12)
        }
    }

    /// Die Typkarten in den eigenen Farben - so sieht das neue Co-Habit nachher aus.
    private func colors(_ type: CohabitType) -> PaletteColor {
        Session.shared.typeColors[TypeColorSlot(type)].colors
    }

    static func description(_ type: CohabitType) -> String {
        switch type {
        case .streak: "Regelmäßig dranbleiben, täglich oder im eigenen Rhythmus."
        case .abstinence: "Tage zählen, an denen ihr auf etwas verzichtet."
        case .goal: "Eine Menge bis zu einem Datum, allein oder als Team."
        case .challenge: "Wer schafft im Zeitraum am meisten?"
        }
    }

    static func example(_ type: CohabitType) -> String {
        switch type {
        case .streak: "z. B. 3× pro Woche laufen"
        case .abstinence: "z. B. ohne Zucker"
        case .goal: "z. B. 100.000 Schritte bis 31.10."
        case .challenge: "z. B. wer kocht im Oktober öfter"
        }
    }

    static func corner(_ type: CohabitType) -> CornerCircle.Corner {
        switch type {
        case .streak, .goal: .topTrailing
        case .abstinence, .challenge: .bottomTrailing
        }
    }
}

// MARK: - Schritt 2

struct SettingsStep: View {
    @Bindable var model: CreateFlowModel

    var body: some View {
        ScrollView {
            CohabitSettingsForm(config: $model.config, sources: Session.shared.me?.sources ?? [], editing: false)
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 12)
            Color.clear.frame(height: 80)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button("Weiter") { model.step = 3 }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(CohabitSettingsForm.problem(model.config) != nil)
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 10)
                .accessibilityIdentifier("createNext")
        }
    }
}

// MARK: - Schritt 3

struct InviteStep: View {
    @Bindable var model: CreateFlowModel
    let finish: (CohabitDetail) -> Void

    @State private var query = ""
    @State private var sharing: ShareItem?
    @State private var linkBusy = false

    private var filteredFriends: [PersonView] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return model.friends }
        return model.friends.filter {
            $0.username.lowercased().hasPrefix(trimmed) || $0.displayName.lowercased().contains(trimmed)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Wer macht mit?")
                        .font(.heading(30))
                        .foregroundStyle(Ink.ink)
                    Spacer()
                    Chip(text: "\(model.seatsUsed) von 8", fill: Ink.surface, weight: .bold)
                }
                InviteLinkCard(busy: linkBusy) {
                    Task {
                        linkBusy = true
                        if let url = await model.inviteLink() { sharing = ShareItem(url: url) }
                        linkBusy = false
                    }
                }
                InputField(placeholder: "Nutzername suchen", text: $query, identifier: "inviteSearch", capitalization: .never)
                    .autocorrectionDisabled()
                if let message = model.errorMessage { ErrorLine(message: message) }
                if !filteredFriends.isEmpty {
                    FormCard {
                        ForEach(Array(filteredFriends.enumerated()), id: \.element.id) { index, friend in
                            if index > 0 { FormDivider() }
                            PersonInviteRow(person: friend,
                                            state: model.invited.contains(friend.id) ? .invited : .invite,
                                            enabled: model.seatsUsed < 8) {
                                model.invited.insert(friend.id)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if model.invited.contains(friend.id) { model.invited.remove(friend.id) }
                            }
                        }
                    }
                }
                if !model.results.isEmpty {
                    FormCard {
                        ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                            if index > 0 { FormDivider() }
                            HStack(spacing: 12) {
                                AvatarView(person: result.person, size: 42, ring: nil)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.person.displayName).font(.system(size: 17, weight: .heavy))
                                    Text("@\(result.person.username)").font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Ink.muted)
                                }
                                Spacer()
                                if result.relation == .none {
                                    Button("Anfragen") { Task { await model.request(result.person) } }
                                        .buttonStyle(SmallOutlineButtonStyle())
                                } else {
                                    RowValue(text: "Angefragt")
                                }
                            }
                            .foregroundStyle(Ink.ink)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 12)
            Color.clear.frame(height: 80)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button {
                Task {
                    if let detail = await model.start() { finish(detail) }
                }
            } label: {
                if model.busy { ProgressView().tint(Ink.onInk) } else { Text("Co-Habit starten") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.busy)
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 10)
            .accessibilityIdentifier("createStart")
        }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await model.search(query)
        }
        .sheet(item: $sharing) { item in
            ActivityView(items: [item.url]).presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Bearbeiten

/// Dieselben Einstellungen wie Schritt 2, ohne den Typ (Vertrag §3.4 PUT).
struct EditCohabitSheet: View {
    let store: CohabitDetailStore
    let detail: CohabitDetail

    @State private var config: CohabitConfig
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    init(store: CohabitDetailStore, detail: CohabitDetail) {
        self.store = store
        self.detail = detail
        _config = State(initialValue: detail.config)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader(title: "Bearbeiten", subtitle: detail.ref.type.title) { dismiss() }
                CohabitSettingsForm(config: $config, sources: Session.shared.me?.sources ?? [], editing: true)
            }
            .padding(Metrics.gutter)
            Color.clear.frame(height: 80)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .safeAreaInset(edge: .bottom) {
            Button {
                saving = true
                Task {
                    if await store.save(config: config) { dismiss() }
                    saving = false
                }
            } label: {
                if saving { ProgressView().tint(Ink.onInk) } else { Text("Sichern") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(saving || CohabitSettingsForm.problem(config) != nil || config == detail.config)
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 10)
        }
    }
}
