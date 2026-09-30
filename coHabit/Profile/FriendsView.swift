import SwiftUI

/// „Freunde & Einladungen" (Vertrag §3.3, §5.2.5): offene Einladungen,
/// Anfragen, Freunde, Suche, Freundes-Link, Blockierte - und ein Feld fuer
/// Links, die jemand per Messenger geschickt hat (sie oeffnen sonst im Browser).
@MainActor
@Observable
final class FriendsStore {
    private(set) var overview: FriendsOverview?
    private(set) var invitations: [InvitationView] = []
    private(set) var blocked: [PersonView] = []
    private(set) var results: [PersonSearchResult] = []
    private(set) var errorMessage: String?

    private var api: CohabitAPI { Session.shared.api() }

    func load() async {
        do {
            async let friends: FriendsOverview = api.get("/friends")
            async let pending: [InvitationView] = api.get("/me/invitations")
            async let blocks: [PersonView] = api.get("/blocks")
            overview = try await friends
            invitations = (try? await pending) ?? []
            blocked = (try? await blocks) ?? []
            errorMessage = nil
        } catch {
            if await Session.shared.handle(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        results = (try? await api.get("/people/search", query: [URLQueryItem(name: "q", value: trimmed)])) ?? []
    }

    func request(_ person: PersonView) async {
        do {
            let _: FriendRequest = try await api.send("POST", "/friends/requests", body: UsernameRequest(username: person.username))
            Toast.shared.show("Anfrage an \(person.displayName) gesendet")
            await load()
            results = results.map { $0.person.id == person.id ? PersonSearchResult(person: $0.person, relation: .requestSent) : $0 }
        } catch {
            Toast.shared.show(error)
        }
    }

    func answer(_ request: FriendRequest, accept: Bool) async {
        do {
            overview = try await api.send("POST", "/friends/requests/\(request.id)/\(accept ? "accept" : "decline")",
                                          body: CohabitAPI.EmptyBody())
            await Session.shared.refreshMe()
        } catch {
            Toast.shared.show(error)
        }
    }

    func remove(_ person: PersonView) async {
        do {
            try await api.sendIgnoringResponse("DELETE", "/friends/\(person.id)")
            await load()
        } catch {
            Toast.shared.show(error)
        }
    }

    func block(_ person: PersonView) async {
        do {
            try await api.sendIgnoringResponse("POST", "/blocks", body: PersonIdRequest(personId: person.id))
            await load()
        } catch {
            Toast.shared.show(error)
        }
    }

    func unblock(_ person: PersonView) async {
        do {
            try await api.sendIgnoringResponse("DELETE", "/blocks/\(person.id)")
            await load()
        } catch {
            Toast.shared.show(error)
        }
    }

    func friendLink() async -> URL? {
        do {
            let link: LinkInfo = try await api.send("POST", "/me/friend-link", body: CohabitAPI.EmptyBody())
            return URL(string: link.url)
        } catch {
            Toast.shared.show(error)
            return nil
        }
    }
}

struct UsernameRequest: Encodable {
    let username: String
}

struct FriendsView: View {
    @State private var store = FriendsStore()
    @State private var query = ""
    @State private var pasted = ""
    @State private var sharing: ShareItem?
    @State private var removeTarget: PersonView?

    private var router: Router { Router.shared }

    var body: some View {
        Subpage(title: "Freunde & Einladungen") {
            linkField
            if let message = store.errorMessage { ErrorLine(message: message) }

            if !store.invitations.isEmpty {
                SectionLabel(text: "Einladungen")
                ForEach(store.invitations) { invitation in
                    InvitationCard(invitation: invitation) { router.invitation = .pending(invitation) }
                }
            }

            if let overview = store.overview, !overview.incoming.isEmpty {
                SectionLabel(text: "Anfragen")
                FormCard {
                    ForEach(Array(overview.incoming.enumerated()), id: \.element.id) { index, request in
                        if index > 0 { FormDivider() }
                        HStack(spacing: 12) {
                            AvatarView(person: request.from, size: 40, ring: nil)
                            personText(request.from)
                            Spacer()
                            Button("Annehmen") { Task { await store.answer(request, accept: true) } }
                                .buttonStyle(SmallOutlineButtonStyle())
                                .accessibilityIdentifier("acceptFriend-\(request.from.id)")
                            Button { Task { await store.answer(request, accept: false) } } label: {
                                Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Ink.muted)
                            }
                            .accessibilityLabel("Ablehnen")
                        }
                        .padding(.vertical, 10)
                    }
                }
            }

            SectionLabel(text: "Freunde")
            InputField(placeholder: "Nutzername suchen", text: $query, identifier: "friendSearch", capitalization: .never)
                .autocorrectionDisabled()
            if !store.results.isEmpty {
                FormCard {
                    ForEach(Array(store.results.enumerated()), id: \.element.id) { index, result in
                        if index > 0 { FormDivider() }
                        HStack(spacing: 12) {
                            AvatarView(person: result.person, size: 40, ring: nil)
                            personText(result.person)
                            Spacer()
                            switch result.relation {
                            case .none:
                                Button("Anfragen") { Task { await store.request(result.person) } }
                                    .buttonStyle(SmallOutlineButtonStyle())
                            case .requestSent: RowValue(text: "Angefragt")
                            case .requestReceived: RowValue(text: "Fragt dich an")
                            case .friend: RowValue(text: "Befreundet")
                            case .selfPerson: RowValue(text: "Du")
                            }
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
            if let overview = store.overview {
                if overview.friends.isEmpty {
                    Text("Noch keine Freunde")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Ink.muted)
                } else {
                    FormCard {
                        ForEach(Array(overview.friends.enumerated()), id: \.element.id) { index, friend in
                            if index > 0 { FormDivider() }
                            HStack(spacing: 12) {
                                AvatarView(person: friend, size: 40, ring: nil)
                                personText(friend)
                                Spacer()
                                Menu {
                                    Button("Entfernen", systemImage: "person.fill.xmark", role: .destructive) {
                                        removeTarget = friend
                                    }
                                    Button("Blockieren", systemImage: "hand.raised", role: .destructive) {
                                        Task { await store.block(friend) }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(Ink.ink)
                                        .frame(width: 36, height: 36)
                                }
                                .accessibilityLabel("Mehr zu \(friend.displayName)")
                            }
                            .padding(.vertical, 10)
                        }
                    }
                }
                if !overview.outgoing.isEmpty {
                    SectionLabel(text: "Angefragt")
                    FormCard {
                        ForEach(Array(overview.outgoing.enumerated()), id: \.element.id) { index, request in
                            if index > 0 { FormDivider() }
                            HStack(spacing: 12) {
                                AvatarView(person: request.to, size: 40, ring: nil)
                                personText(request.to)
                                Spacer()
                            }
                            .padding(.vertical, 10)
                        }
                    }
                }
            }

            Button {
                Task {
                    if let url = await store.friendLink() { sharing = ShareItem(url: url) }
                }
            } label: {
                Label("Freundes-Link teilen", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PrimaryButtonStyle(fill: Ink.accent, foreground: .white))
            .padding(.top, 6)

            if !store.blocked.isEmpty {
                SectionLabel(text: "Blockiert")
                FormCard {
                    ForEach(Array(store.blocked.enumerated()), id: \.element.id) { index, person in
                        if index > 0 { FormDivider() }
                        HStack(spacing: 12) {
                            AvatarView(person: person, size: 40, ring: nil)
                            personText(person)
                            Spacer()
                            Button("Freigeben") { Task { await store.unblock(person) } }
                                .buttonStyle(SmallOutlineButtonStyle())
                        }
                        .padding(.vertical, 10)
                    }
                }
            }
        }
        .task { await store.load() }
        .refreshable { await store.load() }
        .onChange(of: DataBus.shared.revision) { Task { await store.load() } }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await store.search(query)
        }
        .sheet(item: $sharing) { item in
            ActivityView(items: [item.url]).presentationDetents([.medium, .large])
        }
        .confirmationDialog("\(removeTarget?.displayName ?? "") entfernen?",
                            isPresented: Binding(get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) {
                if let person = removeTarget { Task { await store.remove(person) } }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private func personText(_ person: PersonView) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(person.displayName)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Ink.ink)
            Text("@\(person.username)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.muted)
        }
    }

    /// Ein Einladungs- oder Freundes-Link aus einer Nachricht.
    private var linkField: some View {
        HStack(spacing: 8) {
            InputField(placeholder: "Link einfügen", text: $pasted, identifier: "friendsLinkField", capitalization: .never)
                .autocorrectionDisabled()
            PasteButton(payloadType: String.self) { strings in
                pasted = strings.first ?? ""
                openPasted()
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.capsule)
            .tint(Ink.ink)
        }
        .onSubmit(openPasted)
    }

    private func openPasted() {
        guard let link = LinkParser.find(in: pasted) else {
            if !pasted.isEmpty { Toast.shared.show("Link ungültig", error: true) }
            return
        }
        pasted = ""
        router.open(link)
    }
}
