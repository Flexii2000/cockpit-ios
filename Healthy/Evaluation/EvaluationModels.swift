import Foundation

/// Eine Frage des Evaluation-Tabs.
///
/// Der Text steht nur auf dem iPhone - nie im Repo (es ist oeffentlich), nie
/// auf einem Server. Deshalb legt man die Fragen in der App fest und nicht in
/// einer Datei, die mitgebaut wird (Felix, 04.10.).
struct EvaluationQuestion: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

/// Die Antworten eines Tages, je Frage ein Wert von 1 bis 10.
///
/// Schluessel ist die Frage-ID als Text: ein Woerterbuch mit `UUID` als
/// Schluessel kodiert `JSONEncoder` als Liste aus abwechselnd Schluessel und
/// Wert, und die Datei waere kaum noch zu lesen.
struct EvaluationDay: Codable, Hashable, Sendable {
    let date: CalendarDate
    var values: [String: Int]
}

/// Alles, was in der Datei steht.
///
/// Wer eine Frage entfernt, verliert ihre Antworten nicht: sie bleiben in
/// `days` stehen und werden nur nicht mehr gezeigt. Umbenennen behaelt die
/// ID und damit den Verlauf.
struct EvaluationData: Codable, Equatable, Sendable {
    var version = 1
    var questions: [EvaluationQuestion] = []
    var days: [EvaluationDay] = []

    func value(of question: UUID, on date: CalendarDate) -> Int? {
        days.first { $0.date == date }?.values[question.uuidString]
    }

    /// `nil` nimmt die Antwort zurueck. Ein Tag ohne Antwort verschwindet ganz.
    mutating func set(_ value: Int?, for question: UUID, on date: CalendarDate) {
        let key = question.uuidString
        if let index = days.firstIndex(where: { $0.date == date }) {
            days[index].values[key] = value
            if days[index].values.isEmpty { days.remove(at: index) }
        } else if let value {
            days.append(EvaluationDay(date: date, values: [key: value]))
            days.sort { $0.date < $1.date }
        }
    }

    /// Jede Frage beantwortet - erst dann faellt die Erinnerung des Tages weg.
    func isComplete(on date: CalendarDate) -> Bool {
        guard !questions.isEmpty, let day = days.first(where: { $0.date == date }) else { return false }
        return questions.allSatisfy { day.values[$0.id.uuidString] != nil }
    }
}

enum EvaluationScale {
    static let values = Array(1...10)
}

/// Welche Tage sich setzen lassen: heute und gestern - gestern fuer den Abend,
/// der erst nach Mitternacht beantwortet wird (Felix, 04.10.). Aelteres bleibt,
/// wie es ist.
enum EvaluationDays {
    static func editable(today: CalendarDate) -> [CalendarDate] {
        [today, today.adding(days: -1)]
    }
}

/// Zeitraum der Diagramme - dieselben Schritte wie im Gewicht-Tab, ohne die
/// ganz langen.
enum EvaluationRange: Int, CaseIterable, Identifiable, Sendable {
    case month = 30
    case last90 = 90
    case last180 = 180
    case year = 365

    var id: Int { rawValue }
    var days: Int { rawValue }

    var title: String {
        switch self {
        case .month:   "30 Tage"
        case .last90:  "90 Tage"
        case .last180: "180 Tage"
        case .year:    "1 Jahr"
        }
    }
}
