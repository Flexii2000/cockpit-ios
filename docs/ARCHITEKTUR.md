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
M2        [nativ][nativ][Web]     <- Zielbild Stufe 2   offen
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
Cockpit/
  App/       Einstieg, Tab-Gerüst
  Core/      Keychain, Zugang (Cookies), APIClient, Backend-URLs
  Web/       WKWebView-Einbettung fuer die noch nicht nativen Tabs
  Weight/    nativ: API, Store, Diagramm, Kacheln, Eingabe
  Food/      M2
  Finance/   bleibt duenn: nur der WebView-Tab
project.yml  Quelle des Xcode-Projekts (XcodeGen)
tools/       bootstrap.sh (Projekt erzeugen), verify.sh (bauen + testen)
docs/        diese Doku
```

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

## Was die App bewusst nicht tut

- **Keine eigene Datenhaltung.** Die Wahrheit steht in `food.json` und
  `weight.json` auf dem Server. Ein lokaler Cache wäre ein zweiter Stand mit
  Konfliktlogik — dafür ist die Datenmenge zu klein und die Verbindung zu gut.
- **Keine Backend-Änderungen.** Wenn ein Endpunkt fehlt, wird er im
  jeweiligen Repo ergänzt und dort deployt, nicht hier umschifft.
