# Cockpit — Healthy, Vault, Fokus

Drei iOS-Apps aus einem Repo, die Felix' Heimserver-Dienste auf dem iPhone
bedienen:

| App | Tabs | Bundle-ID | Sperre |
|---|---|---|---|
| **Healthy** | Essen (Kalorienzähler), Gewicht (Weight Tracker) | `com.fherrmann.cockpit` | – |
| **Vault** | Noten, Finanzen | `com.fherrmann.vault` | ganze App, Face ID |
| **Fokus** | Habits | `com.fherrmann.fokus` | – |

Die Backends bleiben unverändert und laufen weiter im Browser — das hier sind
Clients, kein Ersatz. Die Token werden **einmal** eingegeben und gelten über
eine geteilte Keychain-Gruppe in allen drei Apps.

## Was die Apps können

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

**Finanzen** — das Cockpit als WebView. In Vault steht die **ganze App**
hinter Face ID: beim Verlassen sperrt sie zu, beim Zurückkommen fragt sie
gleich wieder, und im App-Umschalter liegt eine Decke darüber.

**Noten** — die Abschlussnote nach PO-I23, ECTS-gewichtet mit dreifacher
Thesis, dazu best/average/worst case, alle Module mit ihren Noten und der
Fortschritt. Für offene Module lässt sich eine Note **annehmen**, um zu sehen,
was sie ausmacht. Ebenfalls hinter **Face ID** — und wenn eine neue Note
eingetragen wird, meldet sich das Handy von selbst: „Neue Note 1,7".

**Habits** — Gewohnheiten mit Flamme und Sträh­ne. Aufbauen (abhaken),
Lassen (zählt von selbst, ein Rückfall setzt zurück), Track food (aus dem
Kalorienzähler) und Schritte pro Woche (aus Apple Health, „30/70k", Woche ab
Montag). Heute darf offen sein — die Sträh­ne reißt erst um Mitternacht.

**Zugang** — ein Blatt hinter dem Zahnrad (oben links bei Noten und Habits,
im „…"-Menü bei Essen und Gewicht). Jede App zeigt nur die Abschnitte für
ihre Dienste; gespeichert wird in der geteilten Keychain-Gruppe.

**Ohne Netz** zeigt jeder Tab den letzten Stand — mit Datum in einer Leiste,
damit er nicht wie ein aktueller aussieht. Haken, Messwerte und Essenseinträge
lassen sich trotzdem eintragen: sie warten in einem Postausgang und gehen beim
nächsten Netz raus. Nachgerechnet wird bis dahin nichts.

**Widgets** — die heute noch übrigen Kalorien auf dem Homescreen, klein
(Tacho und Zahl) oder mittel (zusätzlich die drei Makros), und auf dem
**Sperrbildschirm** als Ring neben der Uhr oder als Rechteck mit Balken und
Makros. Dazu die **Habits** auf dem Homescreen, klein (drei) oder mittel
(vier) mit Flamme, Sträh­ne und dem Stand von heute.

| | |
|---|---|
| **Aktueller Stand und was offen ist** | [`docs/STAND.md`](docs/STAND.md) |
| **Aufbau** | [`docs/ARCHITEKTUR.md`](docs/ARCHITEKTUR.md) |
| **Was als Nächstes kommt: drei Apps** | [`docs/PLAN-AUFTEILUNG.md`](docs/PLAN-AUFTEILUNG.md) |
| **APIs der Backends** | [`docs/BACKENDS.md`](docs/BACKENDS.md) |
| **Warum es so ist, wie es ist** | [`docs/ENTSCHEIDUNGEN.md`](docs/ENTSCHEIDUNGEN.md) |
| **Arbeitsregeln (auch für Claude)** | [`CLAUDE.md`](CLAUDE.md) |

## Schnellstart

```bash
tools/bootstrap.sh                        # erzeugt Cockpit.xcodeproj aus project.yml
tools/verify.sh                           # alle drei bauen + Unit-Tests; tools/verify.sh Vault für eine
tools/install-device.sh Healthy --launch  # eine App aufs iPhone; `all` für alle drei
```

Zum Ansehen im Simulator und zum automatisierten Durchklicken — immer mit der
App als erstem Argument:

```bash
tools/run-simulator.sh Healthy weight bild.png   # ein Tab, mit Zugang, als Screenshot
tools/uitest.sh Fokus                            # tippt, wischt, scrollt; Bilder in build/screenshots/
tools/pushtest.sh Vault                          # Benachrichtigung zustellen und antippen
```

Der Noten-Tab braucht dafür ein Passwort und läuft deshalb gegen einen lokal
gestarteten Notendienst statt gegen den Server — wie, steht im Kopf von
`tools/run-simulator.sh`. Ohne diese Angaben überspringen sich seine Tests.

Aufs iPhone gibt es zwei Wege. **Ohne Xcode-Fenster:**
`tools/install-device.sh all --launch` — sucht das gekoppelte Gerät selbst,
baut signiert und installiert alle drei. **Mit Xcode:** Projekt öffnen, oben in der Leiste
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

Beim ersten Start öffnet die App das Blatt **Zugang** (später: Zahnrad) und
fragt nach den Token. Habits braucht keinen eigenen — es nimmt `fh_private`. Sie landen im
Keychain und werden von da an als Cookies gesetzt:

| Token | Wofür | Wo er steht (auf dem Server) |
|---|---|---|
| `fh_private` | Essen-Tab und das Widget (gilt für alles unter `.fherrmann.com`) | `/etc/nginx/conf.d/private-mode.conf` |
| `weight_app_token` | Gewicht-Tab, Schritte | `/etc/health-viz.env` |
| `grades_token` + Benutzer + Passwort | Noten-Tab | `~/services/grades/grades.env` |

Die Noten haben als einziger Dienst **zwei** Schranken: den Geräte-Token und
eine Anmeldung. Beide gibt man einmal ein. Der Token und der Benutzername
liegen wie die übrigen im Keychain, das **Passwort hinter Face ID** — die
Anmeldung selbst passiert danach unsichtbar, sobald die Sitzung nach sieben
Tagen abläuft.

Der Finanzen-Tab hat kein Token: dort meldet man sich im WebView mit Passwort
und TOTP-Code an; das Session-Cookie hält sieben Tage und verlängert sich bei
Nutzung.

**Health** fragt beim ersten Öffnen des Gewicht-Tabs nach Erlaubnis für
Gewicht und Schritte. **Benachrichtigungen** fragt die erste Schnellerfassung
ab. Beides lässt sich später in den iOS-Einstellungen ändern. Meldungen über
neue Noten gibt es erst, **nachdem der Noten-Tab einmal offen war** — die
Kennung des Geräts meldet die App dort erst an, wenn eine Sitzung steht.
