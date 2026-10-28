import SwiftUI

/// Eine Rueckfrage vor etwas Endgueltigem (stornieren, entfernen, oeffentlich stellen).
struct PadelConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let button: String
    let action: () async -> Void
}

// MARK: - Bausteine

/// Ein kleines Schild: Club, „einmalig“, „ab 06.11.“ - in der Farbe des Mitspielers gefuellt.
struct PadelTag: View {
    let text: String
    var color: Color?

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color == nil ? Color.secondary : Color.black.opacity(0.85))
            .background(color ?? Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// „mit Person B“ - nur in Felix' Ansicht; ein Mitspieler sieht ohnehin nur seine.
struct PadelPartnerTag: View {
    let name: String?
    let color: String?

    var body: some View {
        if let name {
            PadelTag(text: "mit \(name)", color: PadelColor.color(color))
        }
    }
}

extension View {
    /// Hinterlegt in der Farbe des Mitspielers (Felix, 23.10.; sie kommt vom Dienst), mit
    /// einem Strich vorn - wie auf der Seite.
    func padelTint(_ hex: String?) -> some View {
        listRowBackground(PadelTintBackground(color: PadelColor.color(hex)))
    }
}

private struct PadelTintBackground: View {
    let color: Color?

    var body: some View {
        if let color {
            ZStack(alignment: .leading) {
                Color(.secondarySystemGroupedBackground)
                color.opacity(0.18)
                Rectangle().fill(color).frame(width: 3)
            }
        } else {
            Color(.secondarySystemGroupedBackground)
        }
    }
}

/// Die Knoepfe unter einem Eintrag - umbrechend, klein, jeder fuer sich antippbar.
struct PadelActions<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) { content.fixedSize() }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }
}

// MARK: - Nächster Termin

struct PadelNextCard: View {
    let next: PadelOccurrence
    let occurrences: [PadelOccurrence]
    let store: PadelStore
    let ask: (PadelConfirmation) -> Void

    var body: some View {
        let day = PadelPlan.day(of: next, in: occurrences)
        VStack(alignment: .leading, spacing: 6) {
            Text(day.count > 1
                 ? "\(PadelFormat.dayLabel(next.date, next.weekday)) · ab \(PadelPlan.earliest(day))"
                 : "\(next.club) · \(PadelFormat.dayLabel(next.date, next.weekday)) · \(next.start)–\(next.end)")
                .font(.title3.weight(.semibold))
            FlowLayout(spacing: 6, lineSpacing: 4) {
                if day.count > 1 {
                    ForEach(PadelPlan.together(next, day: day), id: \.self) { PadelTag(text: $0) }
                }
                if store.isOwner { PadelPartnerTag(name: next.partner, color: next.partnerColor) }
            }
            if next.status == "PLANNED" {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Buchung startet \(PadelFormat.when(next.releaseAt, seconds: true)) · ")
                        .foregroundStyle(.secondary)
                    + Text(PadelFormat.countdown(to: next.releaseAt, now: context.date))
                        .foregroundStyle(.orange)
                        .fontWeight(.semibold)
                }
                .font(.subheadline.monospacedDigit())
            } else {
                PadelStatusLine(occurrence: next)
            }
            if day.count > 1 {
                PadelDayActions(occurrences: day, store: store, ask: ask)
            } else {
                PadelOccurrenceActions(occurrence: next, store: store, ask: ask)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("padelNext")
    }
}

/// Wie ein Termin steht; bei 3-D Secure mit dem Link zur Bank.
struct PadelStatusLine: View {
    let occurrence: PadelOccurrence

    var body: some View {
        HStack(spacing: 6) {
            Text(PadelPlan.status(occurrence))
                .foregroundStyle(["WATCHING", "AWAITING_APPROVAL", "BOOKING"].contains(occurrence.status)
                                 ? Color.orange : Color.secondary)
            if occurrence.status == "AWAITING_APPROVAL", let url = occurrence.approvalUrl.flatMap(URL.init(string:)) {
                Link("Bank öffnen", destination: url)
            }
        }
        .font(.footnote)
    }
}

// MARK: - Gebucht

struct PadelBookingRow: View {
    let booking: PadelBooking
    let store: PadelStore
    let ask: (PadelConfirmation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(PadelFormat.dayLabel(booking.date, booking.weekday)) · \(booking.start)–\(booking.end)")
                .font(.headline)
            FlowLayout(spacing: 6, lineSpacing: 4) {
                Text(["Platz \(booking.court)", PadelFormat.price(booking.price, split: booking.split)]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                PadelTag(text: booking.club)
                if store.isOwner { PadelPartnerTag(name: booking.partner, color: booking.partnerColor) }
                if let longer = booking.extendTo { PadelTag(text: "→ \(longer)′") }
            }
            Text(PadelPlan.bookingLine(booking))
                .font(.footnote)
                .foregroundStyle(.secondary)
            PadelActions {
                if let url = URL(string: booking.inviteUrl) {
                    // Mit eigenem Etikett: das vorgegebene (Symbol und Text) nimmt im Umbruch die
                    // ganze Hoehe, die es angeboten bekommt.
                    ShareLink(item: url) { Text("Einladen") }
                }
                if booking.publishable {
                    Button("Öffentlich stellen") {
                        ask(PadelConfirmation(title: "Endgültig öffentlich stellen?", button: "Öffentlich stellen") {
                            await store.publish(booking)
                        })
                    }
                }
                if booking.mergeable && store.isOwner {
                    Button("Zusammenführen") {
                        ask(PadelConfirmation(title: "Zu 90′ zusammenführen?", button: "Zusammenführen") {
                            await store.merge(booking)
                        })
                    }
                }
                if booking.cancellable {
                    Button("Stornieren", role: .destructive) {
                        ask(PadelConfirmation(title: "Wirklich stornieren?", button: "Stornieren") {
                            await store.cancel(booking)
                        })
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .padelTint(store.isOwner ? booking.partnerColor : nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("padelBooking-\(booking.matchId)")
    }
}

// MARK: - Ergebnisse

struct PadelResultRow: View {
    let result: PadelResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FlowLayout(spacing: 6, lineSpacing: 4) {
                Text("\(PadelFormat.when(result.startedAt)) · \(result.summary)")
                    .font(.headline.monospacedDigit())
                if let club = result.club { PadelTag(text: club) }
                PadelPartnerTag(name: result.partner, color: result.partnerColor)
            }
            Text(result.statusText)
                .font(.footnote)
                .foregroundStyle(result.status == "FAILED" ? Color.red : Color.secondary)
        }
        .padding(.vertical, 2)
        .padelTint(result.partnerColor)
    }
}

// MARK: - Kosten

/// Ein Monat oder die Prognose: links was, rechts der Betrag. Vormonate stehen leiser.
struct PadelCostRow: View {
    let title: String
    let detail: String?
    let amount: Double
    var past = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(past ? .body : .headline)
                    .foregroundStyle(past ? .secondary : .primary)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(PadelFormat.euro(amount))
                .font((past ? Font.body : .headline).monospacedDigit())
                .foregroundStyle(past ? .secondary : .primary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Geplant

struct PadelDayRow: View {
    let day: PadelDay
    let store: PadelStore
    let ask: (PadelConfirmation) -> Void
    @Binding var moving: PadelOccurrence?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let single = day.occurrences.first, day.isSingle {
                Text("\(PadelFormat.dayLabel(single.date, single.weekday)) · \(single.start)–\(single.end)")
                    .font(.headline)
                    .strikethrough(single.status == "SKIPPED" || single.status == "CANCELLED")
                FlowLayout(spacing: 6, lineSpacing: 4) {
                    PadelTag(text: single.club)
                    if store.isOwner { PadelPartnerTag(name: single.partner, color: single.partnerColor) }
                    if single.oneOff { PadelTag(text: "einmalig") }
                    if single.moved { PadelTag(text: "verschoben") }
                    if let shorter = single.alternativeMinutes, shorter < single.durationMinutes {
                        PadelTag(text: "auch \(shorter)′")
                    }
                }
                PadelStatusLine(occurrence: single)
                PadelOccurrenceActions(occurrence: single, store: store, ask: ask, moving: $moving)
            } else {
                Text("\(PadelFormat.dayLabel(day.date, day.weekday)) · ab \(PadelPlan.earliest(day.occurrences))")
                    .font(.headline)
                    .foregroundStyle(isOpen ? Color.primary : Color.secondary)
                FlowLayout(spacing: 6, lineSpacing: 4) {
                    ForEach(clubs, id: \.self) { PadelTag(text: $0) }
                    if store.isOwner { PadelPartnerTag(name: day.partner, color: day.partnerColor) }
                }
                Text(PadelPlan.summary(day))
                    .font(.footnote)
                    .foregroundStyle(isWatching ? Color.orange : Color.secondary)
                PadelDayActions(occurrences: day.occurrences, store: store, ask: ask)
            }
        }
        .padding(.vertical, 2)
        .padelTint(store.isOwner ? day.partnerColor : nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("padelDay-\(day.date)")
    }

    private var clubs: [String] {
        var seen: [String] = []
        for o in day.occurrences where !o.fallback && !seen.contains(o.club) { seen.append(o.club) }
        return seen
    }

    private var isOpen: Bool { day.occurrences.contains { PadelPlan.open.contains($0.status) } }

    private var isWatching: Bool {
        !day.occurrences.contains { $0.status == "PLANNED" } && day.occurrences.contains { $0.status == "WATCHING" }
    }
}

/// Aussetzen und Fortsetzen fuer den ganzen Tag (mit diesem Mitspieler); ein ausgesetzter Tag
/// laesst sich auch ganz entfernen (nur Felix).
struct PadelDayActions: View {
    let occurrences: [PadelOccurrence]
    let store: PadelStore
    let ask: (PadelConfirmation) -> Void

    var body: some View {
        let skippable = occurrences.first(where: \.canSkip)
        let resumable = occurrences.first { $0.canUnskip && PadelPlan.skippedByPerson($0) }
        let removable = skippable == nil ? occurrences.first(where: \.canRemove) : nil
        if skippable != nil || resumable != nil || removable != nil {
            PadelActions {
                if let skippable {
                    Button("Aussetzen") { Task { await store.skip(skippable, day: true) } }
                } else if let resumable {
                    Button("Fortsetzen") { Task { await store.unskip(resumable, day: true) } }
                }
                if let removable {
                    Button("Entfernen", role: .destructive) {
                        ask(PadelConfirmation(title: "Den Tag wirklich entfernen?", button: "Entfernen") {
                            await store.remove(removable, day: true)
                        })
                    }
                }
            }
            .disabled(store.isWorking)
        }
    }
}

/// Die Knoepfe eines einzelnen Termins - nur, was der Dienst erlaubt (`can…`).
struct PadelOccurrenceActions: View {
    let occurrence: PadelOccurrence
    let store: PadelStore
    let ask: (PadelConfirmation) -> Void
    var moving: Binding<PadelOccurrence?>?

    var body: some View {
        let o = occurrence
        if o.canSkip || o.canUnskip || o.canRetry || (o.canMove && moving != nil) || o.canRemove {
            PadelActions {
                if o.canSkip { Button("Aussetzen") { Task { await store.skip(o) } } }
                if o.canUnskip { Button("Fortsetzen") { Task { await store.unskip(o) } } }
                if o.canRetry { Button("Nochmal") { Task { await store.retry(o) } } }
                if o.canMove, let moving { Button("Verschieben") { moving.wrappedValue = o } }
                if o.canRemove {
                    Button("Entfernen", role: .destructive) {
                        ask(PadelConfirmation(title: "Wirklich entfernen?", button: "Entfernen") {
                            await store.remove(o)
                        })
                    }
                }
            }
            .disabled(store.isWorking)
        }
    }
}

// MARK: - Serien

struct PadelSeriesRow: View {
    let series: PadelSeries
    let store: PadelStore
    let ask: (PadelConfirmation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(PadelPlan.title(series))
                .font(.headline)
                .foregroundStyle(series.active ? Color.primary : Color.secondary)
            FlowLayout(spacing: 6, lineSpacing: 4) {
                ForEach(series.clubs, id: \.self) { PadelTag(text: $0) }
                PadelPartnerTag(name: series.partnerLabel, color: series.partnerColor)
                if let first = series.firstDate {
                    PadelTag(text: "ab " + PadelFormat.dayLabel(first, "").trimmingCharacters(in: .whitespaces))
                }
                if series.levelLimit == true { PadelTag(text: "Level −0,5/+0,7") }
                if !series.active { PadelTag(text: "pausiert") }
            }
            PadelActions {
                Button(series.active ? "Pausieren" : "Fortsetzen") {
                    Task { await store.setActive(series, !series.active) }
                }
                Button("Löschen", role: .destructive) {
                    ask(PadelConfirmation(title: "Serie wirklich löschen?", button: "Löschen") {
                        await store.delete(series)
                    })
                }
            }
            .disabled(store.isWorking)
        }
        .padding(.vertical, 2)
        .padelTint(series.partnerColor)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("padelSeries-\(series.id)")
    }
}
