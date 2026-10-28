import Foundation
import SwiftUI

// Was der Padel-Dienst schickt (padel/src/main/java/com/fherrmann/padel/dto/Views.java und
// BookingService.BookingView) - die Feldnamen sind der Vertrag. Gerechnet wird beim Dienst:
// Freigaben, was erlaubt ist (`can…`), Stand der Ergebnisse; die App zeigt.

/// Die Uebersicht - fuer Felix mit Serien, Plaetzen, Stand und Ergebnissen.
struct PadelOverview: Decodable, Equatable, Sendable {
    let viewer: PadelViewer
    let now: Date
    let dryRun: Bool
    /// Der Termin, dessen Freigabe als naechstes ansteht.
    let next: PadelOccurrence?
    let occurrences: [PadelOccurrence]
    let series: [PadelSeries]?
    let courts: [PadelCourt]?
    let status: PadelStatus?
    let feedUrl: String
    let clubs: [PadelChoice]?
    let partners: [PadelPartner]?
    let results: [PadelResult]?
}

struct PadelViewer: Decodable, Equatable, Sendable {
    let name: String
    let owner: Bool
}

/// Ein Termin: eine Zeit bei einem Club an einem Tag.
struct PadelOccurrence: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let oneOff: Bool
    let moved: Bool
    /// yyyy-MM-dd
    let date: String
    /// „Mo“, „Di“ …
    let weekday: String
    /// HH:mm
    let start: String
    let end: String
    let durationMinutes: Int
    /// PLANNED, SKIPPED, BOOKING, AWAITING_APPROVAL, WATCHING, BOOKED, MISSED, CANCELLED
    let status: String
    let note: String?
    let releaseAt: Date
    let watchUntil: Date
    let court: String?
    let price: String?
    let matchId: String?
    let inviteUrl: String?
    let approvalUrl: String?
    let canSkip: Bool
    let canUnskip: Bool
    let canMove: Bool
    let canRemove: Bool
    let canRetry: Bool
    let alternativeMinutes: Int?
    let club: String
    /// Serientermin beim Rueckfall-Club (Aspria).
    let fallback: Bool
    let partner: String?
    let partnerColor: String?
}

/// Eine Serie: fester Wochentag, erste und spaeteste Anfangszeit.
struct PadelSeries: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    /// „MONDAY“ … - so will ihn der Dienst auch zurueck.
    let weekday: String
    let weekdayLabel: String
    let start: String
    let durationMinutes: Int
    let active: Bool
    let latestStart: String?
    /// Nur dieser Club, `nil` = jeder (Aspria als Rueckfall).
    let club: String?
    let clubs: [String]
    /// Schluessel des Mitspielers - geht beim Aendern unveraendert zurueck.
    let partner: String
    let partnerLabel: String
    /// Erster Tag, solange er noch kommt (yyyy-MM-dd).
    let firstDate: String?
    let partnerColor: String?
    /// Buchungen auf −0,5 bis +0,7 um Felix' Level eingegrenzt (23.10.); `nil` bei einem Dienst von
    /// vorher.
    let levelLimit: Bool?
}

struct PadelCourt: Decodable, Equatable, Identifiable, Sendable {
    let resourceId: String
    let shortName: String
    let name: String
    let doubles: Bool
    /// Platz in Felix' Reihenfolge, -1 = wird nicht versucht.
    let position: Int

    var id: String { resourceId }
}

struct PadelStatus: Decodable, Equatable, Sendable {
    let playtomicLogin: Bool
    let playtomicRefreshUntil: Date?
    let calendar: Bool
    let todo: Bool
    let windowHours: Int
    let armedReleases: Int
    let splitPayment: Bool
}

/// Eine Auswahl wie ein Club: Schluessel und was angezeigt wird.
struct PadelChoice: Decodable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let label: String
}

struct PadelPartner: Decodable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let label: String
    let color: String?
}

/// Ein Padel-Ergebnis von der Uhr und was bei Playtomic damit ist.
struct PadelResult: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let startedAt: Date
    let endedAt: Date
    /// „6:0 6:2“
    let summary: String
    let status: String
    let statusText: String
    let club: String?
    let bookingStart: Date?
    let partner: String?
    let partnerColor: String?
}

/// Was Padel Felix kostet (28.10., `GET /api/costs`, nur Felix): dieser Monat mit Prognose,
/// darunter die Vormonate. Betraege in Euro - was Felix bezahlt hat, stornierte zaehlen nicht.
struct PadelCosts: Decodable, Equatable, Sendable {
    let month: String
    /// „Oktober 2026“
    let label: String
    /// Bisher in diesem Monat.
    let spent: Double
    let matches: Int
    /// Gebucht bis Monatsende.
    let booked: Double
    let bookedMatches: Int
    /// Je geplantem Tag ohne Buchung ein Match zum ueblichen Anteil beim Club.
    let planned: Double
    let plannedDays: Int
    /// Bisher + gebucht + geplant.
    let forecast: Double
    /// Die Vormonate, neueste zuerst.
    let months: [PadelMonthCost]
    /// Die Prognose fuer den Folgemonat (28.10.); fehlt bei einem aelteren Dienst.
    let next: PadelForecast?
}

/// Die Prognose fuer einen kommenden Monat: dort Gebuchtes plus je geplantem Tag ein Match zum
/// ueblichen Anteil - auch Serientage, fuer die es noch keine Termine gibt.
struct PadelForecast: Decodable, Equatable, Sendable {
    let month: String
    /// „November 2026“
    let label: String
    let booked: Double
    let bookedMatches: Int
    let planned: Double
    let plannedDays: Int
    let forecast: Double
}

struct PadelMonthCost: Decodable, Equatable, Identifiable, Sendable {
    let month: String
    let label: String
    let amount: Double
    let matches: Int

    var id: String { month }
}

/// Eine Buchung, live aus Playtomic.
struct PadelBooking: Decodable, Equatable, Identifiable, Sendable {
    let matchId: String
    let date: String
    let weekday: String
    let start: String
    let end: String
    let court: String
    /// „16.88 EUR“ - bei geteilter Zahlung der Anteil je Spieler.
    let price: String?
    let split: Bool
    let isPublic: Bool
    let freeCancellationUntil: Date
    let cancellable: Bool
    let inviteUrl: String
    let occurrenceId: String?
    let publishable: Bool
    let publishBlocker: String?
    /// Auf so viele Minuten verlaengert der Dienst, sobald es geht.
    let extendTo: Int?
    let club: String
    let mergeable: Bool
    let partner: String?
    let location: String?
    let partnerColor: String?

    var id: String { matchId }
}

// MARK: - Anfragen

struct PadelSeriesRequest: Encodable, Equatable, Sendable {
    let weekday: String
    let start: String
    let durationMinutes: Int
    var active: Bool?
    let latestStart: String?
    let club: String?
    let partner: String?
    var from: String?
    /// `nil`: beim Aendern bleibt die Eingrenzung, wie sie ist.
    var levelLimit: Bool?
}

struct PadelSlotRequest: Encodable, Equatable, Sendable {
    let date: String
    let start: String
    let durationMinutes: Int
    var club: String?
    var partner: String?
}

struct PadelSettingsRequest: Encodable, Sendable {
    let courtOrder: [String]
}

// MARK: - Farbe

enum PadelColor {
    /// `#EAB308` → Farbe; `nil` ohne oder bei Unsinn.
    static func color(_ hex: String?) -> Color? {
        guard let hex else { return nil }
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return Color(hex: value)
    }
}
