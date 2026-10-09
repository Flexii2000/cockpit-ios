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
    /// Defizit: die Kurve „Defizit ⌀", die Zahl und die Balken der
    /// Energie-Karte.
    static let deficit = Color.adaptive(light: 0x0D9488, dark: 0x2DD4BF)
    /// Ueberschuss - wo mehr gegessen als verbraucht wurde.
    static let surplus = Color.adaptive(light: 0xD33131, dark: 0xEF5350)
    /// Die Flaeche zwischen „Verbrauch ⌀" und „kcal ⌀": hell 16 %, dunkel
    /// 20 % - auf dunklem Grund traegt dieselbe Deckkraft weniger.
    static let deficitFill = Color.adaptive(light: 0x0D9488, dark: 0x2DD4BF,
                                            lightOpacity: 0.16, darkOpacity: 0.2)
    static let surplusFill = Color.adaptive(light: 0xD33131, dark: 0xEF5350,
                                            lightOpacity: 0.16, darkOpacity: 0.2)
}
