# Stand

> **Nächster Schritt:** M3 — HealthKit, Widget, Siri-Kurzbefehl,
> Face-ID-Sperre. Braucht die bezahlte Mitgliedschaft.
>
> Offen aus der Planung: eine Übersicht der **doppelt gepflegten
> Anzeigeregeln** (Toleranzen, BMI-Größe, Tacho-Geometrie) mit ihrer
> Gegenstelle im Web-Quelltext — damit beim Ändern nicht eine der beiden
> Seiten stehenbleibt.
>
> ⚠️ **Terminsache:** das Provisioning-Profil läuft am **8. September 2026,
> 18:41 Uhr** ab (Personal Team). Bis dahin sollte die bezahlte Mitgliedschaft
> stehen — dann `DEVELOPMENT_TEAM` in `project.yml` tauschen und neu
> installieren, sonst startet die App nicht mehr.

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
- [x] **Auf dem iPhone installiert** (iPhone 16 Pro, per `devicectl`).
      Signiert mit dem **Personal Team** `ZWFV263P59` — die Aufnahme ins
      Apple Developer Program lief zu dem Zeitpunkt noch (Apple zeigt bis
      zur Freigabe nur eine Enrollment-ID, noch keine Team-ID).
      ⚠️ **Damit laufen App und Zertifikat nach sieben Tagen ab.** Sobald die
      Mitgliedschaft steht: `DEVELOPMENT_TEAM` in `project.yml` auf die
      Team-ID der bezahlten Mitgliedschaft umstellen, dann gilt ein Jahr.
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

### Nachgereicht auf Zuruf

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

## M3 — was nativ erst möglich macht · offen

- [ ] HealthKit: Gewicht aus Apple Health lesen/schreiben
- [ ] Widget: Restkalorien heute
- [ ] App Intent / Shortcut für die Schnellerfassung („Hey Siri, …")
- [ ] Face-ID-Sperre vor dem Finanzen-Tab

## Offene Fragen

- Apple Developer Program (99 €/Jahr) — ohne läuft die App nach 7 Tagen ab.
- Bundle-ID ist `com.fherrmann.cockpit`. Ändern heißt: neues Profil, App neu
  installieren.
