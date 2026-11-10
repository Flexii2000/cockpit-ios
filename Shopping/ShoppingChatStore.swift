import Foundation

/// Der Rezept-Chat: eine Claude-Session auf dem Server schlaegt Rezepte vor.
///
/// Das Gespraech liegt beim Dienst - die App merkt sich nichts davon, auch nicht
/// im Offline-Stand. Eine Frage geht sofort raus (202), die Antwort entsteht im
/// Hintergrund; solange fragt die App alle zwei Sekunden nach (`GET /api/chat`),
/// wie die Weboberflaeche. Eine offene Anfrage ueber eine halbe Minute scheiterte
/// an nginx, ohne verwertbaren Fehler.
@MainActor
@Observable
final class ShoppingChatStore {

    /// Der Dienst gibt einer Antwort 120 s; etwas Luft fuer den Weg dazu.
    private static let deadline: Duration = .seconds(150)
    private static let interval: Duration = .seconds(2)

    private let api = ShoppingAPI()

    private(set) var chat: ShoppingChat?
    /// Die eigene Nachricht, solange der Dienst sie nicht bestaetigt hat.
    private(set) var pending: ShoppingChatPending?
    /// Warum das Senden scheiterte - in den Worten des Dienstes, wenn er welche hat.
    private(set) var sendError: String?
    /// Die Nachfrage hat aufgegeben, obwohl der Dienst noch „laeuft“ meldet.
    private(set) var stalled = false

    @ObservationIgnored private var poll: Task<Void, Never>?

    /// Ob die Person den Chat benutzen kann - sonst zeigt die App ihn gar nicht.
    /// Ohne Antwort des Dienstes (kein Netz) auch nicht: der Chat braucht ihn.
    var isAvailable: Bool { chat?.available == true }

    var rows: [ShoppingChatRow] {
        ShoppingChatTimeline.rows(chat: chat, pending: pending, sendError: sendError, stalled: stalled)
    }

    var isBusy: Bool {
        ShoppingChatTimeline.isBusy(chat: chat, pending: pending, sendError: sendError, stalled: stalled)
    }

    var isEmpty: Bool { rows.isEmpty }

    /// Holt das Gespraech und fragt weiter nach, falls gerade eine Antwort entsteht -
    /// beim Oeffnen der Rezepte (ob es den Chat gibt) und des Chats selbst.
    func load() async {
        await refresh()
        if chat?.job?.isRunning == true, !stalled { startPolling() }
    }

    /// Der Chat ist nicht mehr zu sehen: nicht weiter nachfragen. Die Antwort
    /// entsteht beim Dienst trotzdem und steht beim naechsten Oeffnen da.
    func pause() {
        poll?.cancel()
        poll = nil
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }
        await post(ShoppingChatPending(id: UUID().uuidString.lowercased(), text: trimmed))
    }

    /// Dieselbe Nachricht mit derselben Kennung noch einmal - der Dienst haengt
    /// nichts an, er fordert nur die Antwort neu an.
    func retry() async {
        guard !isBusy, let message = ShoppingChatTimeline.retry(chat: chat, pending: pending) else { return }
        await post(message)
    }

    /// „Neu“: der Dienst leert das Gespraech und verwirft, was noch unterwegs war.
    func reset() async {
        pause()
        do {
            chat = try await api.resetChat()
            pending = nil
            sendError = nil
            stalled = false
        } catch {
            NoticeCenter.shared.show(error.localizedDescription)
        }
    }

    /// Das Gespraech neu holen. Scheitert das, bleibt stehen, was zu sehen ist.
    func refresh() async {
        guard let fresh = try? await api.chat() else { return }
        chat = fresh
        if let pending, fresh.messages.contains(where: { $0.id == pending.id }) {
            // Angekommen, auch wenn die Antwort auf das Senden verloren ging.
            self.pending = nil
            sendError = nil
        }
        if fresh.job?.isRunning != true { stalled = false }
    }

    // MARK: - Innereien

    private func post(_ message: ShoppingChatPending) async {
        pause()
        pending = message
        sendError = nil
        stalled = false
        do {
            chat = try await api.sendChat(text: message.text, id: message.id)
            pending = nil
            startPolling()
        } catch {
            sendError = error.localizedDescription
        }
    }

    private func startPolling() {
        poll?.cancel()
        poll = Task { [weak self] in
            let clock = ContinuousClock()
            let end = clock.now.advanced(by: Self.deadline)
            while clock.now < end {
                try? await Task.sleep(for: Self.interval)
                guard !Task.isCancelled, let self else { return }
                await self.refresh()
                if self.chat?.job?.isRunning != true { return }
            }
            guard !Task.isCancelled, let self else { return }
            // Der Dienst meldet nach 150 s noch „laeuft“: nicht ewig drehen.
            self.stalled = true
        }
    }
}
