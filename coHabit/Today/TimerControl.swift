import ActivityKit
import SwiftUI
import UIKit

/// Start und Stopp bei Minuten pro Woche (Vertrag §2.4b, §5.2d). Heute, Detail
/// und klassische Liste teilen ihn - ein Tipp zeigt ueberall denselben Timer.
///
/// Gezeigt wird, was gerade getippt ist, sonst was im Postausgang wartet, sonst
/// der Stand des Dienstes. Start und Stopp tragen ihre Tippzeit: ohne Netz
/// warten sie im Postausgang und gelten spaeter genauso. Die Live-Aktivitaet
/// folgt dem, was zu sehen ist.
@MainActor
@Observable
final class TimerController {

    static let shared = TimerController()
    /// So lange gilt ein Tipp, bis der neu geladene Stand ihn zeigt - sonst
    /// spraenge der Knopf nach dem Senden kurz zurueck.
    static let confirmedFor: TimeInterval = 10

    private(set) var tapped: [String: (timer: PendingTimer, at: Date)] = [:]
    /// Laeuft gerade ein Aufruf? Dann dreht der Knopf.
    private(set) var busy: Set<String> = []
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    /// Austauschbar fuer die Tests.
    var makeAPI: @MainActor () -> CohabitAPI = { Session.shared.api() }
    var outbox: CohabitOutbox = .shared
    var activities = true

    private init() {
        // Der Stopp auf dem Sperrbildschirm laeuft in diesem Prozess - danach neu laden.
        NotificationCenter.default.addObserver(forName: CohabitTimerStop.stopped, object: nil, queue: .main) { note in
            guard let id = note.object as? String else { return }
            MainActor.assumeIsolated {
                TimerController.shared.tapped[id] = (.stopped, Date())
                DataBus.shared.changed()
            }
        }
    }

    /// Seit wann der Timer laeuft - `nil`, wenn er steht.
    func startedAt(_ cohabitId: String, server: TimerView?, now: Date = Date()) -> Date? {
        if let tap = tapped[cohabitId], now.timeIntervalSince(tap.at) < Self.confirmedFor {
            return tap.timer.startedAt
        }
        if let pending = CohabitSync.shared.pendingTimers[cohabitId] { return pending.startedAt }
        return server?.startedAt
    }

    /// Wartet, bis der letzte Aufruf durch ist - fuer die Tests.
    func settled(_ cohabitId: String) async {
        await tasks[cohabitId]?.value
    }

    /// Vergisst alles Getippte - fuer die Tests.
    func reset() {
        tapped = [:]
    }

    func isWaiting(_ cohabitId: String) -> Bool {
        CohabitSync.shared.pendingTimers[cohabitId] != nil
    }

    // MARK: - Tippen

    func start(_ timer: TimerTarget) {
        guard !busy.contains(timer.id) else { return }
        let now = Date()
        tapped[timer.id] = (.running(since: now), now)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if activities { TimerActivities.start(timer, startedAt: now) }
        let request = TimerStartRequest(startedAt: now)
        send(timer, path: "/cohabits/\(timer.id)/timer", method: "POST", body: request) {
            await $0.enqueueTimerStart(cohabitId: timer.id, request: request)
        } rejected: {
            self.tapped[timer.id] = nil
            if self.activities { Task { await CohabitTimerStop.end(cohabitId: timer.id) } }
        }
    }

    func stop(_ timer: TimerTarget) {
        guard !busy.contains(timer.id) else { return }
        let now = Date()
        let started = startedAt(timer.id, server: timer.server)
        tapped[timer.id] = (.stopped, now)
        if activities { Task { await CohabitTimerStop.end(cohabitId: timer.id) } }
        let request = TimerStopRequest(stoppedAt: now)
        busy.insert(timer.id)
        tasks[timer.id] = Task {
            defer { busy.remove(timer.id) }
            do {
                let result: TimerStopResult = try await makeAPI().send("POST", "/cohabits/\(timer.id)/timer/stop",
                                                                       body: request)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if result.checkin == nil { Toast.shared.show("Unter einer Minute – nichts eingetragen.") }
                DataBus.shared.changed()
                await WidgetSync.refresh()
            } catch CohabitError.offline {
                await outbox.enqueueTimerStop(cohabitId: timer.id, request: request)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch CohabitError.server(status: 409, _) {
                // Lief schon nicht mehr - etwa im Web gestoppt.
                DataBus.shared.changed()
            } catch {
                if await Session.shared.handle(error) { return }
                // Abgelehnt (lief ueber 24 Stunden): er laeuft weiter, samt Aktivitaet.
                tapped[timer.id] = started.map { (timer: .running(since: $0), at: Date()) }
                if activities, let started { TimerActivities.start(timer, startedAt: started) }
                Toast.shared.show(error)
            }
        }
    }

    /// Verwerfen ohne Eintrag - ohne Rueckfrage (Vertrag §5.2d).
    func discard(_ timer: TimerTarget) {
        tapped[timer.id] = (.stopped, Date())
        if activities { Task { await CohabitTimerStop.end(cohabitId: timer.id) } }
        send(timer, path: "/cohabits/\(timer.id)/timer", method: "DELETE", body: Optional<CohabitAPI.EmptyBody>.none) {
            await $0.enqueueTimerDiscard(cohabitId: timer.id)
        } rejected: {
            self.tapped[timer.id] = nil
        }
    }

    private func send<Body: Encodable & Sendable>(_ timer: TimerTarget, path: String, method: String, body: Body?,
                                                  queue: @escaping (CohabitOutbox) async -> Void,
                                                  rejected: @escaping () -> Void) {
        busy.insert(timer.id)
        tasks[timer.id] = Task {
            defer { busy.remove(timer.id) }
            do {
                try await makeAPI().sendIgnoringResponse(method, path, body: body)
                DataBus.shared.changed()
            } catch CohabitError.offline {
                await queue(outbox)
            } catch {
                if await Session.shared.handle(error) { return }
                rejected()
                Toast.shared.show(error)
                DataBus.shared.changed()
            }
        }
    }

    // MARK: - Live-Aktivitaet

    /// Nach jedem Laden von „Heute": wer laeuft, hat seine Aktivitaet (auch, wenn er
    /// im Web gestartet wurde), wer steht, hat keine mehr.
    func syncActivities(_ summaries: [CohabitSummary]) {
        guard activities else { return }
        var running: [(TimerTarget, Date)] = []
        for summary in summaries where summary.timer != nil {
            if let started = startedAt(summary.id, server: summary.timer) {
                running.append((TimerTarget(summary: summary), started))
            }
        }
        TimerActivities.sync(running)
    }
}

private extension PendingTimer {
    var startedAt: Date? {
        if case .running(let since) = self { return since }
        return nil
    }
}

/// Was der Timer von einem Co-Habit wissen muss - aus „Heute", dem Detail oder
/// der klassischen Liste.
struct TimerTarget: Hashable {
    let id: String
    let name: String
    let color: PaletteKey
    let server: TimerView?

    @MainActor
    init(summary: CohabitSummary) {
        id = summary.id
        name = summary.ref.name
        color = summary.ref.typeColor
        server = summary.timer
    }
}

/// Startet, ersetzt und beendet die Live-Aktivitaeten der Timer - je Co-Habit
/// hoechstens eine. Starten kann nur die App, nie die Erweiterung.
@MainActor
enum TimerActivities {

    static func start(_ timer: TimerTarget, startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        Task {
            await CohabitTimerStop.end(cohabitId: timer.id)
            let attributes = CohabitTimerAttributes(cohabitId: timer.id, name: timer.name, color: timer.color.rawValue)
            let content = ActivityContent(state: CohabitTimerAttributes.ContentState(startedAt: startedAt),
                                          staleDate: nil)
            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            } catch {
                print("Live-Aktivität nicht gestartet: \(error.localizedDescription)")
            }
        }
    }

    /// Eine Aktivitaet zu einem Co-Habit ohne laufenden Timer geht - auch zu einem
    /// verlassenen oder geloeschten.
    static func sync(_ running: [(TimerTarget, Date)]) {
        let existing = Activity<CohabitTimerAttributes>.activities
        for (timer, started) in running {
            let current = existing.first { $0.attributes.cohabitId == timer.id && $0.activityState == .active }
            // Der Dienst speichert die Tippzeit auf die Sekunde - das ist kein anderer Start.
            if let current, abs(current.content.state.startedAt.timeIntervalSince(started)) < 2 { continue }
            start(timer, startedAt: started)
        }
        let runningIds = Set(running.map(\.0.id))
        for activity in existing where !runningIds.contains(activity.attributes.cohabitId) {
            let id = activity.attributes.cohabitId
            Task { await CohabitTimerStop.end(cohabitId: id) }
        }
    }
}

// MARK: - Knopf und Zeit

/// Der runde Start bzw. Stopp an der Stelle des Hakens - Karte, Zeile, klassische Liste.
struct TimerButton: View {
    let summary: CohabitSummary
    var size: CGFloat = 56
    var style: CheckButtonLabel.Style = .filled

    var body: some View {
        let controller = TimerController.shared
        let running = controller.startedAt(summary.id, server: summary.timer) != nil
        let target = TimerTarget(summary: summary)
        Button {
            running ? controller.stop(target) : controller.start(target)
        } label: {
            ZStack {
                if running {
                    Circle().fill(summary.ref.typeColor.colors.accent)
                } else if style == .filled {
                    Circle().fill(Ink.ink)
                } else {
                    Circle().fill(Ink.surface.opacity(0.001))
                        .overlay(Circle().strokeBorder(Ink.ink, lineWidth: 1.6))
                }
                if controller.busy.contains(summary.id) {
                    ProgressView().tint(running || style != .filled ? Ink.ink : Ink.onInk)
                } else {
                    Image(systemName: controller.isWaiting(summary.id) ? "clock" : running ? "stop.fill" : "play.fill")
                        .font(.system(size: size * 0.36, weight: .heavy))
                        .foregroundStyle(running || style != .filled ? Ink.ink : Ink.onInk)
                        .offset(x: running ? 0 : size * 0.03)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .disabled(summary.archived)
        .sensoryFeedback(.selection, trigger: running)
        .accessibilityLabel(running ? "Timer stoppen" : "Timer starten")
        .accessibilityIdentifier("timer-\(summary.id)")
    }
}

/// Die laufende Zeit, sekuendlich: „12:34", ab einer Stunde „1:02:05".
struct TimerElapsedText: View {
    let startedAt: Date

    var body: some View {
        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            .monospacedDigit()
    }
}

/// Langdruck auf eine Karte oder Zeile mit Timer: Minuten von Hand und, solange
/// er laeuft, verwerfen.
struct TimerMenu: ViewModifier {
    let summary: CohabitSummary
    @Environment(\.meId) private var meId

    func body(content: Content) -> some View {
        if summary.timer != nil, !summary.archived {
            content.contextMenu {
                if summary.canCheckIn {
                    Button(summary.checkInLabel ?? "Minuten eintragen", systemImage: "plus") {
                        CheckInController.shared.start(CheckInTarget(summary: summary, meId: meId))
                    }
                }
                if TimerController.shared.startedAt(summary.id, server: summary.timer) != nil {
                    Button("Timer verwerfen", systemImage: "xmark", role: .destructive) {
                        TimerController.shared.discard(TimerTarget(summary: summary))
                    }
                }
            }
        } else {
            content
        }
    }
}

extension View {
    func timerMenu(_ summary: CohabitSummary) -> some View {
        modifier(TimerMenu(summary: summary))
    }
}

extension CohabitSummary {
    /// Seit wann der eigene Timer laeuft, mit dem, was gerade getippt ist.
    @MainActor var timerStartedAt: Date? {
        timer == nil ? nil : TimerController.shared.startedAt(id, server: timer)
    }
}
