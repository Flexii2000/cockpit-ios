# Cockpit

Eine iOS-App, die Felix' drei Heimserver-Dienste unter einem Icon
zusammenführt: **Essen** (Kalorienzähler), **Gewicht** (Weight Tracker) und
**Finanzen** (Finance Cockpit). Bundle-ID `com.fherrmann.cockpit`.

Die Backends bleiben unverändert und laufen weiter im Browser — das hier ist
ein zweiter Client, kein Ersatz.

## Was die App kann

**Essen** — Tagesansicht nach Mahlzeiten mit Teilsumme gegen das jeweilige
Mahlzeitenziel, vier Tachos (kcal plus die drei Makros), Gerichte-Merkliste,
Tagesziele, Verlaufsdiagramm. Die **Schnellerfassung** schickt Freitext an den
Server und blockiert dabei nicht: das Blatt schließt sich sofort, der Vorschlag
meldet sich, wenn er fertig ist — per Push auch dann, wenn das Handy in der
Tasche liegt.

**Gewicht** — Kacheln, ein Diagramm mit Zeitraum-Umschalter (30 Tage bis
3 Jahre), Zielkurve, Zielkorridor, Urlaubs-Bänder und die kcal des jeweiligen
Tages darüber. Darunter die **Schritte von heute** gegen ein Tagesziel.
Gewicht und Schritte kommen **automatisch aus Apple Health**.

**Finanzen** — das Cockpit als WebView, hinter **Face ID**. Beim Verlassen der
App sperrt es wieder zu, und im App-Umschalter liegt eine Decke darüber.

**Widget** — die heute noch übrigen Kalorien auf dem Homescreen, klein
(Tacho und Zahl) oder mittel (zusätzlich die drei Makros).

| | |
|---|---|
| **Aktueller Stand und was offen ist** | [`docs/STAND.md`](docs/STAND.md) |
| **Aufbau** | [`docs/ARCHITEKTUR.md`](docs/ARCHITEKTUR.md) |
| **APIs der Backends** | [`docs/BACKENDS.md`](docs/BACKENDS.md) |
| **Warum es so ist, wie es ist** | [`docs/ENTSCHEIDUNGEN.md`](docs/ENTSCHEIDUNGEN.md) |
| **Arbeitsregeln (auch für Claude)** | [`CLAUDE.md`](CLAUDE.md) |

## Schnellstart

```bash
tools/bootstrap.sh              # erzeugt Cockpit.xcodeproj aus project.yml
tools/verify.sh                 # bauen + Unit-Tests, ohne Xcode-Fenster
tools/install-device.sh --launch  # aufs iPhone bauen, installieren, starten
```

Zum Ansehen im Simulator und zum automatisierten Durchklicken:

```bash
tools/run-simulator.sh weight bild.png   # ein Tab, mit Zugang, als Screenshot
tools/uitest.sh                          # tippt, wischt, scrollt; Bilder in build/screenshots/
```

Aufs iPhone gibt es zwei Wege. **Ohne Xcode-Fenster:**
`tools/install-device.sh --launch` — sucht das gekoppelte Gerät selbst, baut
signiert und installiert. **Mit Xcode:** Projekt öffnen, oben in der Leiste
das iPhone als Ziel wählen, ⌘R.

Gekoppelt wird einmalig per Kabel; hakt man in Xcode unter *Window → Devices
and Simulators* „Connect via network" an, geht es danach drahtlos, solange
Mac und iPhone im selben WLAN sind und der Bildschirm entsperrt ist.

## Voraussetzungen

1. **Xcode** aus dem App Store. Die Command Line Tools allein reichen nicht —
   ohne Xcode gibt es kein iOS-SDK und keinen Simulator. Danach einmal
   `sudo xcode-select -s /Applications/Xcode.app`.
2. **XcodeGen** (`brew install xcodegen`) — holt `tools/bootstrap.sh` bei
   Bedarf selbst.
3. **Apple Developer Program**, aktiv seit dem 01.09.2026 (Team `ZWFV263P59`).
   Das Signaturprofil gilt bis zum **01.09.2027**; einmal
   `tools/install-device.sh` vor diesem Datum erneuert es. HealthKit, Push und
   das Widget hängen an dieser Mitgliedschaft.

## Erste Einrichtung auf einem Gerät

Beim ersten Start fragt die App im Tab **Zugang** zwei Token ab. Sie landen im
Keychain und werden von da an als Cookies gesetzt:

| Token | Wofür | Wo er steht (auf dem Server) |
|---|---|---|
| `fh_private` | Essen-Tab und das Widget (gilt für alles unter `.fherrmann.com`) | `/etc/nginx/conf.d/private-mode.conf` |
| `weight_app_token` | Gewicht-Tab, Schritte | `/etc/health-viz.env` |

Der Finanzen-Tab hat kein Token: dort meldet man sich im WebView mit Passwort
und TOTP-Code an; das Session-Cookie hält sieben Tage und verlängert sich bei
Nutzung.

**Health** fragt beim ersten Öffnen des Gewicht-Tabs nach Erlaubnis für
Gewicht und Schritte. **Benachrichtigungen** fragt die erste Schnellerfassung
ab. Beides lässt sich später in den iOS-Einstellungen ändern.
