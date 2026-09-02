# Stand

> **Nächster Schritt:** vom M3-Rest sind noch offen: **Widget** mit den
> Restkalorien, **Siri-Kurzbefehl** für die Schnellerfassung, **Face-ID-Sperre**
> vor dem Finanzen-Tab. HealthKit und Push sind fertig.
>
> Offen aus der Planung: eine Übersicht der **doppelt gepflegten
> Anzeigeregeln** (Toleranzen, BMI-Größe, Tacho-Geometrie) mit ihrer
> Gegenstelle im Web-Quelltext — damit beim Ändern nicht eine der beiden
> Seiten stehenbleibt.
>
> **Signatur: erledigt.** Die Mitgliedschaft ist seit dem 01.09.2026 aktiv,
> das Profil gilt bis **01.09.2027**. Nächste Erneuerung: einmal
> `tools/install-device.sh` vor diesem Datum. Verlängerung der Mitgliedschaft
> bei Apple: 02.09.2027, 99 €/Jahr.

## Phase 0 — Gerüst · **fertig** (2026-09-01)

- [x] Repo, Doku, `.gitignore`
- [x] `project.yml` (XcodeGen), `tools/bootstrap.sh`, `tools/verify.sh`
- [x] Tab-Gerüst mit drei WebView-Tabs
- [x] Keychain + Cookie-Injektion (WebView **und** URLSession)
- [x] Einrichtungs-Bildschirm für die beiden Token
- [x] `APIClient` inkl. Datums-Dekodierung für Spring (`LocalDate` + `Instant`)
- [x] Xcode 26.6 eingerichtet, XcodeGen 2.46, `Cockpit.xcodeproj` erzeugt
- [x] **Typprüfung sauber**: der gesamte App-Code gegen das
      iOS-26.5-Simulator-SDK, Swift 6 mit `-strict-concurrency=complete`,
      keine Fehler und keine Warnungen:
      ```
      xcrun --sdk iphonesimulator swiftc -typecheck \
        -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
        -target arm64-apple-ios18.0-simulator \
        -swift-version 6 -strict-concurrency=complete Cockpit/**/*.swift
      ```
      Das ist der Ersatzbeleg, solange die Runtime fehlt — es ersetzt
      `tools/verify.sh` **nicht**: gelinkt wurde nichts, und die Tests in
      `Tests/` sind damit nicht abgedeckt (`@testable import` braucht das
      gebaute Modul).
- [x] **`tools/verify.sh` grün**: Build plus 6 Tests im Simulator
      (iPhone 17, iOS 26.5), `** TEST SUCCEEDED **`
- [x] **Startet auch wirklich**: im Simulator installiert und gestartet, die
      App zeigt die vier Tabs und springt ohne hinterlegte Token von selbst
      in den Zugang-Bildschirm
- [x] **Auf dem iPhone installiert** (iPhone 16 Pro, per `devicectl`),
      Team `ZWFV263P59`, Profil gültig bis 01.09.2027.

      ⚠️ **Merkposten für das nächste Mal:** bei einer Aufnahme als
      **Einzelperson bleibt die Team-ID dieselbe** — es kommt kein zweites
      Team dazu, das bestehende wird aufgewertet. Xcode zeigt den Eintrag
      trotzdem weiter als „(Personal Team)" an. Woran man es also erkennt,
      ist **nicht** eine neue ID, sondern die Gültigkeit des Profils:
      sieben Tage heißt kostenlos, ein Jahr heißt bezahlt.

      ⚠️ **`xcodebuild` kann kein Profil neu anfordern, solange Xcode.app
      nicht angemeldet ist** („No Accounts: Add a new account in Accounts
      settings"). Vorherige Builds liefen nur über den Zwischenspeicher in
      `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`. Wer den
      löscht, ohne dass die Anmeldung sitzt, kann nicht mehr aufs Gerät
      bauen.
- [ ] Erststart auf dem Gerät: das Entwicklerprofil muss am iPhone unter
      *Einstellungen → Allgemein → VPN & Geräteverwaltung* einmal als
      vertrauenswürdig bestätigt werden. Ohne das verweigert iOS den Start
      (`FBSOpenApplicationServiceErrorDomain error 1`) — nicht
      automatisierbar, das ist so gewollt

Zwei Fallen dabei, beide behoben:

* `GENERATE_INFOPLIST_FILE` gehört auf **Projektebene**. Stand es nur beim
  App-Target, scheiterte das Test-Bundle am Signieren — mit einer Meldung,
  die nach einem Fehler im App-Target aussah.
* `tools/verify.sh` erzeugte das Projekt nur, **wenn es fehlte**. Eine
  Änderung an `project.yml` kam so nie an, und man sucht den Fehler im Code
  statt im Projektstand. Es erzeugt jetzt immer neu.

## M1 — Gewicht nativ · **fertig** (2026-09-01)

- [x] Modelle `WeightPoint`, `WeightSummary`, `Vacation`, `DashboardConfig`
- [x] `WeightAPI` — alle Endpunkte des Weight Trackers
- [x] Verlaufsdiagramm mit Swift Charts: Messwerte, 7-Tage-Mittel, Zielkurve,
      Zielkorridor als Band, Urlaube als Hintergrundfläche
- [x] Unvollständige Mittel gepunktet — Logik in `WeightChartData`, damit sie
      testbar ist, mit fünf Tests
- [x] Gewicht eintragen (Blatt mit Datum + Dezimalfeld), Ziel ändern
- [x] Alle 18 Kacheln der Web-Registry, Zusätze über `/api/dashboard`
      hinzufügbar und per Kontextmenü entfernbar
- [x] **App-Icon** — erzeugt von `tools/make-icon.swift`
- [x] Fehlerbanner, das ein Zugangsproblem von einem sonstigen Fehler
      unterscheidet
- [x] 21 Tests grün

## M2 — Essen nativ · **fertig** (2026-09-01)

- [x] Modelle für alle Endpunkte des Kalorienzählers
- [x] Tagesansicht nach Mahlzeiten, mit Teilsumme gegen das Mahlzeitenziel;
      Wischen löscht einen Eintrag
- [x] Tag vor/zurück, Tag wählen, „Heute"; vorwärts nur bis heute
- [x] Tachos: drei Makros (Eiweiß als Mindestwert, Fett und Kohlenhydrate als
      Obergrenzen) plus kcal-Tacho mit Restanzeige, Zielmarke bei 1/1,25
- [x] Gerichte-Merkliste: anlegen, ändern, löschen, Portions-Knöpfe
- [x] Tagesziele samt Aufteilung auf die Mahlzeiten
- [x] Schnellerfassung: Auftrag, Nachfragen im Zwei-Sekunden-Takt, Vorschau
      mit Herkunft je Wert, alles korrigierbar vor dem Übernehmen
- [x] Verlaufsdiagramm: kcal als Säulen, Zielline, Gewichtskurve darüber
- [x] 30 Tests grün

### Am echten Datenbestand nachgezogen (2026-09-01)

Die Oberfläche ließ sich zunächst nur blind bauen — im Simulator lagen keine
Token. Mit `tools/run-simulator.sh` ist das erledigt, und beim ersten Blick
fielen drei Dinge auf, die kein Test gefunden hätte:

* **Die y-Achse der Gewichtskurve lief von 0 bis 100.** Ein `RectangleMark`
  ohne y-Grenzen (die Urlaubsbänder) zieht den Bereich bis zur Null herunter;
  die Kurve saß als flacher Strich im obersten Zehntel. Jetzt steht der
  Bereich explizit und rechnet den Zielkorridor mit ein.
* **Ein Urlaub, der in die Zukunft reicht, dehnte die x-Achse.** „Uniblock"
  läuft bis 2. Oktober — rechts stand ein Fünftel des Diagramms leer. Die
  Bänder werden jetzt auf den Datenbereich zugeschnitten, wie im Web.
* **Die letzte Achsenbeschriftung war abgeschnitten** („1...."), behoben mit
  `AxisMarks(preset: .aligned)`.

### Drei Fehler im Verlauf des Kalorienzählers (gemeldet, behoben)

„1. September ist 2× da", „man kann den Zeitraum nicht ändern", „nur zwei
Datenpunkte für Gewicht" — drei Meldungen, **eine** Ursache: das Diagramm
leitete seinen Zeitbereich aus den vorhandenen Daten ab statt aus dem
gewählten Zeitraum. Behoben über `.chartXScale` mit dem Fenster aus dem Store.

Die Rechnerei liegt jetzt in `FoodChartData` neben der View — mit elf Tests,
die genau diese drei Fälle festhalten. **Angesehen habe ich das Diagramm
nicht:** es liegt in der Liste unterhalb des Bildschirms, und `simctl` kann
nicht scrollen (ein leerer Tag und die kleinste Systemschrift reichten nicht).
Geprüft ist die Logik, nicht das Bild.

### Was der Harness sofort gefunden hat

Beim ersten Lauf war die Schritte-Karte auf dem Bild angeschnitten, obwohl der
Test grün war — `exists` gilt auch für Elemente außerhalb des Bildes. Danach
drei Fehlversuche, alle **im Test**, nicht in der App:

* ein Accessibility-Container ist nie `isHittable` — auf ein Kind prüfen
* `element.swipeUp()` wischt nur innerhalb des Elements (dreißig Punkte)
* `app.swipeUp()` setzt in der Bildmitte an, also auf dem Diagramm, wo die
  Ziehgeste liegt und den Wisch verbraucht

Die App war die ganze Zeit in Ordnung. Ohne Bild hätte man das nicht
auseinanderhalten können — genau dafür ist der Harness da.

⚠️ Geblieben ist eine echte Einschränkung: **wer den Finger auf dem Diagramm
aufsetzt, scrollt nicht, sondern liest Werte ab.** Abgemildert dadurch, dass
nur waagerechte Bewegungen als Ablesen zählen; senkrechte gehören der Liste.

### Nachgereicht auf Zuruf

* **Werte ablesen durch Antippen und Ziehen** — in beiden Diagrammen, wie im
  Browser. Zeigt alle sichtbaren Reihen für den Tag unter dem Finger.
  **Ohne den Schleier** über dem Mittelungsfenster, den die Weboberfläche hat:
  dort führt ein Mauszeiger, hier verdeckt der Finger die Stelle ohnehin.
  ⚠️ Die Geste selbst ist **nicht geprüft** — der Simulator kann nicht ziehen.
  Geprüft sind die Zuordnung (`ChartSelection`, vier Tests) und das Aussehen
  der Sprechblase über `COCKPIT_SELECT`.

* **Der Essen-Tab geht in die Zukunft.** Der Vorwärtspfeil war an „heute"
  gesperrt — meine Annahme, nicht Felix'. Mahlzeiten vorplanen ist ein guter
  Grund, und das Backend nimmt Einträge mit beliebigem Datum an (`today()`
  steht dort nur als Vorgabe, wenn keins mitkommt). Benachbarte Tage heißen
  jetzt „Gestern"/„Morgen" statt eines Datums.

* **Schnellerfassung blockiert nicht mehr.** Abschicken schließt das Blatt,
  der Auftrag läuft im Store weiter, eine Zeile in der Tagesliste zeigt ihn an,
  der fertige Vorschlag geht von selbst auf. Ist die App nicht im Bild, kommt
  eine lokale Benachrichtigung. Läuft beim Beenden noch etwas, wird es beim
  nächsten Start wieder aufgenommen.
  ⚠️ Bei gesperrtem Handy friert iOS die App nach ~30 s ein — die Meldung
  kommt dann erst beim Öffnen. Echtes Push wäre ein APNs-Dienst im
  food-Backend.

* **Wischen löscht ohne Wort** — nur noch die Mülltonne. `onDelete` schreibt
  „Löschen" aus; jetzt eine eigene Wischaktion mit `labelStyle(.iconOnly)`,
  der Titel bleibt am Label für VoiceOver.
* **Gewicht im Essen-Verlauf ist zuschaltbar**, standardmäßig aus — und zwar
  getrennt nach **Mittel** und **Tageswerten**. Zwei Serien, kein Rückfall
  aufeinander: sonst zeigte „täglich" an Tagen ohne Messung heimlich das
  Mittel.

* **kcal im Gewicht-Tab** — die Kurve fehlte ganz, obwohl die Weboberfläche
  sie zeigt. Sie ist jetzt da, umschaltbar, mit eigener Achse rechts.
* **Kurve statt Säulen** im Verlauf des Kalorienzählers.

⚠️ Beim Prüfen fiel auf: der Kalorienzähler hat erst **zwei Tage Daten**
(31.08. und 01.09.). Die kcal-Kurve ist deshalb derzeit ein kurzer Strich —
das ist kein Fehler, sondern der Datenbestand.

### Hell und Dunkel

Beides geprüft. Chrome, Karten und Listen folgen dem System von selbst; die
Diagrammfarben stammen aus den dunklen Weboberflächen und waren auf Weiß zu
blass — sie sind jetzt modusabhängig (`Palette.adaptive`), im Dunkeln
unverändert wie im Browser, im Hellen die kräftigere Stufe derselben Farbe.

**Nicht übernommen aus der Weboberfläche:** der Hover-Schleier der Diagramme
(auf einem Touchgerät gibt es kein Hover) und die Umschalter je Serie im
kcal-Verlauf (dort sind es nur zwei Serien).

## M3 — was nativ erst möglich macht · **teilweise fertig** (2026-09-02)

- [x] **HealthKit** — Gewicht aus Apple Health kommt von selbst an. Beobachtung
      mit Hintergrundzustellung plus Abgleich beim Öffnen; ein Wert je Tag, die
      früheste Messung; vorhandene Tage werden nicht überschrieben.
      **Nur lesend** — der Rückweg (App → Health) ist offen und bräuchte einen
      Filter auf die eigene Quelle, sonst liefe der Wert im Kreis.
- [x] **Push** — der Server meldet, wenn eine Schnellerfassung fertig ist.
      APNs ohne Bibliothek im food-Backend, Gerätekennungen in
      `data/devices.json`.
- [x] **Widget** — Restkalorien heute, klein (Tacho + Zahl) und mittel
      (zusätzlich die drei Makros). Holt sich `/api/food/day` selbst.
- [x] **Face-ID-Sperre** vor dem Finanzen-Tab, samt Sichtschutz im
      App-Umschalter.
- [x] **Schritte** aus Health, unter dem Diagramm, mit änderbarem Tagesziel;
      gespeichert im Weight Tracker (`/api/steps`).
- [x] **UI-Test-Harness** (`tools/uitest.sh`) — tippt, wischt, scrollt und
      legt Screenshots ab.
- [ ] App Intent / Shortcut für die Schnellerfassung („Hey Siri, …")

### Der erste Health-Abgleich, und was er ausgelöst hat

Der erste Lauf hat **265 Messwerte zurück bis 2018** eingespielt — die
komplette Health-Historie. Felix' eigene 93 Tage seit dem 01.06.2026 blieben
unangetastet (nachgeprüft: kein einziger davon trägt Health-typische
Fließkomma-Artefakte). Drei Folgen, alle behoben:

* **Der Zielkorridor galt plötzlich als erreicht** — ein Wert vom 25.01.2022
  lag unter 83,5 kg. Die y-Achse streckte sich bis 80, um ein Band
  unterzubringen, das über das laufende Vorhaben nichts aussagt.
  `corridorReachedOn` betrachtet jetzt nur Einträge ab `recordingStart`.
* **Die Historie war unsichtbar** — alle Reihen begannen bei `recordingStart`.
  Sie beginnen jetzt beim frühesten Messwert; die Zielkurve bleibt davor leer.
* **Die x-Achse zeigte viermal „1. Jan"** ohne Jahreszahl. Das Format richtet
  sich jetzt nach der Spanne.

⚠️ **Der erste Abgleich holt weiterhin alles** (so entschieden). Nach einer
Neuinstallation sind die Alt-Werte also wieder da — folgenlos, seit vorhandene
Tage geschont werden.

## Offene Fragen

- Apple Developer Program (99 €/Jahr) — ohne läuft die App nach 7 Tagen ab.
- Bundle-ID ist `com.fherrmann.cockpit`. Ändern heißt: neues Profil, App neu
  installieren.
