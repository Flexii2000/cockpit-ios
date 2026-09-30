import XCTest
@testable import coHabit

/// Dekodieren der Vertrags-JSONs und Kodieren dessen, was die App schickt.
final class ModelTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIClient.decoder().decode(T.self, from: Fixtures.data(json))
    }

    private func object(_ value: some Encodable) throws -> [String: Any] {
        let data = try APIClient.encoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Dekodieren

    func testMeView() throws {
        let me = try decode(MeView.self, Fixtures.me)
        XCTAssertEqual(me.person.id, "felix")
        XCTAssertEqual(me.person.color, .periwinkle)
        XCTAssertEqual(me.sources, ["FOOD", "STEPS_WEEKLY", "FOCUS"])
        XCTAssertEqual(me.counts.wins, 3)
        XCTAssertEqual(me.pendingInvitations, 1)
        XCTAssertNotNil(me.createdAt)
    }

    func testSummary() throws {
        let summary = try decode(CohabitSummary.self, Fixtures.summary)
        XCTAssertEqual(summary.ref.type, .streak)
        XCTAssertEqual(summary.headline.short, "6 Wo.")
        XCTAssertEqual(summary.status, .open)
        XCTAssertEqual(summary.section, .openToday)
        XCTAssertEqual(summary.progress?.goal, 3)
        XCTAssertNil(summary.rank)
        XCTAssertTrue(summary.showsCheckButton)
        XCTAssertEqual(summary.doneTodayBy, ["lena", "max"])
    }

    func testStreakDetail() throws {
        let detail = try decode(CohabitDetail.self, Fixtures.streakDetail)
        XCTAssertEqual(detail.id, "c-3f2a")
        XCTAssertTrue(detail.isAdmin)
        XCTAssertEqual(detail.config.streak?.rhythm.kind, "TIMES_PER_WEEK")
        XCTAssertEqual(detail.config.streak?.rhythm.times, 3)
        XCTAssertEqual(detail.config.reminderTime, "07:30")
        XCTAssertEqual(detail.streak?.week?.rows.first?.cells[2], .open)
        XCTAssertEqual(detail.streak?.week?.rows.last?.cells, [.done, .missed, .done, .future, .future, .paused, .notDue])
        XCTAssertEqual(detail.streak?.week?.days.first, CalendarDate(year: 2026, month: 9, day: 28))
        XCTAssertEqual(detail.streak?.record?.person?.id, "lena")
        XCTAssertEqual(detail.streak?.group?.current, 2)
        XCTAssertEqual(detail.health?.shareText, "nur die Schrittzahl wird geteilt")
        XCTAssertEqual(detail.myCheckins.first?.caption, "Regenlauf zählt doppelt.")
        XCTAssertEqual(detail.backfillFrom, CalendarDate(year: 2026, month: 9, day: 28))
        XCTAssertEqual(detail.myPauses.first?.to, CalendarDate(year: 2026, month: 10, day: 17))
        XCTAssertNil(detail.mySettings.checkins)
        XCTAssertNil(detail.dialog)
    }

    func testTypeBlocks() throws {
        let abstinence = try decode(AbstinenceBlock.self, Fixtures.abstinence)
        XCTAssertEqual(abstinence.currentDays, 23)
        XCTAssertEqual(abstinence.series.last?.current, true)
        XCTAssertEqual(abstinence.group?.days, 12)

        let goal = try decode(GoalBlock.self, Fixtures.goal)
        XCTAssertEqual(goal.percent, 68)
        XCTAssertEqual(goal.deadline, CalendarDate(year: 2026, month: 10, day: 31))
        XCTAssertEqual(goal.contributions.first?.valueText, "24.800")
        XCTAssertNil(goal.finished)

        let challenge = try decode(ChallengeBlock.self, Fixtures.challenge)
        XCTAssertEqual(challenge.myRank, 2)
        XCTAssertEqual(challenge.leaderboard.first?.score, 9)
        XCTAssertEqual(challenge.pastRounds.first?.winners.first?.displayName, "Lena")
        XCTAssertNotNil(challenge.endsAt)

        let dialog = try decode(FinishedDialog.self, Fixtures.dialog)
        XCTAssertTrue(dialog.isChallenge)
        XCTAssertEqual(dialog.podium.first?.rank, 1)
        XCTAssertNil(dialog.reactionTarget, "zusaetzliches Feld des Dienstes - darf fehlen")
    }

    func testInvitationsAndPreview() throws {
        let invitation = try decode(InvitationView.self, Fixtures.invitation)
        XCTAssertEqual(invitation.cohabit.seats.free, 6)
        let preview = try decode(InviteLinkPreview.self, Fixtures.preview)
        XCTAssertFalse(preview.isFriendLink)
        XCTAssertEqual(preview.cohabit?.ref.name, "Laufen")
        let friendLink = try decode(InviteLinkPreview.self, #"{"kind":"FRIEND","from":\#(Fixtures.lena),"cohabit":null,"full":false}"#)
        XCTAssertTrue(friendLink.isFriendLink)
    }

    func testMessagesIncludingUnknownKind() throws {
        let page = try decode(MessagesPage.self, Fixtures.messages)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.messages.map(\.kind), [.checkin, .text, .system, .system],
                       "eine unbekannte Art darf den Chat nicht leeren")
        XCTAssertEqual(page.messages[0].checkin?.photoId, "p1")
        XCTAssertEqual(page.messages[0].reactions.first?.reaction, .stark)
        XCTAssertTrue(page.messages[1].mine)
        XCTAssertEqual(page.messages[2].systemText, "Lena hat eine neue Bestserie: 9 Wochen")
        // Ohne hasMore (Abfrage mit ?after=) gibt es nichts Aelteres.
        let newer = try decode(MessagesPage.self, #"{"messages":[]}"#)
        XCTAssertFalse(newer.hasMore)
    }

    func testTodayTimelineStatsWidget() throws {
        let today = try decode(Today.self, Fixtures.today)
        XCTAssertEqual(today.openCount, 2)
        XCTAssertEqual(today.nudges.first?.text, "Heute noch kochen?")
        XCTAssertEqual(today.newPhotos?.photoIds.count, 2)
        XCTAssertEqual(today.invitations.count, 1)

        let timeline = try decode(TimelinePage.self, Fixtures.timeline)
        XCTAssertEqual(timeline.items.first?.kind, .photoCheckin)
        XCTAssertEqual(timeline.items.last?.kind, .health)
        XCTAssertNil(timeline.items.last?.person)

        let stats = try decode(Stats.self, Fixtures.stats)
        XCTAssertEqual(stats.range, .month)
        XCTAssertEqual(stats.heatmap.days.first?.level, 1)
        XCTAssertEqual(stats.cohabits.first?.progressText, "11/13")

        let widget = try decode(WidgetData.self, Fixtures.widget)
        XCTAssertEqual(widget.cohabits.first?.status, .open)
        XCTAssertEqual(widget.challenge?.myRank, 2)
        XCTAssertEqual(widget.teamGoal?.percent, 68)
    }

    func testSocialShapes() throws {
        let friends = try decode(FriendsOverview.self, Fixtures.friends)
        XCTAssertEqual(friends.incoming.first?.from.id, "torben")
        let candidates = try decode(InviteCandidates.self, Fixtures.candidates)
        XCTAssertTrue(candidates.people[0].isMember)
        XCTAssertFalse(candidates.people[1].isInvited)
        let results = try decode([PersonSearchResult].self, #"[{"person":\#(Fixtures.lena),"relation":"REQUEST_SENT"},{"person":\#(Fixtures.person),"relation":"WHATEVER"}]"#)
        XCTAssertEqual(results.map(\.relation), [.requestSent, .none])
        let link = try decode(AppLink.self, #"{"id":"a1","label":"iPhone","createdAt":"2026-09-30T10:00:00Z","lastUsedAt":null}"#)
        XCTAssertNil(link.lastUsedAt)
        let accepted = try decode(AcceptResult.self, #"{"me":\#(Fixtures.me),"token":"abc","setupUrl":null,"cohabitId":"c-1"}"#)
        XCTAssertEqual(accepted.token, "abc")
    }

    func testLenientEnumsFallBack() throws {
        let ref = try decode(CohabitRef.self, #"{"id":"x","name":"X","color":"lavender","type":"MARATHON"}"#)
        XCTAssertEqual(ref.color, PaletteKey.fallback)
        XCTAssertEqual(ref.type, CohabitType.fallback)
        let cells = try decode([WeekCell].self, #"["DONE","SOMETHING_NEW"]"#)
        XCTAssertEqual(cells, [.done, .future])
    }

    func testInstantsWithFractionsDecode() throws {
        let checkin = try decode(Checkin.self, Fixtures.checkin.replacingOccurrences(
            of: "2026-09-30T05:12:00Z", with: "2026-09-30T05:12:00.123456789Z"))
        XCTAssertNotNil(checkin.createdAt)
    }

    /// Was das Backend ueber den Vertrag hinaus liefert (BACKEND-NOTES.md):
    /// eingeladene und pausierte Mitglieder, Abschlussdialog fuer Ziele mit
    /// dem Ziel fuer „Gratulieren".
    func testBackendAdditions() throws {
        let invited = try decode(Member.self, #"{"person":\#(Fixtures.lena),"role":"MEMBER","state":"INVITED","joinedAt":null}"#)
        XCTAssertNil(invited.joinedAt)
        XCTAssertEqual(MembersSheet.stateText(invited.state), " · eingeladen")
        let paused = try decode(Member.self, #"{"person":\#(Fixtures.lena),"role":"MEMBER","state":"PAUSED","joinedAt":"2026-09-02T10:00:00Z"}"#)
        XCTAssertEqual(MembersSheet.stateText(paused.state), " · pausiert")
        XCTAssertEqual(MembersSheet.stateText("SOMETHING_NEW"), "")

        let goal = try decode(FinishedDialog.self, #"{"id":"goal-1","kind":"GOAL","title":"Ziel erreicht","podium":[],"stakeText":null,"nextText":null,"reactionTarget":"message:m9"}"#)
        XCTAssertFalse(goal.isChallenge)
        XCTAssertEqual(goal.reactionTarget, "message:m9")
        XCTAssertTrue(goal.podium.isEmpty)
    }

    // MARK: - Kodieren

    func testConfigSendsEveryKeyWithNulls() throws {
        let config = try decode(CohabitConfig.self, Fixtures.config)
        let json = try object(config)
        for key in ["abstinence", "goal", "challenge", "health", "auto"] {
            XCTAssertTrue(json[key] is NSNull, "\(key) muss als null ankommen")
        }
        XCTAssertEqual(json["reminderTime"] as? String, "07:30")
        let streak = try XCTUnwrap(json["streak"] as? [String: Any])
        let rhythm = try XCTUnwrap(streak["rhythm"] as? [String: Any])
        XCTAssertEqual(rhythm["kind"] as? String, "TIMES_PER_WEEK")
        XCTAssertEqual(rhythm["times"] as? Int, 3)
        XCTAssertNil(rhythm["weekdays"], "nur die Felder, die zur Art gehoeren")
        let tracking = try XCTUnwrap(json["tracking"] as? [String: Any])
        XCTAssertNil(tracking["unit"])
    }

    func testCreateRequestAddsInvitesAndUpdateKeepsType() throws {
        var config = CohabitConfig.draft(.challenge, today: CalendarDate(year: 2026, month: 9, day: 30))
        config.name = "Wer kocht öfter?"
        config.challenge?.target = 50
        let create = try object(CreateCohabitRequest(config: config, invitePersonIds: ["torben"]))
        XCTAssertEqual(create["invitePersonIds"] as? [String], ["torben"])
        XCTAssertEqual(create["type"] as? String, "CHALLENGE")
        let challenge = try XCTUnwrap(create["challenge"] as? [String: Any])
        XCTAssertEqual(challenge["start"] as? String, "2026-09-30")
        XCTAssertEqual(challenge["end"] as? String, "2026-10-30")
        XCTAssertTrue(challenge["target"] is NSNull, "Zielwert nur bei FIRST_TO_TARGET")
        XCTAssertTrue(challenge["stake"] is NSNull)

        let update = try object(UpdateCohabitRequest(config: config))
        XCTAssertEqual(update["type"] as? String, "CHALLENGE")
        XCTAssertNil(update["invitePersonIds"])
    }

    func testRhythmEncodesOnlyItsFields() throws {
        let weekdays = try object(CohabitConfig.Rhythm(kind: "WEEKDAYS", weekdays: [1, 3, 5], times: 3))
        XCTAssertEqual(weekdays["weekdays"] as? [Int], [1, 3, 5])
        XCTAssertNil(weekdays["times"])
        let interval = try object(CohabitConfig.Rhythm(kind: "INTERVAL"))
        XCTAssertEqual(interval["days"] as? Int, 2)
        let daily = try object(CohabitConfig.Rhythm.daily)
        XCTAssertEqual(daily.count, 1)
    }

    func testCheckinRequestAndSettingsSendNulls() throws {
        let request = CheckinRequest(id: "u1", date: CalendarDate(year: 2026, month: 9, day: 30), value: 8200)
        let json = try object(request)
        XCTAssertEqual(json["id"] as? String, "u1")
        XCTAssertEqual(json["kind"] as? String, "DONE")
        XCTAssertEqual(json["date"] as? String, "2026-09-30")
        XCTAssertEqual(json["value"] as? Double, 8200)
        XCTAssertTrue(json["photoId"] is NSNull)
        XCTAssertTrue(json["caption"] is NSNull)

        let settings = try object(MySettings(muted: false, checkins: nil, chat: true, shareBreaks: false, healthConsent: true))
        XCTAssertTrue(settings["checkins"] is NSNull, "null heisst „wie global“")
        XCTAssertEqual(settings["chat"] as? Bool, true)

        let message = try object(MessageRequest(id: "m", text: "Hi"))
        XCTAssertTrue(message["photoId"] is NSNull)
        XCTAssertFalse(CheckinRequest().id.isEmpty, "die Kennung vergibt die App")
    }

    func testDraftDefaults() {
        let today = CalendarDate(year: 2026, month: 9, day: 30)
        let goal = CohabitConfig.draft(.goal, today: today)
        XCTAssertEqual(goal.timezone, "Europe/Berlin")
        XCTAssertEqual(goal.color, .periwinkle)
        XCTAssertEqual(goal.goal?.start, today)
        XCTAssertEqual(goal.goal?.deadline, today.adding(days: 30))
        XCTAssertEqual(CohabitConfig.draft(.abstinence).abstinence?.groupMode, false)
        XCTAssertEqual(CohabitConfig.draft(.streak).streak?.rhythm.kind, "DAILY")
        XCTAssertEqual(CohabitConfig.backfillChoices, [0, 24, 48, 72, 168, 336])
    }
}
