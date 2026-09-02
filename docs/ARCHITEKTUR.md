# Architektur

## Zielbild (Stufe 2 „Hybrid")

Eine App, drei Tabs. Zwei davon nativ, einer bleibt Web:

| Tab | Umsetzung | Warum |
|---|---|---|
| **Essen** | SwiftUI + Swift Charts auf `/api/food` | Der Tab mit den meisten täglichen Eingaben. Nativ heißt: Schnellerfassung per Siri/Shortcut, Widget mit den Restkalorien, kein Tastatur-Gehampel im Browser |
| **Gewicht** | SwiftUI + Swift Charts auf `/api/weight` | Klein und abgeschlossen — der richtige erste nativer Tab. Später HealthKit-Abgleich |
| **Finanzen** | `WKWebView` auf `finanzen.fherrmann.com` | Hat kein API und soll keins bekommen; das Dashboard wird täglich vom Agenten neu gestaltet |

## Migration: WebView zuerst, dann Tab für Tab ersetzen

Der Aufbau beginnt **nicht** mit sechs Tagen Bauen ohne sichtbares Ergebnis.
Phase 0 stellt alle drei Tabs als WebView hin — damit ist die App ab dem
ersten Tag benutzbar (Stufe 1). Danach wird je Tab die Weboberfläche gegen
eine native ersetzt, einzeln, jeweils lauffähig.

Der Nutzen: jederzeit ein funktionierender Stand, und wenn nach dem
Gewicht-Tab die Luft raus ist, hat man trotzdem eine brauchbare App statt
einer Baustelle.

```
Phase 0   [Web]  [Web]  [Web]     <- benutzbar          erledigt
M1        [Web]  [nativ][Web]     <- benutzbar          erledigt
M2        [nativ][nativ][Web]     <- Zielbild Stufe 2   erledigt
M3        + HealthKit, Widget, Shortcuts, Face-ID-Sperre
```

### Aufbau eines nativen Tabs

Dreiteilig, und in M2 genauso wie in M1:

* **`…API`** — nur Endpunkte, kein Zustand. Duenn genug, um beim Lesen der
  Backend-Doku nebenherzulaufen.
* **`…Store`** (`@MainActor @Observable`) — haelt, was der Tab anzeigt,
  faengt Fehler ab und uebersetzt sie: ein Zugangsproblem ist etwas anderes
  als ein Serverfehler, und nur beim ersten hilft der Hinweis auf den
  Zugang-Tab.
* **View + Datenaufbereitung** — Rechnerei, die mehr ist als Formatieren,
  liegt neben der View statt darin (`WeightChartData`), sonst ist sie nicht
  testbar.

## Ordner

```
Cockpit/            das App-Target
  App/              Einstieg, Tab-Gerüst, AppDelegate
  Core/             Zugang (Cookies), Benachrichtigungen, Palette, Bausteine
  Web/              WKWebView-Einbettung für den Finanzen-Tab
  Weight/           Diagramm, Kacheln, Eingabe, Schritte-Leiste
  Food/             Tagesansicht, Tachos, Gerichte, Schnellerfassung
  Health/           Abgleich mit Apple Health (nur lesend)
  Finance/          WebView plus Face-ID-Sperre
Shared/             was App UND Widget übersetzen
CaloriesWidget/     die Home-Screen-Kachel (eigene Erweiterung)
Tests/              Unit-Tests
UITests/            XCUITest: tippen, wischen, scrollen, Screenshots
project.yml         Quelle des Xcode-Projekts (XcodeGen)
tools/              bootstrap · verify · run-simulator · uitest · install-device · make-icon
docs/               diese Doku
```

⚠️ **Was in `Shared/` liegt, darf nichts benutzen, das es in einer
App-Erweiterung nicht gibt.** `UIApplication.shared` etwa ist dort gesperrt —
deshalb bleibt `Notifications.swift` in `Cockpit/Core/`, und `Palette.swift`
ist geteilt: die Farb-Initialisierer liegen in `Shared/Color+Hex.swift`, der
Rest (mit der `WeightSeries`-Erweiterung) im App-Target.

## Zugang im Client

Beide Token liegen im **Keychain**, eingegeben einmalig über den
Einrichtungs-Bildschirm. Beim Start werden daraus Cookies gebaut und in
**zwei** Speicher gelegt:

- `WKWebsiteDataStore.default().httpCookieStore` — für die WebView-Tabs
- `HTTPCookieStorage.shared` — für die `URLSession` der nativen Tabs

Das erspart das `\/setup?token=…`-Ritual pro Gerät und überlebt einen
App-Neustart. Der Finanzen-Tab bleibt außen vor: dort meldet man sich im
WebView mit Passwort + Einmalcode an, das Session-Cookie hält 7 Tage und
verlängert sich bei Nutzung.

## Was ausserhalb der Oberfläche läuft

Zwei Dinge passieren, ohne dass jemand die App offen hat — und beide brauchen
deshalb einen `AppDelegate` statt einer `.task` an einer View: wird die App im
Hintergrund geweckt, gibt es gar keine Oberfläche.

**HealthKit.** Eine `HKObserverQuery` mit Hintergrundzustellung; iOS weckt die
App, wenn ein neuer Gewichtswert geschrieben wird. Ein Anker merkt sich, was
schon geholt wurde, und wird erst **nach** erfolgreichem Senden gespeichert —
sonst gingen Werte verloren, wenn der Server gerade nicht erreichbar war.

**Das Widget.** Eine eigene Erweiterung, eigener Prozess, eigener Container.
Sie holt sich `/api/food/day` **selbst** und liest das Token aus der geteilten
Keychain-Gruppe — die Vorgabegruppe der App, in der es ohnehin schon liegt.
Cookies der App sieht sie nicht, sie hängt ihren eigenen an die Anfrage. Die
App stößt nach jeder Änderung nur ein Neuzeichnen an; Daten reicht sie keine
weiter.

**Push.** Die Schnellerfassung läuft auf dem Server; der schickt eine
Benachrichtigung, wenn sie fertig ist. Die App meldet ihre Kennung bei jedem
Start neu an (`/api/food/devices`), weil iOS sie gelegentlich austauscht.
Unabhängig davon fragt die App weiter selbst nach, solange sie läuft: die
Benachrichtigung ist ein Zustellweg, keine Voraussetzung.

## Was die App bewusst nicht tut

- **Keine eigene Datenhaltung.** Die Wahrheit steht in `food.json` und
  `weight.json` auf dem Server. Ein lokaler Cache wäre ein zweiter Stand mit
  Konfliktlogik — dafür ist die Datenmenge zu klein und die Verbindung zu gut.
- **Keine Backend-Änderungen.** Wenn ein Endpunkt fehlt, wird er im
  jeweiligen Repo ergänzt und dort deployt, nicht hier umschifft.
