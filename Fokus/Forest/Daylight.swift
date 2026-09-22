import Foundation

/// Der Sonnenstand ueber Hamburg - fuer Licht, Himmel und Schatten der
/// Insel. Ohne Standortabfrage: Felix' Wald steht dort, wo Felix wohnt, und
/// eine Viertelstunde Abweichung sieht niemand.
///
/// Gerechnet mit der ueblichen Naeherung: Deklination aus dem Tag im Jahr,
/// Stundenwinkel aus der Uhrzeit, ohne Zeitgleichung - die macht hoechstens
/// eine Viertelstunde aus.
enum Daylight {

    enum Phase: Equatable {
        case day, dusk, night
    }

    struct Sun: Equatable {
        /// Hoehe ueber dem Horizont, Bogenmass; negativ = unter dem Horizont.
        let elevation: Double
        /// Richtung, Bogenmass, 0 = Sueden, positiv nach Westen.
        let azimuth: Double

        /// Tag ueber dem Horizont, Daemmerung bis sechs Grad darunter
        /// (buergerliche Daemmerung), danach Nacht.
        var phase: Phase {
            if elevation > 0 { return .day }
            if elevation > -6 * .pi / 180 { return .dusk }
            return .night
        }
    }

    static let hamburgLatitude = 53.55
    static let hamburgLongitude = 9.99

    static func sun(at date: Date = Date(),
                    latitude: Double = hamburgLatitude,
                    longitude: Double = hamburgLongitude) -> Sun {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let dayOfYear = Double(utc.ordinality(of: .day, in: .year, for: date) ?? 172)
        let parts = utc.dateComponents([.hour, .minute], from: date)
        var hours = Double(parts.hour ?? 12) + Double(parts.minute ?? 0) / 60
        #if DEBUG
        // COCKPIT_FOREST_HOUR=21.5 stellt die Uhr der Insel (UTC), fuer Bilder
        // von Daemmerung und Nacht zu jeder Tageszeit.
        if let raw = ProcessInfo.processInfo.environment["COCKPIT_FOREST_HOUR"],
           let forced = Double(raw) {
            hours = forced
        }
        #endif

        let declination = 23.44 * .pi / 180 * sin(2 * .pi * (284 + dayOfYear) / 365)
        let solarHours = hours + longitude / 15
        let hourAngle = (solarHours - 12) * 15 * .pi / 180
        let lat = latitude * .pi / 180
        let elevation = asin(sin(lat) * sin(declination) + cos(lat) * cos(declination) * cos(hourAngle))
        return Sun(elevation: elevation, azimuth: hourAngle)
    }
}
