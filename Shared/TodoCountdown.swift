import Foundation

/// Eine Aufgabe, wie die Countdown-Kachel von Fokus sie braucht (Felix 17.11.,
/// etwa „Klausur in 60 Tagen“). Gezaehlt wird bis zur Faelligkeit, in
/// Kalendertagen - der Dienst kennt nur den Tag, keine Uhrzeit.
///
/// Welche Aufgabe, waehlt Felix in der Kachel („Widget bearbeiten“); ohne Wahl
/// zeigt sie die naechste faellige.
struct TodoCountdown: Codable, Sendable, Equatable, Identifiable {
    let id: String
    /// Bei einer Unteraufgabe mit der Aufgabe darueber: „Hausarbeit › Gliederung“.
    let title: String
    /// Der Bereich - `nil` bei einer Aufgabe, die nur in „Heute“ steht.
    let area: String?
    let dueAt: CalendarDate?
    let isDone: Bool

    enum Phase: Sendable, Equatable {
        /// Noch so viele Tage, mindestens einer.
        case ahead(Int)
        case today
        /// Seit so vielen Tagen faellig und noch offen.
        case overdue(Int)
        case done
        /// Die Faelligkeit wurde entfernt.
        case undated
    }

    /// Der Stand an `day` - die Kachel rechnet ihn je Eintrag der Zeitleiste,
    /// damit die Zahl um Mitternacht ohne Netz weiterzaehlt.
    func phase(on day: CalendarDate) -> Phase {
        if isDone { return .done }
        guard let dueAt else { return .undated }
        let days = day.days(until: dueAt)
        if days > 0 { return .ahead(days) }
        return days == 0 ? .today : .overdue(-days)
    }

    /// „Sa 16.01.“, in einem anderen Jahr als `today` „Sa 16.01.27“.
    func dateText(today: CalendarDate) -> String? {
        guard let dueAt else { return nil }
        let weekdays = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
        let date = "\(weekdays[dueAt.isoWeekday - 1]) \(String(format: "%02d.%02d.", dueAt.day, dueAt.month))"
        return dueAt.year == today.year ? date : date + String(format: "%02d", dueAt.year % 100)
    }
}

// MARK: - Aus dem Brett

extension TodoCountdown {

    /// Jede Aufgabe des Bretts genau einmal: aus allen Bereichen samt
    /// Unteraufgaben, dazu die, die nur in „Heute“ stehen. Was in „Heute“ und
    /// in einem Bereich steht, kommt mit seinem Bereich.
    static func all(in board: TodoBoard) -> [TodoCountdown] {
        var seen = Set<String>()
        var result: [TodoCountdown] = []
        func add(_ todo: TodoItem, parent: TodoItem?, area: String?) {
            guard seen.insert(todo.id).inserted else { return }
            result.append(TodoCountdown(id: todo.id, title: parent.map { "\($0.title) › \(todo.title)" } ?? todo.title,
                                        area: area, dueAt: todo.dueAt, isDone: todo.isDone))
            for child in todo.children { add(child, parent: todo, area: area) }
        }
        for area in board.areas {
            for todo in area.todos { add(todo, parent: nil, area: area.name) }
        }
        for item in board.today?.items ?? [] where item.isAdHoc {
            add(item.todo, parent: nil, area: nil)
        }
        return result
    }

    /// Was zur Wahl steht: offene Aufgaben mit Faelligkeit, die naechste zuerst.
    static func choices(in todos: [TodoCountdown]) -> [TodoCountdown] {
        todos.filter { !$0.isDone && $0.dueAt != nil }
            .sorted { lhs, rhs in
                guard let left = lhs.dueAt, let right = rhs.dueAt, left != right else { return lhs.title < rhs.title }
                return left < right
            }
    }

    /// Die gewaehlte Aufgabe - auch erledigt oder ohne Faelligkeit, das zeigt die
    /// Kachel dann so an. Ohne Wahl, oder wenn es sie nicht mehr gibt, die
    /// naechste faellige ab heute: eine leere Kachel hilft niemandem.
    static func pick(_ id: String?, in todos: [TodoCountdown], today: CalendarDate) -> TodoCountdown? {
        if let id, let chosen = todos.first(where: { $0.id == id }) { return chosen }
        return choices(in: todos).first { ($0.dueAt ?? today) >= today }
    }

    /// Die naechsten `count` Tageswechsel nach `date` - dort springt die Zahl.
    static func midnights(after date: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: date)
        return (1...max(count, 1)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
}

// MARK: - Texte der Kachel

extension TodoCountdown.Phase {

    /// Die grosse Zeile der kleinen Kachel. Beim Erledigten steht dort ein
    /// Haken, kein Text.
    var figure: String? {
        switch self {
        case .ahead(let days), .overdue(let days): "\(days)"
        case .today: "Heute"
        case .undated: "–"
        case .done: nil
        }
    }

    /// Was unter der grossen Zeile steht.
    var caption: String? {
        switch self {
        case .ahead(let days): Self.days(days)
        case .overdue(let days): "\(Self.days(days)) überfällig"
        case .today: nil
        case .done: "erledigt"
        case .undated: "ohne Fälligkeit"
        }
    }

    /// Eine Zeile - rechteckig auf dem Sperrbildschirm.
    var line: String {
        switch self {
        case .ahead(let days): "\(days) \(Self.days(days))"
        case .today: "heute"
        case .overdue(let days): "\(days) \(Self.days(days)) überfällig"
        case .done: "erledigt"
        case .undated: "ohne Fälligkeit"
        }
    }

    /// Rund auf dem Sperrbildschirm: Zahl und Einheit. Ueberfaelliges zaehlt ins
    /// Minus - Farbe gibt es dort nicht.
    var compact: (figure: String?, unit: String?) {
        switch self {
        case .ahead(let days): ("\(days)", Self.days(days))
        case .overdue(let days): ("−\(days)", Self.days(days))
        case .today: ("heute", nil)
        case .done: (nil, nil)
        case .undated: ("–", nil)
        }
    }

    /// Die Zeile ueber der Uhr: „Klausur in 60 Tagen“.
    func sentence(_ title: String) -> String {
        switch self {
        case .ahead(1): "\(title) morgen"
        case .ahead(let days): "\(title) in \(days) Tagen"
        case .today: "\(title) heute"
        case .overdue(1): "\(title) seit gestern fällig"
        case .overdue(let days): "\(title) seit \(days) Tagen fällig"
        case .done: "\(title) erledigt"
        case .undated: title
        }
    }

    private static func days(_ count: Int) -> String {
        count == 1 ? "Tag" : "Tage"
    }
}

/// Was die Countdown-Kachel zeigt.
enum TodoCountdownWidgetState: Sendable, Equatable {
    case countdown(TodoCountdown)
    /// Keine offene Aufgabe mit Faelligkeit.
    case empty
    case noAccess
    case unreachable

    /// Was statt eines Countdowns dasteht.
    var message: String? {
        switch self {
        case .countdown: nil
        case .empty: "Kein To-Do mit Fälligkeit"
        case .noAccess: "Kein Zugang"
        case .unreachable: "Nicht erreichbar"
        }
    }
}
