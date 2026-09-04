# Stand

> **Nächster Schritt:** Felix' Abnahme im Gebrauch — To-Do in Fokus und im
> Browser, Erinnerungen (die erste in der App angelegte holt die
> Push-Erlaubnis und meldet das Gerät beim Dienst an; vorher gibt es kein
> `devices.json`), die drei Apps insgesamt. Dann Schritt 2 aus
> `PLAN-AUFTEILUNG.md` (aufräumen) und die Roadmap als Projektliste im
> To-Do-Dienst.

## To-Do · **ausgerollt** (2026-09-04, abends)

`todo.service` läuft, `fherrmann.com/todo` antwortet mit Cookie (ohne: 302),
die Karte auf der Landing Page steht. Fokus liegt mit dem To-Do-Tab und
Push-Berechtigung auf dem Gerät — diesmal **ohne** Xcode-Umweg: seit das
Apple-Konto in Xcode angemeldet ist, legt `xcodebuild` die App-ID mit Push
selbst an. Die Stunde davor mit Vault war also die Anmeldung, nicht die
Kommandozeile.

## Nachgebessert auf Zuruf (2026-09-04, abends)

* **To-Do:** Tastatur schließt nach dem Eintragen; Unteraufgaben jetzt an drei
  Stellen (Wischen nach rechts, langes Drücken, und im Blatt hinter der
  Zeile); der Pfeil rechts an jeder Zeile führt zu Fälligkeit, Erinnerungen
  und Unteraufgaben — vorher fand das niemand.
* **Gewicht:** Diagramm 340 statt 260 Punkte hoch; keine senkrechten
  Gitterlinien mehr, waagerechte nur angedeutet; Urlaubsbänder leiser, die
  Beschriftung als kleine Pille im Band statt frei darüber.
* **Ablesen im Diagramm:** gedrückt halten (0,2 s), dann ziehen — jede
  Richtung. Vorher las nur eine waagerechte Ziehgeste ab, und die war
  launisch: schräg wurde ignoriert, zu gerade hielt die Liste fest. Ein
  leises Ticken je Tag bestätigt das Lesen; Tippen lässt den Wert stehen.

## To-Do: Fälligkeit und Erinnerungen · **gebaut** (2026-09-04)

Je Aufgabe eine Fälligkeit (rot, wenn überfällig) und beliebig viele
Erinnerungen — im Browser im Detailfeld unter der Aufgabe (Klick auf den
Text), in der App im Blatt hinter der Zeile. **Die Erinnerungen schickt der
Dienst** als Push an Fokus, damit sie auch kommen, wenn sie im Browser
angelegt wurden und die App zu ist. Dafür hat Fokus jetzt Push: wie bei Vault
braucht die neue Bundle-ID **einmal Xcode** (Schema Fokus, ⌘R), sonst fehlt
dem Profil `aps-environment`. Der Hinweis „verschwindet am …" ist raus.

## To-Do in Fokus · **gebaut, Dienst nicht ausgerollt** (2026-09-04)

Zweiter Tab in Fokus: die Bereiche als **Seiten zum Wischen** (Punkte unten),
je Seite die Aufgaben mit Unteraufgaben (eine Ebene, eingerückt), Eingabe am
Ende, Unteraufgabe per Wischen nach rechts, Löschen nach links. Erledigtes
durchgestrichen mit „verschwindet am …"; Abhaken darf offline warten. Bereiche
anlegen, umbenennen, löschen und „ältere erledigte zeigen" im „…"-Menü.
Der Dienst (`../todo`, Spring wie Habits) hat daneben eine Weboberfläche mit
Kacheln nebeneinander — geprüft im Simulator gegen einen lokal gestarteten
Dienst und im Browser (Cookie-Trick: ein Cookie gilt je Host, nicht je Port,
eine Hilfsseite auf 48211 setzt ihn für 48210).

Entscheidung „Seiten statt Segmente": drei kurze Namen passen in ein
Segment, der vierte nicht mehr — und Bereiche sollen sich anlegen lassen.

## Aufteilung in drei Apps · **Schritt 1 fertig, auf dem Gerät** (2026-09-04)

`Healthy` (Essen, Gewicht; behält `com.fherrmann.cockpit`), `Vault` (Noten,
Finanzen; eine Sperre vor der ganzen App), `Fokus` (Habits). Ein Repo, drei
App-Targets, zwei Widget-Erweiterungen, drei UI-Test-Bundles mit gemeinsamem
Harness; `Core/` für das, was alle Apps brauchen. Die Token liegen in einer
geteilten Keychain-Gruppe; Healthy holt die vorhandenen beim ersten Start
hinüber. Jedes Skript nimmt die App als erstes Argument.

Geprüft: `verify.sh` baut alle drei, Unit-Tests grün; alle drei im Simulator
angesehen (Fokus mit echten Daten über die geteilte Gruppe, Vault öffnet ohne
Noten-Zugang das Blatt mit nur dem Noten-Abschnitt). Auf dem Server:
`grades.env` schickt an `com.fherrmann.vault`; die alte Kennung in
`devices.json` räumt die Notenwache beim ersten Versand selbst weg.

Icons: drei Motive statt drei Farben — Herz mit Pulslinie (Healthy),
Vorhängeschloss (Vault), Zielscheibe (Fokus); `tools/make-icon.swift
<app> <pfad>` zeichnet sie.

Abweichung vom Plan: die Diagramm-Bausteine (`ChartCallout`, `DaySeries`,
`SeriesChip`, `Palette`) liegen in `Healthy/Charts/`, nicht in `Core/` — sie
kennen Typen, die nur Healthy hat, und Vault brach daran.

## Vier neue Kacheln · **fertig** (2026-09-03)

Kalorien auf dem Sperrbildschirm als Ring (`accessoryCircular`, Rest in der
Mitte) und Rechteck (`accessoryRectangular`, Rest, Balken, Makros). Habits auf
dem Homebildschirm klein (drei Zeilen) und mittel (vier): Flamme, Sträh­ne,
Name, rechts Haken oder „30/70k". Ein Tipp führt über `widgetURL` in den
Habits-Tab. Die Habits-Kachel holt ihre Liste selbst und bekommt ohne Netz die
letzte Antwort aus dem Cache der Erweiterung — mit Datum. Angesehen im
Vorschau-Tab (`COCKPIT_TAB=widget`).

## Absturz beim Antippen einer Benachrichtigung · **behoben** (2026-09-03)

Felix' Fund: die Meldung der Schnellerfassung kam an, ein Tipp darauf
beendete die App. Reproduziert mit `tools/pushtest.sh` (`simctl push` plus
UI-Test, der die Meldung antippt): die `async`-Fassung von
`userNotificationCenter(_:didReceive:)` lief als `nonisolated` auf einem
Hintergrund-Executor, UIKit brach in der Fertig-Meldung mit einer Assertion
ab. Jetzt Completion-Handler; beide Nutzlasten (Kalorienzähler, Noten)
laufen durch, der Noten-Tipp landet auf dem Noten-Tab.

## Offline · **fertig** (2026-09-03)

Ohne Netz zeigt jeder native Tab den letzten Stand mit Datum in einer Leiste;
Haken, Messwerte und Essenseinträge warten in einem Postausgang und gehen beim
nächsten Netz raus. Nachgerechnet wird nichts — siehe `docs/ENTSCHEIDUNGEN.md`.
Zwei Unit-Tests fahren beides gegen einen toten Port; im Simulator gegen einen
lokal gestarteten und dann getöteten Dienst angesehen.

## Habits — fünfter Tab · **fertig** (2026-09-02)

Ausgerollt am 02.09.2026 15:27: `habits.service` läuft, nginx reicht
`/habits/` durch, und über `https://fherrmann.com/habits/api/habits` kommen
mit Cookie die drei Habits mit echten Daten aus beiden Quellen — ohne Cookie
die 302 des Privat-Gates.

Gewohnheiten mit Flamme und Sträh­ne, wie bei Snapchat. Vier Arten: Build
(abhaken), Quit (zählt von selbst, Rückfall setzt zurück), Track food (aus dem
Kalorienzähler: 80 % des kcal-Ziels oder drei Mahlzeiten) und Schritte pro
Woche (aus dem Weight Tracker, „30/70k", Woche ab Montag 0:00). Eigenes
Spring-Backend in `../habits`, **ohne Web-UI** — die App ist der einzige
Client und rechnet nichts nach.

Der sechste Tab war einer zu viel: **Zugang ist jetzt ein Blatt** hinter dem
Zahnrad (Noten und Habits in der Leiste, Essen und Gewicht im „…"-Menü).

Geprüft gegen einen lokal gestarteten Dienst mit den echten Quellen: Track
food stand bei 2 Tagen und 979/1.840 kcal, die Schritte bei 5 Wochen und
30/70k. UI-Test hakt Logbook ab und wieder los. Hell und dunkel angesehen.

## Noten — vierter Tab · **fertig** (2026-09-02)

Die Funktionalität von `fherrmann.com/grades`, nativ: Abschlussnote nach
PO-I23 (ECTS-gewichtet, Thesis dreifach), best/average/worst case, alle Module
mit ihren Noten, Fortschritt, die drei geratenen Zuordnungen mit ihrem
Notenchecker-Namen, und für offene Module eine **angenommene** Note. Hinter
Face ID wie die Finanzen — zwei Sperren, damit der eine Tab nicht den anderen
mit aufmacht.

**Gerechnet wird weiterhin nur auf dem Server.** Der Dienst hat dafür eine
JSON-Schnittstelle bekommen (`/grades/api/…`, siehe `docs/BACKENDS.md`); die
Zugangsprüfungen werden in den Blueprint hineingereicht, statt dort nachgebaut
zu werden.

**Push bei neuer Note:** ein Wächter im Notendienst vergleicht alle fünf
Minuten den Notenchecker-Snapshot mit dem zuletzt gesehenen Stand und schickt
„Neue Note 1,7" mit Fach und neuer Abschlussnote. Eigener APNs-Versand, nicht
über das food-Backend — Felix' Entscheidung, Begründung in
`docs/ENTSCHEIDUNGEN.md`.

Anders als im Web steht die Abschlussnote **oben**: im Browser ist sie die
Summenzeile unter der Tabelle, auf dem Handy wäre sie damit einen Bildschirm
tief.

### Was der Bau nebenbei aufgedeckt hat

* **Der UI-Harness lief auf Resten.** Er reichte seine Token ohne
  `TEST_RUNNER_`-Präfix weiter; `xcodebuild` streicht alles andere. Der
  Testläufer sah leere Token, und grün war es nur, weil im Simulator noch
  welche vom letzten `run-simulator.sh` im Keychain lagen.
* **Ein Zeitfenster ohne Cookie.** `applyCookies()` verschränkte das Setzen im
  gemeinsamen Speicher mit dem `await` für WebKit. Der Noten-Tab fragt beim
  Erscheinen — und war schneller als sein eigenes Cookie.
* **`scrollUp` in der Navigationsleiste zieht nichts.** Der Test sah aus, als
  wäre er unten hängengeblieben; war er auch.

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

## M3 — was nativ erst möglich macht · **fast fertig** (2026-09-02)

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

### Nachgereicht am 2026-09-02

* **Schritte als Leiste statt Tacho** — 👟 mit `3.969/10.000` und einem
  Balken darunter. Der Tacho beantwortet „drüber oder drunter" und hat dafür
  eine Zielkerbe; Schritte sind ein Mindestwert, da geht es um „wie weit".
  Über dem Ziel bleibt der Balken voll statt aus dem Rahmen zu laufen.
* **Alle Kacheln entfern- und hinzufügbar**, auch die vier früher festen, auch
  alle auf einmal. Dafür speichert `/api/dashboard` seit Version 1 die
  **vollständige** Liste statt nur der Zusätze — siehe `docs/BACKENDS.md`.
* **Der Kachel-Vorschau-Tab steht nur noch auf Anforderung** in der Leiste.
  `#if DEBUG` allein war keine Schranke: auf dem Gerät läuft ein Debug-Build.

⚠️ **Reihenfolge bei diesem Deploy:** erst das weight-app-Backend, dann die
App. Andersherum liest die App die gespeicherte Liste als vollständig, während
der Server noch die alte Bedeutung liefert — und es stehen vier Kacheln
weniger da.

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
