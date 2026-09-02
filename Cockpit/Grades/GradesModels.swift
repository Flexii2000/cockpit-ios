import Foundation

/// Was `/grades/api/overview` liefert.
///
/// Die Schluessel sind deutsch, weil sie aus der Rechnung des Dienstes
/// stammen (`app/lib/berechnung.py`). Uebersetzt wird hier, nicht dort: eine
/// zweite Namensgebung auf dem Server waere eine Zuordnung, die bei jeder
/// neuen Zahl mitgepflegt werden muesste.
struct GradesOverview: Decodable, Sendable {

    let modules: [GradeModule]
    let unassigned: [UnassignedGrade]
    /// Bestandene benotete Module.
    let done: Int
    /// Benotete Module, die noch ausstehen.
    let open: Int
    let ectsDone: Int
    let ectsGradedTotal: Int
    let ectsPlanTotal: Int
    let scenarios: Scenarios
    let assumptionCount: Int
    /// Die an deutschen Hochschulen vergebenen Noten - 1,0 bis 4,0.
    let possibleGrades: [Double]
    /// Der ungewichtete Schnitt. **Nicht** die Abschlussnote; der
    /// Notenchecker zeigt ihn, und genau das ist der Grund fuer diesen Dienst.
    let simpleAverage: Double?
    let rule: Rule
    /// Wann der Notenchecker zuletzt nachgesehen hat.
    let asOf: Date?

    enum CodingKeys: String, CodingKey {
        case modules = "module"
        case unassigned = "unzugeordnet"
        case done = "fertig"
        case open = "offen"
        case ectsDone = "ects_erreicht"
        case ectsGradedTotal = "ects_benotet_gesamt"
        case ectsPlanTotal = "ects_plan_gesamt"
        case scenarios = "szenarien"
        case assumptionCount = "annahmen_anzahl"
        case possibleGrades = "moegliche_noten"
        case simpleAverage = "einfacher_schnitt"
        case rule = "regel"
        case asOf = "stand_iso"
    }

    struct Scenarios: Decodable, Sendable {
        /// Nur die vorhandenen Noten, ECTS-gewichtet.
        let current: Double?
        /// Alle offenen Module mit 1,0.
        let best: Double?
        /// Alle offenen Module mit dem bisherigen Schnitt.
        let average: Double?
        /// Alle offenen Module mit 4,0 - der schlechtesten bestandenen Note.
        let worst: Double?
        /// Mit Felix' eigenen Annahmen. `nil`, solange er keine gesetzt hat.
        let assumed: Double?

        enum CodingKeys: String, CodingKey {
            case current = "aktuell"
            case best = "best_case"
            case average = "average_case"
            case worst = "worst_case"
            case assumed = "angenommen"
        }
    }

    struct Rule: Decodable, Sendable {
        let name: String
        let text: String

        enum CodingKeys: String, CodingKey {
            case name = "regel"
            case text = "wortlaut"
        }
    }
}

/// Ein Modul aus dem Studienplan der PO-I23.
struct GradeModule: Decodable, Identifiable, Sendable {

    var id: String { name }

    let name: String
    let ects: Int
    let area: String?
    let semester: String?
    let exam: String?
    /// Unbenotete Module (Seminare, Transfermodule) zaehlen in keiner
    /// Rechnung mit und stehen deshalb auch in keiner Tabelle.
    let graded: Bool
    let grade: Double?
    /// `"name"` (woertlich gefunden) oder `"zuordnung"` (ueber
    /// `data/zuordnung.json` zugeordnet - die drei vermuteten Faelle).
    let source: String?
    /// Wie das Fach im Notenchecker heisst, falls anders.
    let checkerName: String?
    /// Felix' Annahme fuer ein offenes Modul. Ueberschreibt nie eine Note.
    let assumption: Double?

    /// Ob die Zuordnung geraten ist - dann steht der Notenchecker-Name daneben.
    var isMapped: Bool { source == "zuordnung" }

    enum CodingKeys: String, CodingKey {
        case name, ects, semester
        case area = "bereich"
        case exam = "pruefung"
        case graded = "benotet"
        case grade = "note"
        case source = "quelle"
        case checkerName = "notenchecker_name"
        case assumption = "annahme"
    }
}

/// Eine Note aus dem Notenchecker, die zu keinem Planmodul passt.
struct UnassignedGrade: Decodable, Identifiable, Sendable {
    var id: String { subject }
    let subject: String
    let grade: String
}

/// Note als Text: zwei Nachkommastellen, Komma statt Punkt - wie im Web.
enum GradeFormat {

    static func text(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    /// Eine einzelne Note (1,7) statt eines Schnitts (1,72).
    static func short(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    /// „30.08.2026, 11:04" - wie im Web.
    ///
    /// Fest auf Deutsch und nicht ueber `formatted(date:time:)`: das richtet
    /// sich nach der Systemsprache und schreibt sonst mitten in eine
    /// durchgehend deutsche Oberflaeche ein „at" hinein.
    static func stamp(_ date: Date) -> String {
        Self.stampFormatter.string(from: date)
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy, HH:mm"
        return formatter
    }()
}
