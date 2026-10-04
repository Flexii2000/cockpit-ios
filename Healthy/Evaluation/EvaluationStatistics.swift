import Foundation

/// Zusammenhaenge zwischen den Antworten - je Frage-Paar Spearman ρ und
/// Pearson r, am selben Tag und um einen Tag versetzt (Felix, 04.10.).
///
/// Wie beim Mittel rechnet die App selbst: hinter dem Tab steht kein Dienst.
///
/// **p-Werte mit effektivem n.** Tageswerte haengen von Tag zu Tag zusammen;
/// ein Test, der jeden Tag als unabhaengig zaehlt, macht sie zu klein. Deshalb
/// das effektive n nach Bartlett: n · (1 − a·b) / (1 + a·b), mit a und b den
/// Autokorrelationen beider Reihen um einen Tag. Damit der t-Test
/// t = r · √((n_eff − 2) / (1 − r²)), zweiseitig.
///
/// **Holm** ueber alle Tests eines Masses (gleicher Tag und versetzt
/// zusammen): bei drei Fragen neun Tests. ρ und r sind zwei Blicke auf dieselben
/// Hypothesen, keine zusaetzlichen - deshalb je Mass eine Familie.
enum EvaluationStatistics {

    enum Measure: CaseIterable, Hashable, Sendable {
        case spearman, pearson

        var symbol: String {
            switch self {
            case .spearman: "ρ"
            case .pearson:  "r"
            }
        }
    }

    enum Kind: Hashable, Sendable {
        /// Beide Antworten vom selben Tag.
        case sameDay
        /// Die erste Frage an einem Tag, die zweite am Tag darauf.
        case nextDay
    }

    /// Ein Wertepaar. `date` ist der Tag der ersten Antwort - beim Versatz
    /// stammt `y` vom Tag danach.
    struct Sample: Hashable, Sendable {
        let date: CalendarDate
        let x: Double
        let y: Double
    }

    struct Estimate: Hashable, Sendable {
        let coefficient: Double
        let effectiveN: Double
        /// Roh, vor der Korrektur.
        let p: Double?
        /// Nach Holm - danach richten sich die Sterne.
        var adjustedP: Double?
    }

    struct Result: Identifiable, Hashable, Sendable {
        let kind: Kind
        let first: UUID
        let second: UUID
        let n: Int
        var estimates: [Measure: Estimate]

        var id: String { "\(kind)-\(first)-\(second)" }
    }

    /// Ab so vielen Paaren gibt es einen Koeffizienten.
    static let minimumPairs = 5
    /// Ab so viel effektivem n einen p-Wert - darunter haette der t-Test keine
    /// zwei Freiheitsgrade.
    static let minimumEffectiveN = 4.0

    // MARK: - Alle Paare

    static func results(_ data: EvaluationData, from: CalendarDate, to: CalendarDate) -> [Result] {
        let ids = data.questions.map(\.id)
        var pairs: [(Kind, UUID, UUID)] = []
        for i in ids.indices {
            for j in ids.indices where j > i { pairs.append((.sameDay, ids[i], ids[j])) }
        }
        for i in ids.indices {
            for j in ids.indices where j != i { pairs.append((.nextDay, ids[i], ids[j])) }
        }

        var results = pairs.map { kind, first, second in
            let pairs = samples(data, first: first, second: second, kind: kind, from: from, to: to)
            var estimates: [Measure: Estimate] = [:]
            for measure in Measure.allCases {
                if let estimate = estimate(pairs, measure: measure) { estimates[measure] = estimate }
            }
            return Result(kind: kind, first: first, second: second, n: pairs.count, estimates: estimates)
        }

        for measure in Measure.allCases {
            let adjusted = holm(results.map { $0.estimates[measure]?.p })
            for index in results.indices {
                results[index].estimates[measure]?.adjustedP = adjusted[index]
            }
        }
        return results
    }

    /// Die Tage, an denen beide Antworten da sind. Beim Versatz muss auch der
    /// Folgetag im Zeitraum liegen.
    static func samples(_ data: EvaluationData, first: UUID, second: UUID, kind: Kind,
                        from: CalendarDate, to: CalendarDate) -> [Sample] {
        var byDate: [CalendarDate: [String: Int]] = [:]
        for day in data.days { byDate[day.date] = day.values }
        let offset = kind == .sameDay ? 0 : 1
        var samples: [Sample] = []
        var date = from
        while date.adding(days: offset) <= to {
            if let x = byDate[date]?[first.uuidString],
               let y = byDate[date.adding(days: offset)]?[second.uuidString] {
                samples.append(Sample(date: date, x: Double(x), y: Double(y)))
            }
            date = date.adding(days: 1)
        }
        return samples
    }

    static func estimate(_ samples: [Sample], measure: Measure) -> Estimate? {
        guard samples.count >= minimumPairs else { return nil }
        // Spearman ist Pearson auf den Raengen - auch die Autokorrelation wird
        // dann auf den Raengen gemessen, damit beides zusammenpasst.
        let transformed: [Sample]
        switch measure {
        case .pearson:
            transformed = samples
        case .spearman:
            let xs = ranks(samples.map(\.x))
            let ys = ranks(samples.map(\.y))
            transformed = samples.indices.map { Sample(date: samples[$0].date, x: xs[$0], y: ys[$0]) }
        }
        guard let coefficient = pearson(transformed.map(\.x), transformed.map(\.y)) else { return nil }
        let n = effectiveN(transformed.count,
                           lag1(transformed, \.x) ?? 0,
                           lag1(transformed, \.y) ?? 0)
        return Estimate(coefficient: coefficient, effectiveN: n,
                        p: pValue(coefficient, effectiveN: n), adjustedP: nil)
    }

    // MARK: - Bausteine

    /// `nil`, wenn eine der beiden Reihen nicht schwankt - dann gibt es nichts
    /// zu korrelieren.
    static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 2 else { return nil }
        let mx = xs.reduce(0, +) / Double(xs.count)
        let my = ys.reduce(0, +) / Double(ys.count)
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for (x, y) in zip(xs, ys) {
            sxy += (x - mx) * (y - my)
            sxx += (x - mx) * (x - mx)
            syy += (y - my) * (y - my)
        }
        guard sxx > 0, syy > 0 else { return nil }
        return max(-1, min(1, sxy / (sxx * syy).squareRoot()))
    }

    /// Raenge ab 1, Gleichstaende bekommen den mittleren Rang.
    static func ranks(_ values: [Double]) -> [Double] {
        let order = values.indices.sorted { values[$0] < values[$1] }
        var ranks = [Double](repeating: 0, count: values.count)
        var start = 0
        while start < order.count {
            var end = start
            while end + 1 < order.count, values[order[end + 1]] == values[order[start]] { end += 1 }
            let rank = Double(start + end) / 2 + 1
            for k in start...end { ranks[order[k]] = rank }
            start = end + 1
        }
        return ranks
    }

    /// Autokorrelation um einen Tag: Pearson ueber alle Paare aufeinander
    /// folgender Tage im Sample. Luecken brechen ein Paar, nicht die Reihe.
    static func lag1(_ samples: [Sample], _ value: KeyPath<Sample, Double>) -> Double? {
        var byDate: [CalendarDate: Double] = [:]
        for sample in samples { byDate[sample.date] = sample[keyPath: value] }
        var today: [Double] = [], tomorrow: [Double] = []
        for sample in samples {
            if let next = byDate[sample.date.adding(days: 1)] {
                today.append(sample[keyPath: value])
                tomorrow.append(next)
            }
        }
        guard today.count >= 3 else { return nil }
        return pearson(today, tomorrow)
    }

    /// Bartlett: n · (1 − a·b) / (1 + a·b). Nie mehr als n - eine gegenlaeufige
    /// Autokorrelation soll keine Tage dazuerfinden.
    static func effectiveN(_ n: Int, _ a: Double, _ b: Double) -> Double {
        let product = a * b
        guard product > 0 else { return Double(n) }
        return Double(n) * (1 - product) / (1 + product)
    }

    /// Zweiseitiger p-Wert des t-Tests auf r = 0 mit n_eff − 2 Freiheitsgraden.
    static func pValue(_ r: Double, effectiveN n: Double) -> Double? {
        guard n >= minimumEffectiveN else { return nil }
        let df = n - 2
        let rest = 1 - r * r
        guard rest > 1e-12 else { return 0 }
        let t2 = r * r * df / rest
        return regularizedIncompleteBeta(df / (df + t2), df / 2, 0.5)
    }

    /// Holm: aufsteigend sortiert, der i-te von m mal (m − i + 1), nie kleiner
    /// als der davor und nie ueber 1. `nil` bleibt `nil` und zaehlt nicht mit.
    static func holm(_ ps: [Double?]) -> [Double?] {
        let present = ps.indices.filter { ps[$0] != nil }.sorted { ps[$0]! < ps[$1]! }
        let m = present.count
        var adjusted = [Double?](repeating: nil, count: ps.count)
        var running = 0.0
        for (rank, index) in present.enumerated() {
            running = max(running, min(1, Double(m - rank) * ps[index]!))
            adjusted[index] = running
        }
        return adjusted
    }

    static func stars(_ p: Double) -> String {
        switch p {
        case ..<0.001: "***"
        case ..<0.01:  "**"
        case ..<0.05:  "*"
        default:       ""
        }
    }

    // MARK: - Unvollstaendige Betafunktion

    /// I_x(a, b) per Kettenbruch (Lentz), wie in den Numerical Recipes - fuer
    /// den p-Wert des t-Tests, ohne eine Bibliothek dafuer.
    static func regularizedIncompleteBeta(_ x: Double, _ a: Double, _ b: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        let front = exp(lgamma(a + b) - lgamma(a) - lgamma(b) + a * log(x) + b * log(1 - x))
        // Der Kettenbruch konvergiert nur fuer x < (a + 1) / (a + b + 2) schnell -
        // sonst ueber die Symmetrie I_x(a, b) = 1 − I_{1−x}(b, a).
        if x < (a + 1) / (a + b + 2) {
            return front * continuedFraction(x, a, b) / a
        }
        return 1 - front * continuedFraction(1 - x, b, a) / b
    }

    private static func continuedFraction(_ x: Double, _ a: Double, _ b: Double) -> Double {
        let tiny = 1e-300
        var c = 1.0
        var d = 1 - (a + b) * x / (a + 1)
        if abs(d) < tiny { d = tiny }
        d = 1 / d
        var h = d
        for m in 1...300 {
            let m = Double(m)
            let even = m * (b - m) * x / ((a + 2 * m - 1) * (a + 2 * m))
            d = 1 + even * d
            if abs(d) < tiny { d = tiny }
            c = 1 + even / c
            if abs(c) < tiny { c = tiny }
            d = 1 / d
            h *= d * c
            let odd = -(a + m) * (a + b + m) * x / ((a + 2 * m) * (a + 2 * m + 1))
            d = 1 + odd * d
            if abs(d) < tiny { d = tiny }
            c = 1 + odd / c
            if abs(c) < tiny { c = tiny }
            d = 1 / d
            let step = d * c
            h *= step
            if abs(step - 1) < 1e-14 { break }
        }
        return h
    }
}
