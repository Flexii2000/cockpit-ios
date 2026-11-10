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
                    // Drei kleine Tachos nebeneinander (Felix, 10.11.: Tachos, keine
                    // Balken) - knapp gesetzt, damit sie auch auf der kleinen Uhr
                    // (40 mm) ohne Scrollen unter den kcal-Bogen passen.
                    HStack(alignment: .top, spacing: 2) {
                        ForEach(Macro.allCases) { macro in
                            WatchMacroGauge(macro: macro, consumed: consumed, targets: targets)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.top, 2)
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

/// Ein Makro als kleiner Tacho (Felix, 10.11.: Tachos statt Balken): ein offener
/// Bogen wie in der Essen-Ansicht des iPhones, der sich bis zum Ziel fuellt, in
/// der Mitte das Gegessene, in der Luecke unten das Kuerzel, darunter das Ziel.
/// Die Farbe ist die des Stands - Eiweiss rot unter dem Erhalt, gelb ab dem
/// Erhalt, gruen ab dem Ziel (Vertrag §11.1); Fett und Kohlenhydrate erst ueber
/// dem Ziel gelb und rot.
struct WatchMacroGauge: View {

    let macro: Macro
    let consumed: Nutrients
    let targets: Nutrients

    /// Der Bogen laesst unten ein Viertel offen.
    private static let sweep = 0.75
    private static let lineWidth: CGFloat = 4

    var body: some View {
        let tone = NutritionTone.tone(for: macro, consumed: consumed, targets: targets)
        let eaten = macro.value(consumed)
        let target = macro.value(targets)
        let fraction = target > 0 ? min(max(eaten / target, 0), 1) : 0
        VStack(spacing: 1) {
            ZStack {
                arc(to: 1).stroke(tone.watchColor.opacity(0.25), style: Self.stroke)
                arc(to: fraction).stroke(tone.watchColor, style: Self.stroke)
                Text(String(Int(eaten.rounded())))
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                Text(macro.short)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .offset(y: 3)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 50)
            .padding(Self.lineWidth / 2)
            Text("\(Int(target.rounded())) g")
                .font(.system(size: 10, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(macro.label)
        .accessibilityValue(WatchMacroText.label(macro, consumed: consumed, targets: targets))
    }

    private static var stroke: StrokeStyle { StrokeStyle(lineWidth: lineWidth, lineCap: .round) }

    /// Der Bogen von links unten im Uhrzeigersinn; `share` 1 ist der ganze Tacho.
    private func arc(to share: Double) -> some Shape {
        Circle()
            .trim(from: 0, to: Self.sweep * share)
            .rotation(.degrees(135))
    }
}
