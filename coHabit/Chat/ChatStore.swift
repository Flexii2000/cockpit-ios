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

    init(cohabitId: String) {
        self.cohabitId = cohabitId
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

    /// Text und/oder Foto. Ohne Netz in den Postausgang - die Nachricht steht
    /// dann mit Uhr unten im Chat.
    func send(text: String, photo: UIImage?) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || photo != nil else { return false }
        sending = true
        defer { sending = false }
        var request = MessageRequest(text: trimmed.isEmpty ? nil : String(trimmed.prefix(2000)))
        var jpeg = photo.flatMap { PhotoEncoding.jpeg($0) }
        do {
            if let data = jpeg {
                let upload = try await api.uploadPhoto(jpeg: data, key: UUID().uuidString.lowercased())
                if let photo { PhotoLoader.shared.remember(photo, id: upload.id) }
                request.photoId = upload.id
                jpeg = nil
            }
            let message: Message = try await api.send("POST", path, body: request)
            merge([message])
            await markRead()
            return true
        } catch CohabitError.offline {
            await CohabitOutbox.shared.enqueueMessage(cohabitId: cohabitId, request: request, photo: jpeg)
            return true
        } catch {
            Toast.shared.show(error)
            return false
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

    /// Reagieren - sofort sichtbar, ohne Netz im Postausgang.
    func toggle(_ reaction: ReactionKind, on message: Message) async {
        let mine = message.reactions.first { $0.reaction == reaction }?.mine ?? false
        let updated = await Reactions.toggle(reaction, target: message.reactionTarget,
                                             current: message.reactions, mine: mine)
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = messages[index].with(reactions: updated)
        }
    }

    /// „Gratulieren" im Abschlussdialog: „Stark" auf die Systemmeldung zum
    /// Ende der Challenge (Vertrag §5.2.17). Die Meldung selbst hat keine
    /// Kennung im Dialog - gesucht wird die juengste Systemmeldung mit dem
    /// Namen des Gewinners, sonst die juengste ueberhaupt.
    static func congratulate(cohabitId: String, winner: PersonView?) async {
        let api = Session.shared.api()
        guard let page: MessagesPage = try? await api.get("/cohabits/\(cohabitId)/messages",
                                                          query: [URLQueryItem(name: "limit", value: "50")])
        else { return }
        let system = page.messages.filter { $0.kind == .system }.reversed()
        let target = system.first { message in
            guard let name = winner?.displayName else { return false }
            return message.systemText?.contains(name) ?? false
        } ?? system.first
        guard let target, !(target.reactions.first { $0.reaction == .stark }?.mine ?? false) else { return }
        _ = await Reactions.toggle(.stark, target: target.reactionTarget, current: target.reactions, mine: false)
        DataBus.shared.changed()
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

    /// Setzt oder nimmt eine Reaktion und liefert die neue Liste. Ohne Netz
    /// wird lokal gezaehlt und im Postausgang nachgereicht.
    @MainActor
    static func toggle(_ reaction: ReactionKind, target: String, current: [ReactionView], mine: Bool) async -> [ReactionView] {
        let api = Session.shared.api()
        let request = ReactionRequest(target: target, reaction: reaction)
        do {
            let result: ReactionsResult
            if mine {
                result = try await api.delete("/reactions", query: [
                    URLQueryItem(name: "target", value: target),
                    URLQueryItem(name: "reaction", value: reaction.rawValue),
                ])
            } else {
                result = try await api.send("POST", "/reactions", body: request)
            }
            return result.reactions
        } catch CohabitError.offline {
            await CohabitOutbox.shared.enqueueReaction(request, add: !mine)
            return locally(current, reaction: reaction, add: !mine)
        } catch {
            Toast.shared.show(error)
            return current
        }
    }

    /// Plus oder minus eins - mehr rechnet die App nicht.
    static func locally(_ reactions: [ReactionView], reaction: ReactionKind, add: Bool) -> [ReactionView] {
        var list = reactions
        if let index = list.firstIndex(where: { $0.reaction == reaction }) {
            let old = list[index]
            let count = max(0, old.count + (add ? 1 : -1))
            if count == 0 {
                list.remove(at: index)
            } else {
                list[index] = ReactionView(reaction: reaction, label: old.label, count: count, mine: add)
            }
        } else if add {
            list.append(ReactionView(reaction: reaction, label: reaction.label, count: 1, mine: true))
        }
        return list
    }
}

extension Message {
    func with(reactions: [ReactionView]) -> Message {
        Message(id: id, cohabitId: cohabitId, kind: kind, author: author, mine: mine, createdAt: createdAt,
                text: text, photoId: photoId, checkin: checkin, systemText: systemText,
                reactionTarget: reactionTarget, reactions: reactions, deleted: deleted)
    }
}
