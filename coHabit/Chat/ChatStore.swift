import Foundation
import UIKit

/// Der Chat eines Co-Habits (Vertrag §3.6): neueste 50 zuerst geladen,
/// aeltere beim Hochscrollen, neuere alle paar Sekunden, solange er offen ist.
@MainActor
@Observable
final class ChatStore {

    let cohabitId: String
    private(set) var messages: [Message] = []
    private(set) var hasMore = false
    private(set) var isLoading = false
    private(set) var isLoadingOlder = false
    private(set) var errorMessage: String?
    private(set) var sending = false
    /// `GET /gifs/config`, einmal je Chat - ohne (oder ausgeschaltet) kein GIF-Knopf.
    private(set) var gifConfig: GifConfig?
    /// Ein GIF aus der Zwischenablage, das noch ins Eingabefeld gehoert.
    var pastedGif: Data?

    init(cohabitId: String) {
        self.cohabitId = cohabitId
    }

    /// Die Suche bei KLIPY - `nil`, solange der Dienst keinen Schluessel hat.
    var klipy: KlipyClient? { KlipyClient(config: gifConfig) }

    func loadGifConfig() async {
        guard gifConfig == nil else { return }
        gifConfig = try? await api.get("/gifs/config")
    }

    private var api: CohabitAPI { Session.shared.api() }
    private var path: String { "/cohabits/\(cohabitId)/messages" }

    func load() async {
        isLoading = messages.isEmpty
        defer { isLoading = false }
        do {
            let page: MessagesPage = try await api.get(path, query: [URLQueryItem(name: "limit", value: "50")])
            messages = page.messages
            hasMore = page.hasMore
            errorMessage = nil
            await markRead()
        } catch {
            if await Session.shared.handle(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Neuere als die letzte bekannte - fuer das Nachladen im Takt.
    func refresh() async {
        guard let last = messages.last else { return await load() }
        guard let page: MessagesPage = try? await api.get(path, query: [URLQueryItem(name: "after", value: last.id)])
        else { return }
        if !page.messages.isEmpty {
            merge(page.messages)
            await markRead()
        }
    }

    func loadOlder() async {
        guard hasMore, !isLoadingOlder, let first = messages.first else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        guard let page: MessagesPage = try? await api.get(path, query: [
            URLQueryItem(name: "before", value: first.id), URLQueryItem(name: "limit", value: "50"),
        ]) else { return }
        messages = page.messages + messages.filter { message in !page.messages.contains { $0.id == message.id } }
        hasMore = page.hasMore
    }

    private func merge(_ incoming: [Message]) {
        var byId = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        for message in incoming { byId[message.id] = message }
        messages = byId.values.sorted { $0.createdAt < $1.createdAt }
    }

    func markRead() async {
        guard let last = messages.last else { return }
        let _: UnreadResult? = try? await api.send("POST", "/cohabits/\(cohabitId)/read",
                                                   body: ReadRequest(lastMessageId: last.id))
    }

    // MARK: - Schreiben

    /// Text und/oder Foto bzw. eigenes GIF. Ohne Netz in den Postausgang -
    /// die Nachricht steht dann mit Uhr unten im Chat.
    func send(text: String, attachment: ChatAttachment?) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || attachment != nil else { return false }
        sending = true
        defer { sending = false }
        var request = MessageRequest(text: trimmed.isEmpty ? nil : String(trimmed.prefix(2000)))
        var file = attachment?.uploadData
        do {
            if let data = file {
                let upload = try await api.uploadPhoto(data: data, key: UUID().uuidString.lowercased())
                switch attachment {
                case .photo(let image): PhotoLoader.shared.remember(image, id: upload.id)
                case .gif(let gif): PhotoLoader.shared.remember(fullData: gif, id: upload.id)
                case nil: break
                }
                request.photoId = upload.id
                file = nil
            }
            let message: Message = try await api.send("POST", path, body: request)
            merge([message])
            await markRead()
            return true
        } catch CohabitError.offline {
            await CohabitOutbox.shared.enqueueMessage(cohabitId: cohabitId, request: request, photo: file)
            return true
        } catch {
            Toast.shared.show(error)
            return false
        }
    }

    /// Ein GIF aus der Suche: sofort raus (kein Vorschauschritt), danach
    /// bekommt KLIPY sein `share` - feuern und vergessen.
    func sendGif(_ item: KlipyItem, query: String) async {
        guard let gif = item.gifInput else {
            Toast.shared.show("Das GIF ist ungültig.")
            return
        }
        let client = klipy
        let request = MessageRequest(text: nil, gif: gif)
        do {
            let message: Message = try await api.send("POST", path, body: request)
            merge([message])
            await markRead()
        } catch CohabitError.offline {
            await CohabitOutbox.shared.enqueueMessage(cohabitId: cohabitId, request: request, photo: nil)
        } catch {
            Toast.shared.show(error)
            return
        }
        if let client {
            Task.detached { await client.share(slug: item.slug, query: query) }
        }
    }

    func delete(_ message: Message) async {
        do {
            let updated: Message = try await api.delete("\(path)/\(message.id)")
            merge([updated])
        } catch {
            Toast.shared.show(error)
        }
    }

    func report(_ message: Message, reason: String) async {
        do {
            try await api.sendIgnoringResponse("POST", "\(path)/\(message.id)/report", body: ReportRequest(reason: reason))
            Toast.shared.show("Gemeldet")
        } catch {
            Toast.shared.show(error)
        }
    }

    func block(_ person: PersonView) async {
        do {
            try await api.sendIgnoringResponse("POST", "/blocks", body: PersonIdRequest(personId: person.id))
            Toast.shared.show("\(person.displayName) blockiert")
            await load()
        } catch {
            Toast.shared.show(error)
        }
    }

    /// Reagieren (Vertrag §2.7a): ein Emoji setzt die eigene Reaktion, das
    /// eigene noch einmal nimmt sie zurueck. Sofort sichtbar, ohne Netz im
    /// Postausgang.
    func react(_ emoji: String, on message: Message) async {
        await Reactions.choose(emoji, target: message.reactionTarget, current: message.reactions) { [weak self] list in
            self?.replaceReactions(list, of: message.id)
        }
    }

    /// Die eigene Reaktion zuruecknehmen („Entfernen" im Blatt „Reaktionen").
    func removeReaction(on message: Message) async {
        guard let mine = Reactions.mine(in: message.reactions) else { return }
        await react(mine, on: message)
    }

    private func replaceReactions(_ reactions: [ReactionView], of messageId: String) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index] = messages[index].with(reactions: reactions)
        }
    }

    /// „Gratulieren" im Abschlussdialog: 💪 auf die Systemmeldung zum Ende der
    /// Challenge (Vertrag §5.2.17, §2.7a). Der Dienst nennt die Meldung im
    /// Dialog (`reactionTarget`); fehlt sie, gilt die juengste Systemmeldung
    /// mit dem Namen des Gewinners, sonst die juengste ueberhaupt.
    static func congratulate(cohabitId: String, dialog: FinishedDialog) async {
        let api = Session.shared.api()
        if let target = dialog.reactionTarget {
            let request = ReactionRequest(target: target, reaction: Emoji.congratulate)
            do {
                let _: ReactionsResult = try await api.send("POST", "/reactions", body: request)
            } catch CohabitError.offline {
                await CohabitOutbox.shared.enqueueReaction(request, add: true)
            } catch {
                // weg oder nicht mehr sichtbar - der Chat zeigt ohnehin den Stand.
            }
            DataBus.shared.changed()
            return
        }
        let winner = dialog.podium.first?.person
        guard let page: MessagesPage = try? await api.get("/cohabits/\(cohabitId)/messages",
                                                          query: [URLQueryItem(name: "limit", value: "50")])
        else { return }
        let system = page.messages.filter { $0.kind == .system }.reversed()
        let target = system.first { message in
            guard let name = winner?.displayName else { return false }
            return message.systemText?.contains(name) ?? false
        } ?? system.first
        // Schon 💪 von mir - noch einmal gesetzt naehme es zurueck.
        guard let target, Reactions.mine(in: target.reactions) != Emoji.congratulate else { return }
        await Reactions.choose(Emoji.congratulate, target: target.reactionTarget, current: target.reactions) { _ in }
        DataBus.shared.changed()
    }
}

/// Was am Eingabefeld haengt: ein Foto (geht als JPEG) oder ein eigenes GIF
/// (geht unveraendert, damit es animiert bleibt - Vertrag §2.7a).
enum ChatAttachment {
    case photo(UIImage)
    case gif(Data)

    /// Aus der Galerie bzw. der Zwischenablage: ein GIF erkennt man am
    /// Dateianfang (`GIF8`) - der Typ, den die Quelle nennt, ist nur ein Hinweis.
    static func picked(_ data: Data) -> ChatAttachment? {
        if ImageFormat.sniff(data) == .gif { return .gif(data) }
        return UIImage(data: data).map(ChatAttachment.photo)
    }

    var isGif: Bool {
        if case .gif = self { return true }
        return false
    }

    /// Das Vorschaubild im Eingabefeld - beim GIF das erste Bild.
    var preview: UIImage? {
        switch self {
        case .photo(let image): image
        case .gif(let data): UIImage(data: data)
        }
    }

    /// Was hochgeht.
    var uploadData: Data? {
        switch self {
        case .photo(let image): PhotoEncoding.jpeg(image)
        case .gif(let data): data
        }
    }
}

struct ReadRequest: Encodable {
    let lastMessageId: String
}

struct ReportRequest: Encodable {
    let reason: String
}

/// Reaktionen auf Nachrichten und Timeline-Ereignisse - dieselbe Mechanik.
enum Reactions {

    /// Das eigene Emoji in der Liste.
    static func mine(in reactions: [ReactionView]) -> String? {
        reactions.first(where: \.mine)?.reaction
    }

    /// Setzt ein Emoji oder nimmt das eigene zurueck (dasselbe noch einmal).
    /// `show` bekommt erst den lokal gerechneten Stand - sofort sichtbar -,
    /// dann den des Dienstes; ohne Netz bleibt der lokale, und die Reaktion
    /// wartet im Postausgang. Lehnt der Dienst ab, kommt der alte Stand zurueck.
    @MainActor
    static func choose(_ emoji: String, target: String, current: [ReactionView],
                       show: @MainActor ([ReactionView]) -> Void) async {
        let emoji = Emoji.normalized(emoji)
        let removing = mine(in: current) == emoji
        let request = ReactionRequest(target: target, reaction: emoji)
        show(locally(current, setting: removing ? nil : emoji, me: Session.shared.me?.person))
        let api = Session.shared.api()
        do {
            let result: ReactionsResult
            if removing {
                result = try await api.delete("/reactions", query: [
                    URLQueryItem(name: "target", value: target),
                    URLQueryItem(name: "reaction", value: emoji),
                ])
            } else {
                result = try await api.send("POST", "/reactions", body: request)
            }
            show(result.reactions)
        } catch CohabitError.offline {
            await CohabitOutbox.shared.enqueueReaction(request, add: !removing)
        } catch {
            show(current)
            Toast.shared.show(error)
        }
    }

    /// Der Stand nach dem eigenen Tipp, ohne den Dienst: die eigene Reaktion
    /// raus, das neue Emoji (falls eins) rein - mehr rechnet die App nicht.
    /// Sortiert wie der Dienst nach Anzahl; bei Gleichstand bleibt die
    /// bisherige Reihenfolge, neue Emojis kommen hinten an.
    static func locally(_ reactions: [ReactionView], setting emoji: String?, me: PersonView?) -> [ReactionView] {
        var list: [ReactionView] = []
        for reaction in reactions {
            guard reaction.mine else {
                list.append(reaction)
                continue
            }
            let count = reaction.count - 1
            if count > 0 {
                list.append(ReactionView(reaction: reaction.reaction, label: reaction.label, count: count, mine: false,
                                         people: reaction.people.filter { $0.id != me?.id }))
            }
        }
        if let emoji {
            let people = me.map { [$0] } ?? []
            if let index = list.firstIndex(where: { $0.reaction == emoji }) {
                let old = list[index]
                list[index] = ReactionView(reaction: emoji, label: old.label, count: old.count + 1, mine: true,
                                           people: old.people + people)
            } else {
                list.append(ReactionView(reaction: emoji, count: 1, mine: true, people: people))
            }
        }
        return sorted(list)
    }

    /// Nach Anzahl absteigend, sonst in der bisherigen Reihenfolge.
    static func sorted(_ reactions: [ReactionView]) -> [ReactionView] {
        reactions.enumerated()
            .sorted { $0.element.count != $1.element.count ? $0.element.count > $1.element.count : $0.offset < $1.offset }
            .map(\.element)
    }

    /// Die Emojis der Pille: hoechstens drei, die haeufigsten zuerst.
    static func top(_ reactions: [ReactionView]) -> [String] {
        Array(sorted(reactions).prefix(3).map(\.reaction))
    }

    /// Alle Reaktionen zusammen - die Zahl in der Pille (erst ab zwei).
    static func total(_ reactions: [ReactionView]) -> Int {
        reactions.reduce(0) { $0 + $1.count }
    }
}

extension Message {
    func with(reactions: [ReactionView]) -> Message {
        Message(id: id, cohabitId: cohabitId, kind: kind, author: author, mine: mine, createdAt: createdAt,
                text: text, photoId: photoId, checkin: checkin, systemText: systemText,
                reactionTarget: reactionTarget, reactions: reactions, deleted: deleted, photoIds: photoIds,
                gif: gif, photoAnimated: photoAnimated)
    }
}
