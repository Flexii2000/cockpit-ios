import SwiftUI

/// Anfangszeiten wie auf der Seite: jede halbe Stunde von 07:00 bis 22:00.
enum PadelTimes {
    static let starts: [String] = stride(from: 7 * 60, through: 22 * 60, by: 30).map {
        String(format: "%02d:%02d", $0 / 60, $0 % 60)
    }
    static let durations = [60, 90, 120]
    static let weekdays: [(id: String, label: String)] = [
        ("MONDAY", "Montag"), ("TUESDAY", "Dienstag"), ("WEDNESDAY", "Mittwoch"), ("THURSDAY", "Donnerstag"),
        ("FRIDAY", "Freitag"), ("SATURDAY", "Samstag"), ("SUNDAY", "Sonntag"),
    ]

    static func iso(_ date: Date) -> String {
        CalendarDate(date: date, in: TimeZone(identifier: "Europe/Berlin") ?? .current).iso
    }
}

/// Neue Serie: Wochentag, erster und spaetester Beginn, Dauer, Club, Mitspieler (Felix, 23.10.).
struct PadelSeriesSheet: View {

    let store: PadelStore
    @Environment(\.dismiss) private var dismiss

    @State private var weekday = "MONDAY"
    @State private var start = "18:00"
    /// Leer: nur die eine Zeit.
    @State private var latest = "21:00"
    @State private var minutes = 90
    /// Leer: alle Clubs, Aspria als Rueckfall.
    @State private var club = ""
    @State private var partner = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Wochentag", selection: $weekday) {
                    ForEach(PadelTimes.weekdays, id: \.id) { Text($0.label).tag($0.id) }
                }
                Picker("Beginn", selection: $start) {
                    ForEach(PadelTimes.starts, id: \.self) { Text($0).tag($0) }
                }
                Picker("Bis", selection: $latest) {
                    Text("–").tag("")
                    ForEach(PadelTimes.starts, id: \.self) { Text($0).tag($0) }
                }
                Picker("Dauer", selection: $minutes) {
                    ForEach(PadelTimes.durations, id: \.self) { Text("\($0)′").tag($0) }
                }
                Picker("Club", selection: $club) {
                    Text("Alle").tag("")
                    ForEach(store.overview?.clubs ?? []) { Text($0.label).tag($0.id) }
                }
                Picker("Mitspieler", selection: $partner) {
                    ForEach(store.overview?.partners ?? []) { Text($0.label).tag($0.id) }
                }
            }
            .navigationTitle("Neue Serie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        Task {
                            let request = PadelSeriesRequest(weekday: weekday, start: start, durationMinutes: minutes,
                                                             latestStart: latest.isEmpty ? nil : latest,
                                                             club: club.isEmpty ? nil : club,
                                                             partner: partner.isEmpty ? nil : partner)
                            if await store.createSeries(request) { dismiss() }
                        }
                    }
                    .disabled(store.isWorking)
                }
            }
            .onAppear { if partner.isEmpty { partner = store.overview?.partners?.first?.id ?? "" } }
        }
    }
}

/// Ein Termin ausser der Reihe.
struct PadelOneOffSheet: View {

    let store: PadelStore
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date().addingTimeInterval(7 * 86_400)
    @State private var start = "18:00"
    @State private var minutes = 90
    @State private var club = "mitte"
    @State private var partner = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Datum", selection: $date, in: Date()..., displayedComponents: .date)
                Picker("Beginn", selection: $start) {
                    ForEach(PadelTimes.starts, id: \.self) { Text($0).tag($0) }
                }
                Picker("Dauer", selection: $minutes) {
                    ForEach(PadelTimes.durations, id: \.self) { Text("\($0)′").tag($0) }
                }
                Picker("Club", selection: $club) {
                    ForEach(store.overview?.clubs ?? []) { Text($0.label).tag($0.id) }
                }
                Picker("Mitspieler", selection: $partner) {
                    ForEach(store.overview?.partners ?? []) { Text($0.label).tag($0.id) }
                }
            }
            .navigationTitle("Einmalig")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        Task {
                            let slot = PadelSlotRequest(date: PadelTimes.iso(date), start: start, durationMinutes: minutes,
                                                        club: club, partner: partner.isEmpty ? nil : partner)
                            if await store.addOneOff(slot) { dismiss() }
                        }
                    }
                    .disabled(store.isWorking)
                }
            }
            .onAppear { if partner.isEmpty { partner = store.overview?.partners?.first?.id ?? "" } }
        }
    }
}

/// Einen Termin verschieben (nur, wo der Dienst es erlaubt).
struct PadelMoveSheet: View {

    let occurrence: PadelOccurrence
    let store: PadelStore
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var start = "18:00"
    @State private var minutes = 90

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Datum", selection: $date, in: Date()..., displayedComponents: .date)
                Picker("Beginn", selection: $start) {
                    ForEach(PadelTimes.starts, id: \.self) { Text($0).tag($0) }
                }
                Picker("Dauer", selection: $minutes) {
                    ForEach(PadelTimes.durations, id: \.self) { Text("\($0)′").tag($0) }
                }
            }
            .navigationTitle("Verschieben")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Verschieben") {
                        Task {
                            if await store.move(occurrence, date: PadelTimes.iso(date), start: start, minutes: minutes) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(store.isWorking)
                }
            }
            .onAppear {
                start = occurrence.start
                minutes = occurrence.durationMinutes
                if let day = CalendarDate(iso: occurrence.date) { date = day.startOfDay() }
            }
        }
    }
}

/// Die Plaetze in Felix' Reihenfolge - verschieben, herausnehmen, wieder hinein.
struct PadelCourtsView: View {

    let store: PadelStore

    var body: some View {
        let courts = store.overview?.courts ?? []
        let order = courts.filter { $0.position >= 0 }.sorted { $0.position < $1.position }
        let off = courts.filter { $0.position < 0 }
        List {
            Section {
                ForEach(Array(order.enumerated()), id: \.element.id) { index, court in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(index + 1). Platz \(court.shortName)")
                            Text(court.name).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Raus") { save(order.map(\.id).filter { $0 != court.id }) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(order.count == 1)
                    }
                }
                .onMove { from, to in
                    var ids = order.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    save(ids)
                }
            }
            if !off.isEmpty {
                Section {
                    ForEach(off) { court in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Platz \(court.shortName)").foregroundStyle(.secondary)
                                Text(court.name).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Rein") { save(order.map(\.id) + [court.id]) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Plätze")
        .disabled(store.isWorking)
    }

    private func save(_ ids: [String]) {
        Task { await store.saveCourtOrder(ids) }
    }
}
