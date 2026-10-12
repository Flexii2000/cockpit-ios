import SwiftUI

/// Zaehlen beim Tageslimit (Vertrag §2.5a, §5.2c). Heute, Detail und klassische
/// Liste teilen ihn - ein Tipp zeigt ueberall dieselbe Zahl.
///
/// Gezeigt wird, was gerade getippt ist, sonst was im Postausgang wartet, sonst
/// der Stand des Dienstes. Geschickt wird absolut („3“, nicht „eins mehr“) nach
/// einer halben Sekunde Ruhe, je Co-Habit und Tag hoechstens ein Aufruf zur
/// Zeit. Ohne Netz - oder wenn der Dienst bzw. das Logbook nicht antwortet -
/// wartet die Zahl im Postausgang und steht mit Uhr da. Lehnt der Dienst ab,
/// springt sie auf seinen Stand zurueck, und seine Meldung erscheint.
@MainActor
@Observable
final class LimitCounter {

    static let shared = LimitCounter()
    /// Wie im Logbook.
    static let maxCount: Double = 10_000
    /// So lange gilt eine angekommene Zahl, bis der neu geladene Stand sie zeigt -
    /// sonst blitzte nach dem Senden kurz die alte auf.
    static let confirmedFor: TimeInterval = 10

    /// Getippt und noch nicht abgegeben - je Co-Habit und Tag.
    private(set) var typed: [LimitKey: Double] = [:]
    /// Beim Dienst angekommen, aber vielleicht noch nicht neu geladen.
    private(set) var confirmed: [LimitKey: (count: Double, at: Date)] = [:]
    @ObservationIgnored private var settling: [LimitKey: Task<Void, Never>] = [:]
    /// Je Tag der laufende Aufruf - der naechste wartet auf ihn.
    @ObservationIgnored private var chains: [LimitKey: Task<Void, Never>] = [:]

    /// Austauschbar fuer die Tests.
    var makeAPI: @MainActor () -> CohabitAPI = { Session.shared.api() }
    var outbox: CohabitOutbox = .shared
    var settleDelay: Duration = .milliseconds(500)

    init() {}

    /// Die Zahl, die zu sehen ist; `nil`, wenn das Logbook nichts liefert und
    /// nichts getippt ist.
    func count(_ key: LimitKey, server: Double?, now: Date = Date()) -> Double? {
        if let value = typed[key] ?? CohabitSync.shared.pendingLimits[key] { return value }
        if let done = confirmed[key], now.timeIntervalSince(done.at) < Self.confirmedFor { return done.count }
        return server
    }

    /// Die Uhr: die Zahl wartet im Postausgang.
    func isWaiting(_ key: LimitKey) -> Bool {
        CohabitSync.shared.pendingLimits[key] != nil
    }

    func step(_ key: LimitKey, server: Double?, by delta: Int) {
        let next = min(max((count(key, server: server) ?? 0) + Double(delta), 0), Self.maxCount)
        typed[key] = next
        settling[key]?.cancel()
        settling[key] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.settleDelay)
            guard !Task.isCancelled else { return }
            self.settling[key] = nil
            self.send(key, next)
        }
    }

    /// Wartet auf das Abgeben - fuer die Tests.
    func settled(_ key: LimitKey) async {
        await settling[key]?.value
        await chains[key]?.value
    }

    private func send(_ key: LimitKey, _ value: Double) {
        let previous = chains[key]
        chains[key] = Task { [weak self] in
            await previous?.value
            await self?.deliver(key, value)
        }
    }

    private func deliver(_ key: LimitKey, _ value: Double) async {
        // Wartet fuer diesen Tag schon eine Zahl, kommt die neue dahinter - ein
        // direkter Aufruf ueberholte die wartende sonst.
        if CohabitSync.shared.pendingLimits[key] != nil {
            await wait(key, value)
            return
        }
        do {
            try await makeAPI().sendIgnoringResponse("PUT", LimitCountRequest.path(cohabitId: key.cohabitId, date: key.date),
                                                     body: LimitCountRequest(count: value))
            confirmed[key] = (value, Date())
            release(key, value)
            DataBus.shared.changed()
        } catch let error as CohabitError {
            switch error {
            case .offline, .queued:
                await wait(key, value)
            case .server(let status, _) where status >= 500 || status == 408 || status == 429:
                // Der Dienst oder das Logbook antwortet nicht: spaeter nochmal.
                await wait(key, value)
            case .unauthorized:
                await wait(key, value)
                _ = await Session.shared.handle(error)
            default:
                reject(key, value, error)
            }
        } catch {
            reject(key, value, error)
        }
    }

    private func wait(_ key: LimitKey, _ value: Double) async {
        await outbox.enqueueLimitCount(cohabitId: key.cohabitId, date: key.date, count: value)
        release(key, value)
    }

    /// Abgelehnt: zurueck auf den Stand des Dienstes, mit seinem Grund.
    private func reject(_ key: LimitKey, _ value: Double, _ error: Error) {
        confirmed[key] = nil
        release(key, value)
        Toast.shared.show(error)
        DataBus.shared.changed()
    }

    /// Die getippte Zahl ist abgegeben - ausser, es wurde inzwischen weitergetippt.
    private func release(_ key: LimitKey, _ value: Double) {
        if typed[key] == value, settling[key] == nil { typed[key] = nil }
    }
}

extension LimitView {
    /// „heute 3 von 4 Tassen“ mit der Zahl, die gerade zu sehen ist.
    func liveText(_ count: Double?, withUnit: Bool = true) -> String {
        let text = "heute \(LimitFormat.count(count ?? 0)) von \(perDay)"
        guard withUnit, let unit, !unit.isEmpty else { return text }
        return text + " " + unit
    }
}

/// „2", „2,5" - wie im Logbook.
enum LimitFormat {
    static func count(_ value: Double?) -> String {
        guard let value else { return "–" }
        return value.formatted(.number.locale(Locale(identifier: "de_DE")).precision(.fractionLength(0...1)))
    }
}

/// Das runde „+“ an der Stelle des Hakens - Karte und Zeile in Heute.
struct LimitPlusButton: View {
    let cohabitId: String
    let limit: LimitView
    var size: CGFloat = 56
    var style: CheckButtonLabel.Style = .filled

    var body: some View {
        let counter = LimitCounter.shared
        let key = LimitKey(cohabitId: cohabitId, date: limit.date)
        let count = counter.count(key, server: limit.count)
        Button { counter.step(key, server: limit.count, by: 1) } label: {
            Image(systemName: counter.isWaiting(key) ? "clock" : "plus")
                .font(.system(size: size * 0.38, weight: .heavy))
                .foregroundStyle(style == .filled ? Ink.onInk : Ink.ink)
                .frame(width: size, height: size)
                .background {
                    if style == .filled {
                        Circle().fill(Ink.ink)
                    } else {
                        Circle().fill(Ink.surface.opacity(0.001))
                            .overlay(Circle().strokeBorder(Ink.ink, lineWidth: 1.6))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!limit.canCount)
        .sensoryFeedback(.increase, trigger: count)
        .accessibilityLabel("Eins mehr")
        .accessibilityValue(LimitFormat.count(count))
        .accessibilityIdentifier("plus-\(cohabitId)")
    }
}

/// „− 3 +“ - fuer heute unten auf der Detailseite und im Blatt fuer einen
/// frueheren Tag.
struct LimitStepper: View {
    let cohabitId: String
    let date: CalendarDate
    /// Der Stand des Dienstes fuer diesen Tag.
    let server: Double?
    let perDay: Int
    var enabled = true

    var body: some View {
        let counter = LimitCounter.shared
        let key = LimitKey(cohabitId: cohabitId, date: date)
        let count = counter.count(key, server: server)
        let over = (count ?? 0) > Double(perDay)
        HStack(spacing: 18) {
            stepButton("minus", label: "Eins weniger", id: "limitMinus") {
                counter.step(key, server: server, by: -1)
            }
            .disabled(!enabled || (count ?? 0) <= 0)
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text(LimitFormat.count(count ?? 0))
                        .font(.figure(40))
                        .foregroundStyle(over ? Ink.danger : Ink.ink)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("limitCount")
                    if counter.isWaiting(key) {
                        Image(systemName: "clock")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Ink.muted)
                            .accessibilityLabel("wartet auf Netz")
                    }
                }
                Text("von \(perDay)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Ink.muted)
            }
            .frame(minWidth: 84)
            stepButton("plus", label: "Eins mehr", id: "limitPlus") {
                counter.step(key, server: server, by: 1)
            }
            .disabled(!enabled)
        }
        .sensoryFeedback(.selection, trigger: count)
        .animation(.snappy, value: count)
    }

    private func stepButton(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Ink.onInk)
                .frame(width: 60, height: 60)
                .background(Circle().fill(Ink.ink))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}
