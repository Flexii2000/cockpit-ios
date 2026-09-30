import Foundation

/// Die JSON-Formen aus dem Vertrag (§3), so wie der Dienst sie liefert -
/// weicht ein Schluessel ab, faellt es hier auf und nicht als leerer
/// Bildschirm auf dem Handy.
enum Fixtures {

    static let person = #"{"id":"torben","displayName":"Torben","username":"torben","initials":"TO","color":"mint","avatarPhotoId":null}"#
    static let lena = #"{"id":"lena","displayName":"Lena","username":"lena.k","initials":"LK","color":"peach","avatarPhotoId":"p-av1"}"#
    static let felix = #"{"id":"felix","displayName":"Felix","username":"felix","initials":"FE","color":"periwinkle","avatarPhotoId":null}"#

    static let ref = #"{"id":"c-3f2a","name":"Laufen","color":"peach","type":"STREAK"}"#

    static let me = """
    {"person":\(felix),"isOwner":true,"sources":["FOOD","STEPS_WEEKLY","FOCUS"],
     "counts":{"cohabits":4,"friends":5,"wins":3},
     "pendingInvitations":1,"incomingFriendRequests":0,"canLogout":false,
     "createdAt":"2026-09-30T12:00:00Z"}
    """

    static let summary = """
    {"ref":\(ref),"archived":false,
     "headline":{"value":"6","unit":"Wochen","short":"6 Wo."},
     "typeLine":"Streak · 3× pro Woche",
     "subline":"Lena & Max heute schon",
     "listLine":"2 von 3 · Foto",
     "status":"OPEN","section":"OPEN_TODAY","unavailableText":null,
     "canCheckIn":true,"photoRequired":true,"valueUnit":null,
     "checkInLabel":"Beweisfoto & abhaken",
     "members":[\(lena),\(felix)],"memberCount":3,
     "doneTodayBy":["lena","max"],
     "progress":{"done":2,"goal":3,"fraction":0.67},
     "rank":null,
     "unreadMessages":2}
    """

    static let config = """
    {"type":"STREAK","name":"Laufen","color":"peach","timezone":"Europe/Berlin",
     "tracking":{"mode":"CHECK"},"photoRequired":true,"backfillHours":48,"reminderTime":"07:30",
     "membersCanInvite":false,
     "streak":{"rhythm":{"kind":"TIMES_PER_WEEK","times":3},"groupStreak":false},
     "abstinence":null,"goal":null,"challenge":null,"health":null,"auto":null}
    """

    static let checkin = """
    {"id":"k1","cohabitId":"c-3f2a","person":\(felix),"kind":"DONE","date":"2026-09-30",
     "createdAt":"2026-09-30T05:12:00Z","value":null,"valueText":null,"note":null,"photoId":"p1",
     "caption":"Regenlauf zählt doppelt.","source":"MANUAL","editable":true}
    """

    static let streakDetail = """
    {"summary":\(summary),"config":\(config),
     "createdBy":"felix","createdAt":"2026-09-01T10:00:00Z","myRole":"ADMIN","canInvite":true,
     "seats":{"used":3,"max":8},
     "members":[{"person":\(felix),"role":"ADMIN","state":"ACTIVE","joinedAt":"2026-09-01T10:00:00Z"},
                {"person":\(lena),"role":"MEMBER","state":"ACTIVE","joinedAt":"2026-09-02T10:00:00Z"}],
     "rules":["Beweisfoto-Pflicht","Nachtragen bis 48 h","Europe/Berlin","Erinnerung 07:30"],
     "streak":{"current":6,"unit":"WEEKS","unitLabel":"Wochen","atRisk":true,
       "remainingText":"noch 1 Eintrag diese Woche",
       "week":{"days":["2026-09-28","2026-09-29","2026-09-30","2026-10-01","2026-10-02","2026-10-03","2026-10-04"],
               "todayIndex":2,
               "rows":[{"person":\(felix),"cells":["DONE","DONE","OPEN","FUTURE","FUTURE","FUTURE","FUTURE"]},
                       {"person":\(lena),"cells":["DONE","MISSED","DONE","FUTURE","FUTURE","PAUSED","NOT_DUE"]}]},
       "fulfillmentRate":86,
       "record":{"value":9,"short":"9 Wo.","person":\(lena)},
       "group":{"current":2,"unitLabel":"Wochen"}},
     "abstinence":null,"goal":null,"challenge":null,
     "health":{"metric":"STEPS","label":"Schritte","consent":true,"lastSyncAt":"2026-09-30T12:02:00Z",
               "shareText":"nur die Schrittzahl wird geteilt"},
     "myCheckins":[\(checkin)],
     "backfillFrom":"2026-09-28",
     "myPauses":[{"id":"pa1","from":"2026-10-10","to":"2026-10-17"}],
     "mySettings":{"muted":false,"checkins":null,"chat":null,"shareBreaks":false,"healthConsent":false},
     "unreadMessages":2,
     "dialog":null}
    """

    static let abstinence = """
    {"currentDays":23,"record":41,"toRecordText":"noch 18 bis zum Rekord",
     "members":[{"person":\(felix),"days":23,"newPersonalRecord":false}],
     "series":[{"label":"Mai","days":12,"current":false},{"label":"aktuell","days":23,"current":true}],
     "group":{"days":12}}
    """

    static let goal = """
    {"target":100000,"targetText":"100.000","unitLabel":"Schritte","deadline":"2026-10-31",
     "counting":"AMOUNT","mode":"TEAM","typeLine":"Teamziel · bis 31.10.",
     "total":68400,"totalText":"68.400 von 100.000","percent":68,
     "planDelta":2400,"planDeltaText":"+2.400 vor Plan","remainingDays":31,"remainingText":"noch 31 Tage",
     "contributions":[{"person":\(lena),"value":24800,"valueText":"24.800","fraction":1.0}],
     "finished":null}
    """

    static let challenge = """
    {"round":3,"start":"2026-09-01","end":"2026-09-30","endsAt":"2026-09-30T21:59:59Z",
     "endsInText":"endet in 9 Std. 41 Min.","periodLabel":"September",
     "scoring":"MOST_ENTRIES","scoringText":"Meiste Einträge","target":null,
     "stake":"Verlierer kocht für alle","recurrence":"MONTHLY","recurrenceText":"startet jeden Monat neu",
     "myRank":2,"leaderboard":[{"rank":1,"person":\(lena),"score":9,"scoreText":"9","fraction":1.0}],
     "pastRounds":[{"label":"August","winners":[\(lena)]}],"finished":false}
    """

    static let dialog = """
    {"id":"challenge-2","kind":"CHALLENGE",
     "title":"Lena gewinnt „Wer kocht öfter?“",
     "podium":[{"rank":1,"person":\(lena),"score":9,"scoreText":"9"}],
     "stakeText":"Verlierer kocht für alle: Sara ist dran.",
     "nextText":"Die nächste Runde startet am 1. Oktober automatisch."}
    """

    static let invitation = """
    {"id":"i1","from":\(lena),"createdAt":"2026-09-30T08:00:00Z",
     "cohabit":{"ref":\(ref),"typeLine":"Streak · 3× pro Woche","rules":["Beweisfoto-Pflicht"],
                "members":[\(lena)],"seats":{"used":2,"max":8}}}
    """

    static let preview = """
    {"kind":"COHABIT","from":\(lena),
     "cohabit":{"ref":\(ref),"typeLine":"Streak · 3× pro Woche","rules":["Beweisfoto-Pflicht"],
                "members":[\(lena)],"seats":{"used":2,"max":8}},
     "full":false}
    """

    static let messages = """
    {"messages":[
      {"id":"m1","cohabitId":"c-3f2a","kind":"CHECKIN","author":\(lena),"mine":false,
       "createdAt":"2026-09-30T05:12:00Z","text":null,"photoId":"p1","checkin":\(checkin),
       "systemText":null,"reactionTarget":"event:e1",
       "reactions":[{"reaction":"STARK","label":"Stark","count":2,"mine":true}],"deleted":false},
      {"id":"m2","cohabitId":"c-3f2a","kind":"TEXT","author":\(felix),"mine":true,
       "createdAt":"2026-09-30T06:00:00Z","text":"Bin dabei!","photoId":null,"checkin":null,
       "systemText":null,"reactionTarget":"message:m2","reactions":[],"deleted":false},
      {"id":"m3","cohabitId":"c-3f2a","kind":"SYSTEM","author":null,"mine":false,
       "createdAt":"2026-09-30T06:10:00Z","text":null,"photoId":null,"checkin":null,
       "systemText":"Lena hat eine neue Bestserie: 9 Wochen","reactionTarget":"message:m3",
       "reactions":[],"deleted":false},
      {"id":"m4","cohabitId":"c-3f2a","kind":"FUTURE_KIND","author":null,"mine":false,
       "createdAt":"2026-09-30T06:11:00Z","text":null,"photoId":null,"checkin":null,
       "systemText":"?","reactionTarget":"message:m4","reactions":[],"deleted":true}],
     "hasMore":true}
    """

    static let today = """
    {"date":"2026-09-30","openCount":2,"headline":"Noch 2 Haken offen",
     "nudges":[{"id":"n1","from":\(lena),"cohabit":\(ref),"text":"Heute noch kochen?","createdAt":"2026-09-30T09:00:00Z"}],
     "newPhotos":{"count":2,"photoIds":["p1","p2"]},
     "invitations":[\(invitation)],"cohabits":[\(summary)]}
    """

    static let timeline = """
    {"items":[{"id":"e1","day":"2026-09-30","at":"2026-09-30T05:12:00Z","cohabit":\(ref),
       "kind":"PHOTO_CHECKIN","person":\(lena),
       "title":"Lena hat Laufen abgehakt","subtitle":"07:12 · Serie 9 Wochen",
       "photoId":"p1","caption":"Regenlauf zählt doppelt.",
       "reactionTarget":"event:e1","reactions":[{"reaction":"RESPEKT","label":"Respekt","count":1,"mine":false}],
       "canReply":true},
      {"id":"e2","day":"2026-09-29","at":"2026-09-29T09:05:00Z","cohabit":\(ref),
       "kind":"HEALTH","person":null,"title":"Health hat 8.200 Schritte für dich eingetragen",
       "subtitle":"11:05 · 100k Schritte","photoId":null,"caption":null,
       "reactionTarget":"event:e2","reactions":[],"canReply":false}],
     "hasMore":false}
    """

    static let stats = """
    {"range":"MONTH","label":"September","fulfillmentRate":86,
     "longestStreak":{"short":"6 Wo.","cohabit":\(ref)},
     "heatmap":{"from":"2026-09-01","to":"2026-09-30","days":[{"date":"2026-09-01","count":1,"level":1}]},
     "cohabits":[{"ref":\(ref),"progressText":"11/13","fraction":0.85}]}
    """

    static let widget = """
    {"generatedAt":"2026-09-30T12:00:00Z","openCount":2,
     "cohabits":[{"ref":\(ref),"value":"6","unit":"Wochen","sub":"Wochen · 2/3","status":"OPEN",
                  "statusText":"offen","photoRequired":true,"quickCheckIn":false}],
     "challenge":{"ref":{"id":"c-9","name":"Wer kocht öfter?","color":"butter","type":"CHALLENGE"},
                  "endsText":"endet heute","myRank":2,
                  "leaderboard":[{"rank":1,"name":"Lena","score":9,"me":false}]},
     "teamGoal":{"ref":{"id":"c-7","name":"100k Schritte","color":"periwinkle","type":"GOAL"},"percent":68},
     "openStreak":{"ref":\(ref),"text":"Laufen · 6 Wochen"}}
    """

    static let friends = """
    {"friends":[\(lena)],
     "incoming":[{"id":"r1","from":\(person),"to":\(felix),"createdAt":"2026-09-30T10:00:00Z"}],
     "outgoing":[]}
    """

    static let candidates = """
    {"seats":{"used":3,"max":8},"canInvite":true,
     "people":[{"person":\(lena),"status":"MEMBER"},{"person":\(person),"status":"INVITE"}]}
    """

    static func data(_ json: String) -> Data { Data(json.utf8) }
}
