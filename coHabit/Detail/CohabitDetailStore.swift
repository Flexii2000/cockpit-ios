import Foundation

/// Ein Co-Habit mit allem, was seine Detailseite braucht (`GET /cohabits/{id}`).
@MainActor
@Observable
final class CohabitDetailStore {

    let cohabitId: String
    private(set) var detail: CohabitDetail?
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    /// Weg (geloescht, verlassen) - die Seite geht dann zu.
    private(set) var isGone = false

    init(cohabitId: String) {
        self.cohabitId = cohabitId
    }

    private var api: CohabitAPI { Session.shared.api() }
    private var path: String { "/cohabits/\(cohabitId)" }

    func load() async {
        isLoading = detail == nil
        defer { isLoading = false }
        do {
            apply(try await api.get(path))
            errorMessage = nil
        } catch {
            if await Session.shared.handle(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    func apply(_ detail: CohabitDetail) {
        self.detail = detail
        CohabitGroup.remember(zone: detail.config.timezone, for: detail.id)
        CohabitHealthSync.shared.update(from: detail)
    }

    /// Fuehrt eine Aenderung aus, die mit dem neuen Detail antwortet.
    @discardableResult
    func change(_ method: String, _ suffix: String, body: some Encodable & Sendable) async -> Bool {
        do {
            let updated: CohabitDetail = try await api.send(method, path + suffix, body: body)
            apply(updated)
            DataBus.shared.changed()
            return true
        } catch {
            if await Session.shared.handle(error) { return false }
            Toast.shared.show(error)
            return false
        }
    }

    // MARK: - Einstellungen

    func save(config: CohabitConfig) async -> Bool {
        await change("PUT", "", body: UpdateCohabitRequest(config: config))
    }

    func save(settings: MySettings) async {
        await change("PUT", "/settings/me", body: settings)
        if detail?.config.health != nil {
            Task { await CohabitHealthSync.shared.sync(only: cohabitId) }
        }
    }

    /// Health einschalten: erst der System-Dialog, dann die Einwilligung beim
    /// Dienst, dann der erste Abgleich.
    func enableHealth() async {
        guard var settings = detail?.mySettings else { return }
        await CohabitHealthSync.shared.requestAuthorization()
        settings.healthConsent = true
        await save(settings: settings)
        await CohabitHealthSync.shared.sync(only: cohabitId)
        await load()
    }

    func archive(_ archived: Bool) async {
        await change("POST", archived ? "/archive" : "/unarchive", body: CohabitAPI.EmptyBody())
    }

    func delete() async -> Bool {
        do {
            try await api.sendIgnoringResponse("DELETE", path, body: ConfirmRequest(confirm: true))
            gone()
            return true
        } catch {
            Toast.shared.show(error)
            return false
        }
    }

    func leave() async -> Bool {
        do {
            try await api.sendIgnoringResponse("DELETE", path + "/members/me")
            gone()
            return true
        } catch {
            Toast.shared.show(error)
            return false
        }
    }

    private func gone() {
        isGone = true
        CohabitHealthSync.shared.remove(cohabitId)
        DataBus.shared.changed()
        Task { await WidgetSync.refresh() }
    }

    // MARK: - Mitglieder

    func remove(member: PersonView) async {
        do {
            try await api.sendIgnoringResponse("DELETE", path + "/members/\(member.id)")
            await load()
            DataBus.shared.changed()
        } catch {
            Toast.shared.show(error)
        }
    }

    func makeAdmin(_ person: PersonView) async {
        await change("PUT", "/admin", body: PersonIdRequest(personId: person.id))
    }

    func nudge(_ person: PersonView, text: String?) async {
        do {
            try await api.sendIgnoringResponse("POST", path + "/nudges", body: NudgeRequest(to: person.id, text: text))
            Toast.shared.show("\(person.displayName) angestupst")
        } catch {
            Toast.shared.show(error)
        }
    }

    // MARK: - Pausen

    func addPause(from: CalendarDate, to: CalendarDate) async -> Bool {
        await change("POST", "/pauses", body: PauseRequest(from: from, to: to))
    }

    func removePause(_ pause: Pause) async {
        do {
            let updated: CohabitDetail = try await api.delete(path + "/pauses/\(pause.id)")
            apply(updated)
            DataBus.shared.changed()
        } catch CohabitError.decoding {
            // 204 statt Detail - dann eben neu laden.
            await load()
        } catch {
            Toast.shared.show(error)
        }
    }

    // MARK: - Eigene Eintraege

    func update(_ checkin: Checkin, _ update: CheckinUpdate) async -> Bool {
        do {
            let result: CheckinResult = try await api.send("PUT", path + "/checkins/\(checkin.id)", body: update)
            apply(result.cohabit)
            DataBus.shared.changed()
            return true
        } catch {
            Toast.shared.show(error)
            return false
        }
    }

    func delete(_ checkin: Checkin) async {
        do {
            let updated: CohabitDetail = try await api.delete(path + "/checkins/\(checkin.id)")
            apply(updated)
            DataBus.shared.changed()
            Task { await WidgetSync.refresh() }
        } catch {
            Toast.shared.show(error)
        }
    }

    // MARK: - Abschlussdialog

    func markDialogSeen(_ dialog: FinishedDialog) async {
        try? await api.sendIgnoringResponse("POST", path + "/dialogs/\(dialog.id)/seen")
    }
}

struct ConfirmRequest: Encodable {
    let confirm: Bool
}

struct PersonIdRequest: Encodable {
    let personId: String
}

struct PauseRequest: Encodable {
    let from: CalendarDate
    let to: CalendarDate
}
