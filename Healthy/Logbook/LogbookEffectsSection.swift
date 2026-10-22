import SwiftUI

/// Die Effekte unter dem Logbook (Vertrag §4.1/§4.2): was eine Verhaltensweise,
/// ein Co-Habit oder ein Healthy-Wert mit der Recovery des naechsten Morgens zu
/// tun hat. Gerechnet im Weight Tracker, hier nur gezeigt.
///
/// Die drei staerksten; „Alle Effekte (n)“ klappt an Ort und Stelle auf. Der
/// Zeitraum (30 · 90 · 180 · 365 Tage) bleibt gemerkt.
struct LogbookEffectsSection: View {

    let store: LogbookStore
    @State private var showsAll = false

    var body: some View {
        if let insights = store.insights {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Effekte").font(.headline)
                    Spacer()
                    // Unter 14 Morgen mit Score rechnet der Dienst nichts - wie weit
                    // es noch ist, sagt die Zahl.
                    if !insights.hasEnoughNights {
                        Text("\(insights.nightsWithScore)/\(LogbookInsights.requiredNights) Morgen")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Picker("Zeitraum", selection: Binding(
                    get: { store.period },
                    set: { period in Task { await store.select(period: period) } })) {
                    ForEach(LogbookAPI.periods, id: \.self) { days in
                        Text("\(days)").tag(days)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Zeitraum in Tagen")

                ForEach(insights.unavailableSources, id: \.self) { source in
                    Label("\(source) nicht erreichbar", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Tone.warn.color)
                }
                ForEach(showsAll ? insights.evaluated : insights.strongest) { predictor in
                    LogbookEffectRow(predictor: predictor)
                }
                if showsAll, !insights.notEvaluated.isEmpty {
                    Text("Zu wenig Daten")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ForEach(insights.notEvaluated) { predictor in
                        LogbookPendingRow(predictor: predictor)
                    }
                }
                if insights.predictors.count > insights.strongest.count {
                    Button {
                        withAnimation(.snappy) { showsAll.toggle() }
                    } label: {
                        Text(showsAll ? "Weniger" : "Alle Effekte (\(insights.predictors.count))")
                            .font(.subheadline.weight(.medium))
                    }
                    .accessibilityIdentifier("logbookAllEffects")
                }
            }
            .dashboardCard()
        }
    }
}

/// „Name  +8,1 %-Pkt **", darunter die Bausteine „HRV +9 % · RHF −1,9 bpm"
/// und „[+3,2; +13,0] · 41 ja · 37 nein".
struct LogbookEffectRow: View {

    let predictor: Predictor

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            LogbookSourceIcon(source: predictor.source)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(predictor.name)
                        .font(.subheadline.weight(.medium))
                    if let perUnit = LogbookFormat.perUnit(predictor) {
                        Text(perUnit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if let effect = LogbookFormat.effectLine(predictor) {
                        Text(effect)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(color)
                            .fixedSize()
                    }
                }
                // Ohne Farbe und ohne Sterne: getestet ist nur der Effekt darueber.
                if let components = LogbookFormat.components(predictor) {
                    Text(components)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(LogbookFormat.detail(predictor))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Farbe nur fuer, was nach Holm traegt - ein Effekt ohne Stern ist noch
    /// kein Befund.
    private var color: Color {
        guard let effect = predictor.effect, !LogbookFormat.stars(predictor.pAdjusted).isEmpty else {
            return .primary
        }
        return effect >= 0 ? Tone.good.color : Tone.warn.color
    }
}

/// Eine Zeile ohne Effekt: wie weit sie noch ist („3/5 ja · 5/5 nein").
private struct LogbookPendingRow: View {

    let predictor: Predictor

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            LogbookSourceIcon(source: predictor.source)
            Text(predictor.name)
                .font(.subheadline)
            if let perUnit = LogbookFormat.perUnit(predictor) {
                Text(perUnit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(LogbookFormat.notEvaluated(predictor))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Woher eine Zeile stammt, als kleines Symbol: eigenes Verhalten, Co-Habit
/// oder ein Wert aus Healthy.
struct LogbookSourceIcon: View {

    let source: PredictorSource

    var body: some View {
        Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 16)
            .accessibilityLabel(label)
    }

    private var symbol: String {
        switch source {
        case .logbook: "book.closed"
        case .cohabit: Backend.cohabit.systemImage
        case .healthy: "heart"
        case .unknown: "circle"
        }
    }

    private var label: String {
        switch source {
        case .logbook: "Logbook"
        case .cohabit: "coHabit"
        case .healthy: "Healthy"
        case .unknown: ""
        }
    }
}
