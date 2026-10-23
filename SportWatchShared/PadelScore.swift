import Foundation

// Das Zaehlen eines Padel-Matches auf der Uhr (Felix, 23.10.) - rein rechnend, damit die
// Unit-Tests von Sport es pruefen koennen. Uebersetzt von Sport und SportWatch.

/// Was bei 40:40 gilt (Felix, 23.10.: Golden oder Silver Point einstellbar).
enum PadelDeuceRule: String, Codable, CaseIterable, Sendable {
    /// Bei 40:40 entscheidet der naechste Punkt.
    case golden
    /// Beim ersten 40:40 wird um den Vorteil gespielt; kommt es ein zweites Mal zu 40:40,
    /// entscheidet der naechste Punkt.
    case silver

    var label: String {
        switch self {
        case .golden: "Golden Point"
        case .silver: "Silver Point"
        }
    }
}

/// Wir (Felix und sein Mitspieler) oder die anderen.
enum PadelSide: String, Codable, CaseIterable, Sendable {
    case us, them

    var other: PadelSide { self == .us ? .them : .us }
}

/// Welcher der beiden Spieler eines Teams aufschlaegt - so, wie der Ball auf der Uhr in der
/// Haelfte des Teams steht (Felix, 23.10.).
enum PadelPlayer: String, Codable, Sendable {
    case left, right

    var other: PadelPlayer { self == .left ? .right : .left }
}

/// Je Team der Spieler, der das naechste Aufschlagspiel des Teams hat - im laufenden, wer gerade
/// aufschlaegt. Anfangs rechts (Felix, 23.10.); stimmt das nicht, tippt man auf den Ball.
struct PadelServers: Codable, Equatable, Sendable {
    var us = PadelPlayer.right
    var them = PadelPlayer.right

    subscript(side: PadelSide) -> PadelPlayer {
        get { side == .us ? us : them }
        set { if side == .us { us = newValue } else { them = newValue } }
    }
}

/// Zwei Zahlen, eine je Seite - Spiele, Punkte oder ein Satz.
struct PadelPair: Codable, Equatable, Sendable {
    var us = 0
    var them = 0

    subscript(side: PadelSide) -> Int {
        get { side == .us ? us : them }
        set { if side == .us { us = newValue } else { them = newValue } }
    }
}

/// Ein abgeschlossener Satz aus unserer Sicht, mit dem Tie-Break, falls es einen gab.
struct PadelSetScore: Codable, Equatable, Sendable {
    let us: Int
    let them: Int
    var tieBreak: PadelPair?

    var winner: PadelSide { us > them ? .us : .them }

    /// Ein Satz, wie Playtomic ihn kennt: 6 mit zwei Spielen Abstand, 7:5 oder 7:6.
    var isValid: Bool {
        let high = max(us, them), low = min(us, them)
        return (high == 6 && low <= 4) || (high == 7 && (low == 5 || low == 6))
    }
}

/// Der Spielstand. Jeder Punkt macht einen neuen; zurueck geht es ueber den alten
/// (`PadelMatch` haelt den Verlauf).
struct PadelScore: Codable, Equatable, Sendable {

    let rule: PadelDeuceRule
    /// Die abgeschlossenen Saetze.
    private(set) var sets: [PadelSetScore] = []
    /// Spiele im laufenden Satz.
    private(set) var games = PadelPair()
    /// Punkte im laufenden Spiel (0 bis 3 = 0, 15, 30, 40) bzw. im Tie-Break.
    private(set) var points = PadelPair()
    /// Wer nach 40:40 den Vorteil hat.
    private(set) var advantage: PadelSide?
    /// Wie oft es im laufenden Spiel schon 40:40 stand - beim Silver Point entscheidet das zweite.
    private(set) var deuces = 0
    /// Wer im laufenden Spiel aufschlaegt; im Tie-Break, wer den naechsten Punkt aufschlaegt.
    private(set) var server: PadelSide
    /// Wer den laufenden Tie-Break eroeffnet hat - die anderen beginnen den naechsten Satz.
    private(set) var tieBreakOpener: PadelSide?
    /// `nil` in einem Stand, den die Uhr vor dem Merken der Spieler gespeichert hat - dann gilt
    /// wieder „rechts“.
    private var storedServers: PadelServers?

    init(rule: PadelDeuceRule, firstServer: PadelSide) {
        self.rule = rule
        server = firstServer
        storedServers = PadelServers()
    }

    var isTieBreak: Bool { tieBreakOpener != nil }

    /// Wer in jedem Team als Naechstes aufschlaegt.
    private(set) var servers: PadelServers {
        get { storedServers ?? PadelServers() }
        set { storedServers = newValue }
    }

    /// Links oder rechts im Team, das gerade aufschlaegt.
    var servingPlayer: PadelPlayer { servers[server] }

    /// Der Ball steht beim falschen Spieler: im aufschlagenden Team ist es der andere - fuer das
    /// erste Aufschlagspiel eines Teams und wenn ein Team zu Satzbeginn die Reihenfolge tauscht.
    mutating func switchServingPlayer() {
        guard winner == nil else { return }
        servers[server] = servers[server].other
    }

    /// Gewonnene Saetze je Seite.
    var setsWon: PadelPair {
        var won = PadelPair()
        for set in sets { won[set.winner] += 1 }
        return won
    }

    /// Wer das Match gewonnen hat (zwei Saetze) - danach zaehlt kein Punkt mehr.
    var winner: PadelSide? {
        let won = setsWon
        return won.us >= 2 ? .us : won.them >= 2 ? .them : nil
    }

    /// Ob der naechste Punkt das Spiel entscheidet - so steht es auf der Uhr.
    var isDecidingPoint: Bool {
        !isTieBreak && points.us == 3 && points.them == 3 && advantage == nil
            && (rule == .golden || deuces >= 2)
    }

    /// Was fuer eine Seite angezeigt wird: „15“, „40“, „AD“, im Tie-Break die Punkte.
    func pointLabel(_ side: PadelSide) -> String {
        if isTieBreak { return String(points[side]) }
        if advantage == side { return "AD" }
        return ["0", "15", "30", "40"][min(points[side], 3)]
    }

    /// Ein Punkt fuer `side`.
    mutating func point(for side: PadelSide) {
        guard winner == nil else { return }
        if isTieBreak {
            tieBreakPoint(for: side)
            return
        }
        let mine = points[side], theirs = points[side.other]
        if advantage == side {
            winGame(side)
        } else if advantage == side.other {
            // Zurueck auf 40:40 - beim Silver Point entscheidet jetzt der naechste Punkt.
            advantage = nil
            deuces += 1
        } else if mine == 3 && theirs == 3 {
            if rule == .golden || deuces >= 2 {
                winGame(side)
            } else {
                advantage = side
            }
        } else if mine == 3 {
            winGame(side)
        } else {
            points[side] += 1
            if points.us == 3 && points.them == 3 { deuces = 1 }
        }
    }

    // MARK: - Intern

    private mutating func winGame(_ side: PadelSide) {
        games[side] += 1
        points = PadelPair()
        advantage = nil
        deuces = 0
        // Der Aufschlag wechselt nach jedem Spiel - auch ueber das Ende eines Satzes hinweg -, und
        // im Team, das aufgeschlagen hat, ist beim naechsten Mal der andere Spieler dran.
        servers[server] = servers[server].other
        server = server.other
        if games.us == 6 && games.them == 6 {
            tieBreakOpener = server
        } else if games[side] >= 6 && games[side] - games[side.other] >= 2 {
            finishSet(tieBreak: nil)
        }
    }

    /// Bis 7 mit zwei Punkten Abstand. Aufschlag: der Eroeffner einen Punkt, danach je zwei.
    /// Die Spieler wechseln reihum wie in den Spielen: endet der Durchgang eines Teams, ist dort
    /// beim naechsten Mal der andere dran.
    private mutating func tieBreakPoint(for side: PadelSide) {
        let servedBy = server
        points[side] += 1
        let played = points.us + points.them
        guard let opener = tieBreakOpener else { return }
        if points[side] >= 7 && points[side] - points[side.other] >= 2 {
            games[side] += 1
            let tieBreak = points
            servers[servedBy] = servers[servedBy].other
            // Wer im Tie-Break zuerst annahm, schlaegt im naechsten Satz zuerst auf.
            server = opener.other
            finishSet(tieBreak: tieBreak)
            return
        }
        server = ((played + 1) / 2) % 2 == 0 ? opener : opener.other
        if server != servedBy { servers[servedBy] = servers[servedBy].other }
    }

    private mutating func finishSet(tieBreak: PadelPair?) {
        sets.append(PadelSetScore(us: games.us, them: games.them, tieBreak: tieBreak))
        games = PadelPair()
        points = PadelPair()
        advantage = nil
        deuces = 0
        tieBreakOpener = nil
    }
}

/// Was die Uhr nach dem Match an den Padel-Dienst schickt (Felix, 23.10.): der Dienst sucht
/// die Buchung dazu und traegt das Ergebnis bei Playtomic ein, sobald es dort geht.
struct PadelMatchReport: Codable, Equatable, Sendable, Identifiable {
    /// Von der Uhr vergeben - wer zweimal schickt (direkt und uebers iPhone), traegt nur einmal ein.
    let id: String
    let startedAt: Date
    let endedAt: Date
    let rule: PadelDeuceRule
    /// Nur die abgeschlossenen Saetze, aus unserer Sicht.
    let sets: [PadelSetScore]

    /// Ein Ergebnis, das sich eintragen laesst: mindestens ein ganzer Satz, alle gueltig.
    var isValid: Bool { !sets.isEmpty && sets.allSatisfy(\.isValid) }

    /// „6:0 6:2“
    var summary: String {
        sets.map { "\($0.us):\($0.them)" }.joined(separator: " ")
    }
}
