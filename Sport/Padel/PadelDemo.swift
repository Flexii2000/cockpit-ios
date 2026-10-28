import Foundation

#if DEBUG
/// Vorfuehrdaten fuer `COCKPIT_PADEL_DEMO=1` - Aufnahmen und UI-Tests ohne Dienst. Platzhalter
/// statt echter Personen (das Repo ist oeffentlich); die Clubs gibt es wirklich.
enum PadelDemo {

    static func overview(now: Date = Date()) -> PadelOverview {
        decode(overviewJSON(now))
    }

    static func bookings(now: Date = Date()) -> [PadelBooking] {
        decode(bookingsJSON(now))
    }

    static func costs() -> PadelCosts {
        decode("""
        {"month":"2026-10","label":"Oktober 2026","spent":80.38,"matches":6,"booked":15.00,"bookedMatches":1,
         "planned":33.00,"plannedDays":2,"forecast":128.38,"months":[
          {"month":"2026-09","label":"September 2026","amount":210.01,"matches":13},
          {"month":"2026-08","label":"August 2026","amount":226.38,"matches":17},
          {"month":"2026-07","label":"Juli 2026","amount":197.97,"matches":17}]}
        """)
    }

    private static func decode<T: Decodable>(_ json: String) -> T {
        // Die Vorfuehrdaten sind fest geschrieben - scheitert das, ist der Text falsch.
        // swiftlint:disable:next force_try
        try! APIClient.decoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Bausteine

    private static let zone = TimeZone(identifier: "Europe/Berlin") ?? .current

    /// Ein Kalendertag relativ zu heute: „2026-11-06“ und „Fr“.
    private static func day(_ offset: Int, from now: Date) -> (iso: String, weekday: String, date: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = calendar.date(byAdding: .day, value: offset, to: now) ?? now
        let p = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        let names = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        return (String(format: "%04d-%02d-%02d", p.year ?? 2026, p.month ?? 1, p.day ?? 1),
                names[((p.weekday ?? 1) - 1) % 7], date)
    }

    private static func instant(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func occurrence(_ id: String, day d: (iso: String, weekday: String, date: Date), start: String,
                                   end: String, status: String, note: String? = nil, release: Date, watch: Date,
                                   club: String, fallback: Bool = false, partner: String, color: String?,
                                   court: String? = nil, canSkip: Bool = false, canUnskip: Bool = false,
                                   canRemove: Bool = false) -> String {
        """
        {"id":"\(id)","oneOff":false,"moved":false,"date":"\(d.iso)","weekday":"\(d.weekday)","start":"\(start)",
         "end":"\(end)","durationMinutes":90,"status":"\(status)","note":\(note.map { "\"\($0)\"" } ?? "null"),
         "releaseAt":"\(instant(release))","watchUntil":"\(instant(watch))","court":\(court.map { "\"\($0)\"" } ?? "null"),
         "price":null,"matchId":null,"inviteUrl":null,"approvalUrl":null,"canSkip":\(canSkip),
         "canUnskip":\(canUnskip),"canMove":false,"canRemove":\(canRemove),"canRetry":false,"attempts":[],
         "alternativeMinutes":null,"club":"\(club)","fallback":\(fallback),"partner":"\(partner)",
         "partnerColor":\(color.map { "\"\($0)\"" } ?? "null")}
        """
    }

    private static let yellow = "#EAB308"
    private static let turquoise = "#14B8A6"

    private static func overviewJSON(_ now: Date) -> String {
        let hour: TimeInterval = 3600
        let friday = day(14, from: now)
        let tuesday = day(11, from: now)
        let thursday = day(6, from: now)
        let saturday = day(8, from: now)
        let releaseB = now.addingTimeInterval(4 * hour + 754)
        let releaseA = now.addingTimeInterval(4 * 24 * hour)
        let rows = [
            occurrence("d-1", day: thursday, start: "18:00", end: "19:30", status: "BOOKED",
                       release: now.addingTimeInterval(-8 * 24 * hour), watch: thursday.date, club: "mitte",
                       partner: "Person A", color: yellow, court: "7"),
            occurrence("d-2", day: thursday, start: "18:00", end: "19:30", status: "SKIPPED",
                       note: "an dem Tag schon gebucht", release: now.addingTimeInterval(-8 * 24 * hour),
                       watch: thursday.date, club: "Padelon", partner: "Person A", color: yellow),
            occurrence("d-3", day: saturday, start: "08:30", end: "10:00", status: "WATCHING",
                       release: now.addingTimeInterval(-hour), watch: saturday.date.addingTimeInterval(-24 * hour),
                       club: "Aspria", partner: "Person A", color: yellow, canSkip: true),
            occurrence("d-4", day: tuesday, start: "18:00", end: "19:30", status: "PLANNED", release: releaseA,
                       watch: tuesday.date, club: "mitte", partner: "Person A", color: yellow, canSkip: true),
            occurrence("d-5", day: tuesday, start: "18:00", end: "19:30", status: "PLANNED", release: releaseA,
                       watch: tuesday.date, club: "Padelon", partner: "Person A", color: yellow, canSkip: true),
            occurrence("d-6", day: tuesday, start: "18:00", end: "19:30", status: "PLANNED",
                       release: releaseA.addingTimeInterval(5 * 24 * hour), watch: tuesday.date, club: "Aspria",
                       fallback: true, partner: "Person A", color: yellow, canSkip: true),
            occurrence("d-7", day: friday, start: "18:00", end: "19:30", status: "PLANNED", release: releaseB,
                       watch: friday.date, club: "mitte", partner: "Person B", color: turquoise, canSkip: true),
            occurrence("d-8", day: friday, start: "18:30", end: "20:00", status: "PLANNED",
                       release: releaseB.addingTimeInterval(1800), watch: friday.date, club: "mitte",
                       partner: "Person B", color: turquoise, canSkip: true),
        ]
        let courts = (1...9).map { n in
            "{\"resourceId\":\"c-\(n)\",\"shortName\":\"\(n)\",\"name\":\"\(n) • Double Court\",\"doubles\":true,\"position\":\(n - 1)}"
        } + ["A", "B", "C"].map { name in
            "{\"resourceId\":\"c-\(name)\",\"shortName\":\"\(name)\",\"name\":\"\(name) • Single Court\",\"doubles\":false,\"position\":-1}"
        }
        let yesterday = now.addingTimeInterval(-26 * hour)
        return """
        {"viewer":{"name":"felix","owner":true},"now":"\(instant(now))","dryRun":false,
         "next":\(rows[6]),
         "occurrences":[\(rows.joined(separator: ","))],
         "series":[
          {"id":"s-1","weekday":"MONDAY","weekdayLabel":"Mo","start":"18:00","durationMinutes":90,"active":true,
           "latestStart":"21:30","club":"mitte","clubs":["mitte"],"partner":"b","partnerLabel":"Person B",
           "firstDate":"\(friday.iso)","partnerColor":"\(turquoise)","levelLimit":true},
          {"id":"s-2","weekday":"TUESDAY","weekdayLabel":"Di","start":"18:00","durationMinutes":90,"active":true,
           "latestStart":"21:00","club":null,"clubs":["mitte","Padelon"],"partner":"a","partnerLabel":"Person A",
           "firstDate":null,"partnerColor":"\(yellow)","levelLimit":true},
          {"id":"s-3","weekday":"SATURDAY","weekdayLabel":"Sa","start":"08:30","durationMinutes":90,"active":false,
           "latestStart":null,"club":"aspria","clubs":["Aspria"],"partner":"a","partnerLabel":"Person A",
           "firstDate":null,"partnerColor":"\(yellow)"}],
         "courts":[\(courts.joined(separator: ","))],
         "status":{"playtomicLogin":true,"playtomicRefreshUntil":null,"calendar":true,"todo":true,"windowHours":336,
                   "armedReleases":86,"splitPayment":true},
         "feedUrl":"webcal://fherrmann.com/padel/calendar/demo.ics",
         "clubs":[{"id":"mitte","label":"mitte"},{"id":"padelon","label":"Padelon"},{"id":"aspria","label":"Aspria"}],
         "partners":[{"id":"a","label":"Person A","color":"\(yellow)"},{"id":"b","label":"Person B","color":"\(turquoise)"},
                     {"id":"c","label":"Person C","color":null}],
         "results":[
          {"id":"r-1","startedAt":"\(instant(yesterday))","endedAt":"\(instant(yesterday.addingTimeInterval(5100)))",
           "summary":"6:0 6:2","status":"SUBMITTED","statusText":"bei Playtomic eingetragen","club":"mitte",
           "bookingStart":"\(instant(yesterday))","partner":"Person B","partnerColor":"\(turquoise)"}]}
        """
    }

    private static func bookingsJSON(_ now: Date) -> String {
        let thursday = day(6, from: now)
        let tuesday = day(11, from: now)
        return """
        [{"matchId":"m-1","date":"\(thursday.iso)","weekday":"\(thursday.weekday)","start":"18:00","end":"19:30",
          "court":"7","price":"16.88 EUR","split":true,"isPublic":false,
          "freeCancellationUntil":"\(instant(thursday.date.addingTimeInterval(-3 * 3600)))","cancellable":true,
          "inviteUrl":"https://app.playtomic.com/matches/m-1","occurrenceId":"d-1","publishable":false,
          "publishBlocker":"Person A hat noch nicht bezahlt","extendTo":null,"club":"mitte","mergeable":false,
          "partner":"Person A","location":"mitte","partnerColor":"\(yellow)"},
         {"matchId":"m-2","date":"\(tuesday.iso)","weekday":"\(tuesday.weekday)","start":"20:00","end":"21:30",
          "court":"3","price":"16.5 EUR","split":true,"isPublic":true,
          "freeCancellationUntil":"\(instant(tuesday.date))","cancellable":false,
          "inviteUrl":"https://app.playtomic.com/matches/m-2","occurrenceId":null,"publishable":false,
          "publishBlocker":null,"extendTo":null,"club":"Padelon","mergeable":false,"partner":"Person B",
          "location":"Padelon","partnerColor":"\(turquoise)"}]
        """
    }
}
#endif
