# Arbeitsregeln für `cockpit-ios`

Eine iOS-App, die Felix' Heimserver-Dienste unter einem Icon zusammenführt:
**Kalorienzähler** (`food.fherrmann.com`), **Weight Tracker**
(`weight.fherrmann.com`), **Finance Cockpit** (`finanzen.fherrmann.com`), die
**Notenübersicht** (`fherrmann.com/grades`) und **Habits**
(`fherrmann.com/habits`).

Dieses Repo enthält **nur den Client**. Änderungen an den Diensten gehören in
deren eigene Repos (`../food`, `../weight-app`, `../finance-cockpit`,
`../grades`, `../habits`) — von hier aus wird an ihnen nichts geändert, auch
nicht "mal eben". Habits hat **kein Web-UI**: die App ist sein einziger
Client, und der Dienst liefert alles fertig gerechnet — hier wird keine
Sträh­ne nachgezählt.

⚠️ **Fünf Tabs sind das Maximum.** iOS schiebt den sechsten unter „Mehr".
Deshalb ist Zugang ein Blatt hinter dem Zahnrad (`Router.showsSetup`) und
kein Tab mehr. Ein weiterer Dienst braucht einen Platz, nicht einen Tab.

⚠️ Eine Ausnahme mit Ansage: die Noten haben für diese App eine
**JSON-Schnittstelle bekommen** (`../grades/app/api/`). Gerechnet wird
weiterhin nur dort — die Regel aus PO-I23 § 8 Abs. 2 in Swift nachzubauen
wäre eine zweite Stelle, an der eine Prüfungsordnung stimmen muss.

## Vor dem ersten Handgriff

1. `docs/STAND.md` lesen. Da steht, was fertig ist und was als Nächstes
   dran ist. Das ist der Einstieg, nicht dieses Dokument.
2. `docs/BACKENDS.md` lesen, wenn du an einem der nativen Tabs arbeitest.
   Da stehen Endpunkte, Datentypen und die Fallstricke.
3. `../SERVER-CONTEXT.md` lesen, wenn es um Erreichbarkeit, Domains oder
   Zugang geht — das ist die Referenz für den Server, nicht dieses Repo.

## Doku aktuell halten — im selben Arbeitsgang

Nicht "später", nicht "am Ende der Session": **im selben Arbeitsgang wie die
Änderung.** Eine Doku, die einen Schritt hinterherhinkt, ist schlimmer als
keine — sie wird geglaubt.

| Datei | Wann sie fällig ist |
|---|---|
| `docs/STAND.md` | **Nach jedem Arbeitsschritt.** Erledigtes abhaken, "Nächster Schritt" oben neu setzen. Wer die Session abbricht, hinterlässt hier einen brauchbaren Einstieg für die nächste |
| `docs/ENTSCHEIDUNGEN.md` | Sobald eine Entscheidung fällt, bei der es eine echte Alternative gab. Mit Datum, Begründung **und** der verworfenen Alternative — sonst wird sie in drei Monaten neu diskutiert |
| `docs/BACKENDS.md` | Sobald du merkst, dass ein Endpunkt, ein Feld oder ein Verhalten dort nicht (mehr) stimmt |
| `docs/ARCHITEKTUR.md` | Bei strukturellen Änderungen: neuer Ordner, neue Schicht, Tab wechselt von WebView auf nativ |
| `README.md` | Nur wenn sich Einstieg oder Schnellstart ändert |

⚠️ **Quelle der Wahrheit für `docs/BACKENDS.md` ist der Code der Dienste** —
Java in `../food/src/main/java/…` und `../weight-app/src/main/java/…`, Python
in `../grades/app/`. Bei Widerspruch gilt der Code — Doku korrigieren, nicht
raten. Und nicht aus dem Gedächtnis dokumentieren: die Controller, Records und
Routen wirklich aufmachen.

## Bauen und prüfen

```bash
tools/bootstrap.sh   # einmalig + nach Änderungen an project.yml
tools/verify.sh      # baut fuer den Simulator und laesst die Tests laufen
tools/run-simulator.sh weight bild.png   # mit Zugang starten und aufnehmen
tools/install-device.sh --launch         # aufs iPhone bauen und starten
```

`run-simulator.sh` startet die App im Simulator **mit echten Daten** und legt
auf Wunsch einen Screenshot ab — der einzige Weg, Layoutfehler zu sehen statt
sie sich vorzustellen. Erstes Argument ist der Tab (`food`, `weight`,
`finance`, `grades`, `habits`, `setup`), zweites der Pfad fürs Bild.

Der **Noten-Tab** braucht dafür ein Passwort. Das gehört nicht in den
Schlüsselbund dieses Rechners — es ist Felix' Anmeldung, kein Dienstgeheimnis.
Für einen Blick darauf den Dienst lokal starten und die App umleiten (siehe
Kopf von `run-simulator.sh`, Schalter `COCKPIT_URL_GRADES`).

Die Token dafür stehen im **macOS-Schlüsselbund** unter dem Konto
`cockpit-ios` (Dienste `fh_private` und `weight_app_token`) — nicht im Repo,
nicht in einer Datei. Wie sie dort hinkommen, steht im Kopf des Skripts. Die
App liest sie nur im Debug-Build (`Access.seedFromEnvironment`).

Erscheinungsbild umschalten: `xcrun simctl ui booted appearance dark|light`.
**Beide anschauen**, bevor etwas als fertig gilt.

```bash
tools/uitest.sh                 # alle UI-Tests, Bilder nach build/screenshots/
tools/uitest.sh testSwipeOnAn…  # nur ein Test
```

`uitest.sh` kann, was `simctl` nicht kann: **tippen, wischen, scrollen** — und
legt von jedem Schritt einen Screenshot ab. Drei Dinge, die dabei nicht
offensichtlich sind und je einen halben Anlauf gekostet haben:

* **Erst aufnehmen, dann prüfen.** Schlägt eine Prüfung fehl, endet der Test
  sofort — ohne Bild weiß man nur, *dass* etwas nicht stimmt.
* **`element.swipeUp()` wischt nur innerhalb des Elements.** Bei einer
  Beschriftung sind das dreißig Punkte, zu wenig zum Scrollen. Und
  `app.swipeUp()` setzt in der Bildmitte an — auf dem Diagramm, wo die
  Ziehgeste liegt. Deshalb `scrollDown()` mit Koordinaten.
* **Ein Accessibility-Container ist nie `isHittable`.** Auf ein Kind prüfen,
  nicht auf die Karte selbst.
* **Die Token muessen mit `TEST_RUNNER_` davor exportiert werden.**
  `xcodebuild` reicht nur solche Variablen an den Testlaeufer weiter und
  streicht das Praefix dabei. Ohne das sieht der Test leere Token - und der
  Lauf ist trotzdem gruen, solange im Simulator noch welche vom letzten
  `run-simulator.sh` im Keychain liegen.
* **Was die App sich merkt, ueberlebt den Testlauf.** Die angenommenen Noten
  liegen in den UserDefaults; ein Test, der gegen eine Abschlussnote misst,
  muss sie erst wegraeumen (`clearAssumptions`).

Was der Harness **nicht** kann: Systemdialoge (Health, Face ID) bedienen —
dafür sind die Debug-Schalter da.

Der Simulator allein kann **nicht tippen, wischen oder scrollen**. Alles, was
hinter einer Geste liegt, ist ohne den Harness nicht zu sehen — dafür gibt es
Debug-Schalter, die nur im Debug-Build wirken:

| Schalter | Wofür |
|---|---|
| `COCKPIT_TAB=weight` | mit welchem Tab die App aufmacht (`food`, `weight`, `finance`, `grades`, `habits`); `setup` öffnet das Zugang-Blatt |
| `COCKPIT_RANGE=threeYears` | Zeitraum im Gewicht-Tab (`month`, `last90`, `year`, `threeYears`) |
| `COCKPIT_DAY=2026-08-10` | Tag im Essen-Tab — ein leerer Tag macht die Liste kurz genug, dass mehr ins Bild passt |
| `COCKPIT_SELECT=2026-08-15` | wählt einen Tag im Diagramm vor, damit die Sprechblase im Bild ist |
| `COCKPIT_NO_LOCK=1` | Face-ID-Sperre aus |
| `COCKPIT_FORCE_LOCK=1` | Sperrbildschirm erzwingen (im Simulator ist kein Gesicht hinterlegt) |
| `COCKPIT_NO_PUSH=1` | keine Push-Anmeldung — sonst meldet jeder Testlauf eine Simulator-Kennung beim food-Backend an |
| `COCKPIT_URL_GRADES=http://127.0.0.1:48230/grades` | biegt einen Dienst auf eine andere Adresse um (`COCKPIT_URL_<DIENST>`, auch `_HABITS`) - gegen einen lokal gestarteten Dienst; beim Habits-Dienst wird der Privat-Token dann auch fuer diesen Rechner als Cookie gesetzt |
| `COCKPIT_GRADES_TOKEN`, `_USER`, `_PASSWORD` | Noten-Zugang. Das Passwort landet dabei **ohne** Face-ID-Schutz im Keychain - im Simulator gibt es kein Gesicht, ein geschuetzter Eintrag waere dort nicht mehr zu lesen |
| `COCKPIT_NO_HEALTH=1` | Health-Anbindung aus. Sonst verdeckt der Berechtigungsdialog jeden Screenshot des Gewicht-Tabs, und wegklicken lässt er sich nicht (`simctl privacy` kennt keinen Health-Dienst) |

⚠️ **`#if DEBUG` ist keine Schranke gegen sichtbare Oberfläche.** Auf dem
Gerät läuft ein Debug-Build (`install-device.sh` baut Debug) — ein Tab, ein
Knopf oder eine Zeile hinter `#if DEBUG` steht damit auf Felix' Handy. Debug-
Oberfläche gehört deshalb zusätzlich hinter einen Schalter, der sie nur auf
ausdrückliche Anforderung zeigt (siehe `TabSelection.showsWidgetPreview`).

Jeder dieser Schalter ist entstanden, weil ohne ihn ein Fehler unsichtbar
geblieben wäre. Was weiterhin **nicht** prüfbar ist: Wischgesten, alles
unterhalb des ersten Bildschirms, und ob nach erteilter Health-Erlaubnis
wirklich Werte ankommen.

`install-device.sh` sucht das iPhone selbst. Es muss einmal per Kabel mit
Xcode gekoppelt worden sein (`Window > Devices`, „Connect via network"),
danach reicht dasselbe WLAN. Ist es gesperrt oder nicht im Netz, bricht das
Skript mit einer Erklärung ab statt mit einem Fehlercode.

**Nie behaupten, etwas baue, ohne `tools/verify.sh` gelaufen zu haben.**
Swift-Code, der nur "aussieht wie er kompiliert", ist ungeprüfter Code —
sag das dann auch so.

## Konventionen

- **Xcode-Projekt niemals von Hand.** Die `.xcodeproj` ist erzeugt und steht
  in `.gitignore`; die Quelle ist `project.yml`. Neue Datei = Datei anlegen
  und `tools/bootstrap.sh`, kein Gefummel in einer `pbxproj`. Dasselbe gilt
  für die `.entitlements` und die `Info.plist` der Erweiterung — auch die
  erzeugt XcodeGen.
- **Wohin eine neue Datei gehört.** `Shared/` nur, wenn das **Widget** sie
  braucht — dort ist `UIApplication.shared` gesperrt, und ein Verstoß fällt
  erst beim Bauen der Erweiterung auf. Sonst `Cockpit/<Bereich>/`.
- **Bezeichner englisch, Kommentare deutsch.** Wie im Rest von Felix'
  Projekten. Kommentare erklären das **Warum**, nicht das Was — was der Code
  tut, steht im Code.
- **Keine Tokens im Repo.** Die Zugangstokens liegen im Keychain des Geräts
  und werden einmal über den Einrichtungs-Bildschirm eingegeben. Kein
  Default-Token im Code, auch kein "changeme".
- **Keine Netzwerk-Zugriffe in Tests.** Die Backends sind privat; ein Test,
  der sie braucht, läuft bei niemandem sonst.
- **Committen und pushen.** Wie im Eltern-Ordner: was nicht gepusht ist,
  existiert für den nächsten Rechner nicht.

## Was hier bewusst fehlt

- **Kein zweiter Datenstand.** Ohne Netz zeigt die App den **letzten
  Stand** jeder Abfrage (`OfflineCache`, mit Datum in der Leiste) und legt
  Haken, Messwerte und Essenseinträge in einen **Postausgang** (`Outbox`), der
  beim nächsten Netz rausgeht. Was sie dabei **nicht** tut: nachrechnen.
  Sträh­nen, Tagessummen, Kacheln bleiben Sache der Dienste — bis der Ausgang
  leer ist, steht der alte Stand da und die Leiste sagt, dass etwas wartet.
  Wer offline eine lokale Sträh­nen-Logik einbaut, baut die Regel ein zweites
  Mal. Nur Änderungen, die später genauso gelten (mit Datum im Rumpf oder
  Pfad), dürfen `queueWhenOffline: true` bekommen.
- **Kein Multi-User, keine Registrierung.** Wie in den Backends: eine Person,
  ein Gerät, ein geteiltes Geheimnis.
