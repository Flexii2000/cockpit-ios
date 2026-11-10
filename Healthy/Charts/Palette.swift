import SwiftUI
import UIKit

/// Die Farben der Diagramme.
///
/// Der Dunkelwert ist jeweils der aus der Weboberflaeche - dieselbe Kurve
/// sieht in App und Browser gleich aus. Der Hellwert ist dieselbe Farbe, nur
/// kraeftiger. Aufnahme, Verbrauch, Defizit und Ueberschuss stehen so im
/// Healthy-Vertrag (§5) und gelten auf allen Oberflaechen.
enum Palette {
    static let measured = Color.adaptive(light: 0x0288D1, dark: 0x4FC3F7)
    static let avg7     = Color.adaptive(light: 0x388E3C, dark: 0x81C784)
    static let avg14    = Color.adaptive(light: 0xF57C00, dark: 0xFFB74D)
    static let avg30    = Color.adaptive(light: 0x7B1FA2, dark: 0xBA68C8)
    static let target   = Color.adaptive(light: 0xD32F2F, dark: 0xE57373)
    /// „Distanz z. Target" - Pink (Felix, 19.10.): eigene Farbe statt des
    /// Rots der Zielkurve, damit die Kurve neben ihr nicht als zweite
    /// Zielkurve gelesen wird.
    static let targetDistance = Color.adaptive(light: 0xC2255C, dark: 0xF06595)
    /// Die Aufnahme (kcal). Dunkel mit 85 % wie im Web - das volle Gelb
    /// strahlte dort heller als jede andere Kurve.
    static let kcal     = Color.adaptive(light: 0xD49C00, dark: 0xFFD54F, darkOpacity: 0.85)
    static let vacation = Color.adaptive(light: 0x5C7CFA, dark: 0x7C9CFA)
    /// Ueber dem Ziel - im Verlauf des Kalorienzaehlers.
    static let over     = Color.adaptive(light: 0xD32F2F, dark: 0xEF5350)
    /// „Verbrauch ⌀" - Indigo, auf allen Oberflaechen gleich (Vertrag §5).
    /// Gegen die vorhandenen Reihen auf Farbfehlsicht geprueft: neben dem
    /// Gelb der kcal und dem Blau des Messwerts bleibt es unterscheidbar, und
    /// die Luecke zwischen ihm und „kcal ⌀" ist das Defizit.
    static let expenditure = Color.adaptive(light: 0x4338CA, dark: 0x6E7BFF)
    /// Die Kurven „Defizit ⌀" und „Defizit Tag" samt Nulllinie und Skala.
    /// Orange - weit weg vom Gruen und Blau des Gewichts, neben dem die Kurve
    /// vorgewaehlt steht (das fruehere Petrol lag zu nah daran), und vom
    /// Indigo des Verbrauchs.
    static let deficit = Color.adaptive(light: 0xE8590C, dark: 0xFF922B)
    /// Defizit als Bilanz - ueberall, wo Defizit gegen Ueberschuss steht: Zahl,
    /// Bilanzbalken und Wochenbalken der Energie-Karte, die Flaeche zwischen
    /// „Verbrauch ⌀" und „kcal ⌀" (Felix, 10.11.: gruen = Defizit, rot =
    /// drueber). Die Kurven bleiben Orange: neben „Gewicht ⌀" stuende sonst ein
    /// zweites Gruen.
    static let deficitBalance = Color.adaptive(light: 0x2B8A3E, dark: 0x51CF66)
    /// Ueberschuss - wo mehr gegessen als verbraucht wurde.
    static let surplus = Color.adaptive(light: 0xD33131, dark: 0xEF5350)
    /// Die Flaeche zwischen „Verbrauch ⌀" und „kcal ⌀": hell 16 %, dunkel
    /// 20 % - auf dunklem Grund traegt dieselbe Deckkraft weniger.
    static let deficitFill = Color.adaptive(light: 0x2B8A3E, dark: 0x51CF66,
                                            lightOpacity: 0.16, darkOpacity: 0.2)
    static let surplusFill = Color.adaptive(light: 0xD33131, dark: 0xEF5350,
                                            lightOpacity: 0.16, darkOpacity: 0.2)

    // MARK: - Strain (Vertrag §5, seit 10.11.)

    /// Der Strain: Zahl, Balken und die Linie „Akut“ - zugleich das Band
    /// `MODERATE`. Blau, weit weg vom Gruen und Rot der Energie-Karte direkt
    /// darunter im Dashboard.
    static let strain = Color.adaptive(light: 0x1971C2, dark: 0x4DABF7)
    /// Ueber dem Ziel: der Teil des Balkens hinter der Marke - zugleich das
    /// Band `HIGH`.
    static let strainOver = Color.adaptive(light: 0xE8590C, dark: 0xFF922B)
    /// Die Linie „Gewohnt“ in der Form-Kurve - ein ruhiges Grau neben dem
    /// Blau von „Akut“, in beiden Erscheinungsbildern gut zu sehen.
    static let strainChronic = Color.adaptive(light: 0x868E96, dark: 0xADB5BD)
    /// Band `LIGHT`.
    static let strainLight = Color.adaptive(light: 0x74C0FC, dark: 0x74C0FC)
    /// Band `ALL_OUT`.
    static let strainAllOut = Color.adaptive(light: 0xD33131, dark: 0xEF5350)
    /// Die Flaeche zwischen „Akut“ und „Gewohnt“ in der Form-Kurve: wo Akut
    /// darunter liegt, in der Strain-Farbe, sonst in „über Ziel“ - hell 16 %,
    /// dunkel 20 %, wie die Flaeche der Energie.
    static let strainFill = Color.adaptive(light: 0x1971C2, dark: 0x4DABF7,
                                           lightOpacity: 0.16, darkOpacity: 0.2)
    static let strainOverFill = Color.adaptive(light: 0xE8590C, dark: 0xFF922B,
                                               lightOpacity: 0.16, darkOpacity: 0.2)

    /// Die Farbe eines Strain-Bands - fuer Punkte, die nur die Stufe zeigen.
    static func strainBand(_ band: StrainBand?) -> Color {
        switch band {
        case .light:    strainLight
        case .moderate: strain
        case .high:     strainOver
        case .allOut:   strainAllOut
        default:        .secondary
        }
    }
}
