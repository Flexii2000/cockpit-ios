import SwiftUI
import WidgetKit

/// Der Tagesstand wie auf der Komplikation - und darunter seit 10.11. die drei
/// Makros (Felix: ein Tipp auf die Komplikation soll Eiweiss, Fett und
/// Kohlenhydrate zeigen). Die Uhr-App holt den Tag dafuer selbst, wie die
/// Komplikation; ohne Netz zeigt sie, was zuletzt da war.
struct WatchHomeView: View {

    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot = ComplicationStore.snapshot()

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                KcalGaugeView(consumed: isToday ? snapshot?.consumedKcal : nil, target: snapshot?.targetKcal)
                    .scaleEffect(1.3)
                    .frame(height: 76)
                if isToday, let consumed = snapshot?.consumed, let targets = snapshot?.targets {
                    // Knapp gesetzt: auf der kleinen Uhr (40 mm) sollen alle
                    // drei Zeilen ohne Scrollen unter den Bogen passen.
                    VStack(spacing: 3) {
                        ForEach(Macro.allCases) { macro in
                            WatchMacroRow(macro: macro, consumed: consumed, targets: targets)
                        }
                    }
                    .padding(.horizontal, 6)
                } else {
                    // Ein Stand von vor dem Update oder von gestern: nur der Bogen.
                    Text("Healthy").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    /// Erst der abgelegte Stand, dann der frische vom Kalorienzaehler.
    private func refresh() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["COCKPIT_WATCH_DEMO"] == "kcal" {
            snapshot = Self.demo
            return
        }
        #endif
        snapshot = ComplicationStore.snapshot()
        guard let cookie = ComplicationStore.cookie() else { return }
        let now = Date()
        let today = CalendarDate(date: now)
        guard let day = try? await FoodAPI(cookie: cookie, timeout: 10).day(today) else { return }
        let fresh = ComplicationSnapshot(date: today.iso, consumedKcal: day.consumed.kcal,
                                         targetKcal: day.targets.kcal, fetchedAt: now,
                                         consumed: day.consumed, targets: day.targets)
        ComplicationStore.save(snapshot: fresh)
        snapshot = fresh
        // Die Komplikation zeigt denselben Tag - sie soll nicht aelter sein als die App.
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.watchKcal)
    }

    private var isToday: Bool { snapshot?.date == Self.todayISO }

    private static var todayISO: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", parts.year ?? 2026, parts.month ?? 1, parts.day ?? 1)
    }

    #if DEBUG
    /// Erfundener Tag fuer Bilder - der Uhren-Simulator hat keinen Zugang.
    private static var demo: ComplicationSnapshot {
        ComplicationSnapshot(
            date: todayISO, consumedKcal: 1550, targetKcal: 2300, fetchedAt: Date(),
            consumed: Nutrients(kcal: 1550, proteinG: 96, carbsG: 180, fatG: 41),
            targets: Nutrients(kcal: 2300, proteinG: 195, carbsG: 236, fatG: 70, proteinMinG: 140))
    }
    #endif
}

/// Eine Makro-Zeile: „E 96/195“ und ein schmaler Balken, in der Farbe ihres
/// Stands - Eiweiss rot unter dem Erhalt, gelb ab dem Erhalt, gruen ab dem Ziel
/// (Vertrag §11.1); Fett und Kohlenhydrate erst ueber dem Ziel gelb und rot.
struct WatchMacroRow: View {

    let macro: Macro
    let consumed: Nutrients
    let targets: Nutrients

    var body: some View {
        let tone = NutritionTone.tone(for: macro, consumed: consumed, targets: targets)
        let target = macro.value(targets)
        let fraction = target > 0 ? min(max(macro.value(consumed) / target, 0), 1) : 0
        VStack(alignment: .leading, spacing: 2) {
            Text(WatchMacroText.label(macro, consumed: consumed, targets: targets))
                .font(.system(.footnote, design: .rounded).monospacedDigit())
                .foregroundStyle(tone == .neutral || tone == .near ? Color.primary : tone.watchColor)
            // Von Hand statt `ProgressView`: dessen Balken ist auf der Uhr so
            // dick, dass die dritte Zeile aus dem Bild rutscht.
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(tone.watchColor.opacity(0.25))
                    Capsule().fill(tone.watchColor)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(macro.label)
    }
}
