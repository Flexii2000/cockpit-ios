# Arbeitsregeln für `cockpit-ios`

Fünf iOS-Apps aus einem Repo, die Felix' Heimserver-Dienste bedienen:
**Healthy** (Kalorienzähler `food.fherrmann.com`, Weight Tracker
`weight.fherrmann.com`, Einkaufsliste `fherrmann.com/shopping-list`),
**Vault** (Notenübersicht `fherrmann.com/grades`, Finance Cockpit
`finanzen.fherrmann.com`), **Fokus** (To-Do `fherrmann.com/todo`, Wald —
Fokus-Sessions beim Habits-Dienst), **Einkaufsliste** (nur die Einkaufsliste — für das Handy
von Joana, deren Token nur diesen einen Dienst öffnet) und **coHabit**
(Habits gemeinsam mit Freunden, `fherrmann.com/cohabit` — der frühere
Habits-Dienst; eigener Token je Person, eigene Kacheln).

Dieses Repo enthält **nur die Clients**. Änderungen an den Diensten gehören in
deren eigene Repos (`../food`, `../weight-app`, `../finance-cockpit`,
`../grades`, `../habits`, `../todo`, `../shopping`) — von hier aus wird an
ihnen nichts geändert, auch nicht "mal eben". Gerechnet wird in den Diensten (Sträh­nen, Abschlussnote,
Tagessummen); die Apps zeigen.

⚠️ **Wohin eine Datei gehört, entscheidet, wer sie übersetzt:**

| Ordner | übersetzt von | darf |
|---|---|---|
| `Shared/` | alle Apps **und** beide Erweiterungen | nichts, das es in einer Erweiterung nicht gibt (`UIApplication.shared`) |
| `Core/` | alle fünf Apps (coHabit nimmt daraus nur `Notifications` und `FlowLayout`; Netz, Fehler- und Offline-Leisten hat es eigene) | nichts, das nur eine App kennt (Diagramm-Typen, Tab-Namen) |
| `Shopping/` | Healthy **und** Einkaufsliste | der Einkaufs-Tab samt Store — Typen mit `Shopping`-Präfix, weil Healthy schon ein `DishEditSheet` hat |
| `Healthy/`, `Vault/`, `Fokus/`, `Einkaufsliste/` | genau diese App | alles |
| `FocusShared/` | Fokus, `FokusMonitor` **und** `FokusWidget` | laufende Session, Tagesstand, erlaubte Apps, die Schild-Regel — was Erweiterungen aus der App-Gruppe `group.com.fherrmann.fokus` brauchen (Schild neu legen, Countdown zeigen) |
| `coHabit/` | nur coHabit | alles |
| `CohabitShared/` | coHabit **und** `coHabitWidget` | API-Client mit Bearer, Modelle, Postausgang, App-Gruppe `group.com.fherrmann.cohabit`, App-Intents und die Kachel-Ansichten — nichts, das es in einer Erweiterung nicht gibt |
| `coHabitNotifications/` | nur die Notification Service Extension von coHabit | eine Datei; dazu einzeln (project.yml) `CohabitShared/NotificationImage.swift`, `ImageFormat.swift`, `CohabitToken.swift` und `Shared/Keychain.swift`, `Backend.swift` - **diese drei aus `CohabitShared/` duerfen nichts aus dem Rest von `CohabitShared/` benutzen**, sonst baut die Erweiterung nicht |
| `FokusMonitor/` | nur die DeviceActivity-Erweiterung von Fokus | eine Datei plus `FocusShared/`, kein `Shared/`: legt beim Intervallstart den Schild (neu), nimmt ihn am Ende weg und ersetzt die Ende-Meldung durch „Apps wieder frei", sonst nichts |

Ein Verstoß fällt erst beim Bauen einer **anderen** App auf — deshalb baut
`tools/verify.sh` immer alle fünf. `TabSelection` und `Router` gibt es je App;
sie werden nicht geteilt.

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
| `docs/PLAN-AUFTEILUNG.md` | Solange die Aufteilung in Healthy, Vault und Fokus läuft: Schritte abhaken, Abweichungen vom Plan **dort** festhalten, nicht nur im Code |

⚠️ **Quelle der Wahrheit für `docs/BACKENDS.md` ist der Code der Dienste** —
Java in `../food/src/main/java/…` und `../weight-app/src/main/java/…`, Python
in `../grades/app/`. Bei Widerspruch gilt der Code — Doku korrigieren, nicht
raten. Und nicht aus dem Gedächtnis dokumentieren: die Controller, Records und
Routen wirklich aufmachen.

## Bauen und prüfen

```bash
tools/bootstrap.sh                 # einmalig + nach Änderungen an project.yml
tools/verify.sh                    # baut alle fuenf fuer den Simulator, Unit-Tests in Healthy und coHabit
tools/verify.sh Vault              # nur eine
tools/run-simulator.sh Healthy weight bild.png   # eine App, ein Tab, mit Zugang, als Bild
tools/install-device.sh all --launch             # alle fuenf aufs iPhone (oder eine)
tools/testflight.sh Einkaufsliste                # archivieren + zu TestFlight hochladen (API-Schluessel noetig)
tools/testflight.sh Einkaufsliste --export-only  # nur .ipa bauen
```

Jedes Skript nimmt die App als **erstes** Argument (`Healthy`, `Vault`,
`Fokus`, `Einkaufsliste`, `coHabit`). Tabs: Healthy `dashboard|food|weight|evaluation|shopping|widget|recovery|logbook`
(`recovery` und `logbook` sind das Dashboard samt dieser Seite), Vault
`grades|finance`, Fokus `todo|forest|widget`, Einkaufsliste hat nur die eine Seite,
coHabit `today|timeline|stats|profile|new|widget`;
`setup` öffnet das Zugang-Blatt (nicht in coHabit — dort ist der Zugang ein
eingefügter Link).

**coHabit läuft gegen einen lokal gestarteten Dienst** (Backend-Repo
`../habits`, Demo-Daten laut dessen README): `COCKPIT_URL_COHABIT` und
`COCKPIT_COHABIT_TOKEN` (Token einer Demo-Person) für `run-simulator.sh`, dazu
`COCKPIT_COHABIT_OTHER_TOKEN` (eine zweite Person, die einlädt) für
`uitest.sh coHabit`; `COCKPIT_PHOTO_COHABIT=<id>` lässt
`testCheckInWithSeveralPhotos` in einem bestehenden Co-Habit eintragen statt in
einem eigenen. `COCKPIT_TOUR=1 tools/uitest.sh coHabit
CohabitTourUITests/testTourOfAllScreens` tippt sich durch jeden Bildschirm und
nimmt ihn hell und dunkel auf (`XCUIDevice.shared.appearance`). Die Unit-Tests von coHabit hängen an coHabit als Wirt
(`CohabitTests/`), nicht an Healthy. Der Einkaufs-Token kommt wie die anderen aus
dem Schlüsselbund (`shopping_token`, freiwillig — ohne ihn fehlt der Tab).

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
App liest sie nur im Debug-Build (`Access.seedFromEnvironment`). Gesetzte
`COCKPIT_FH_PRIVATE_TOKEN`/`COCKPIT_WEIGHT_TOKEN` gehen in `run-simulator.sh`
und `uitest.sh` dem Schlüsselbund vor - gegen einen lokalen Dienst gilt dessen
Token (`local-private`), nicht der vom Server. So läuft der Wald-Test, der
wirklich einen Baum von einer Minute pflanzt:
`COCKPIT_URL_HABITS=http://127.0.0.1:<port>/habits COCKPIT_URL_COHABIT=http://127.0.0.1:<port>/cohabit/api COCKPIT_FH_PRIVATE_TOKEN=local-private COCKPIT_WEIGHT_TOKEN=local-weight DEVICE="coHabit Test" tools/uitest.sh Fokus testPlantATreeWithACategory`.

Erscheinungsbild umschalten: `xcrun simctl ui booted appearance dark|light`.
**Beide anschauen**, bevor etwas als fertig gilt.

```bash
tools/uitest.sh Healthy                 # alle UI-Tests einer App, Bilder nach build/screenshots/
tools/uitest.sh Healthy testSwipeOnAn…  # nur ein Test
```

Der Harness (`start`, `scrollDown`, `shoot`, …) liegt in `UITests/Harness.swift`
und ist in allen drei Bundles eingebunden; je App eine Testdatei.
`start()` setzt `COCKPIT_NO_LOCK=1` immer - Vault sperrt die ganze App, und
XCUITest kann kein Gesicht vorzeigen.

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
  muss sie erst wegraeumen (`clearAssumptions`). Ebenso der Schalter
  „Klassische Liste" in coHabit - die coHabit-Tests setzen `COCKPIT_CLASSIC=0`.
* **„Timed out while loading Accessibility"**: der Testlaeufer kommt nicht an
  den Simulator heran, und xcodebuild haengt danach in `simctl diagnose`
  (abbrechen). Ein anderer Simulator hilft - coHabit laeuft im eigenen
  (`DEVICE="coHabit Test" tools/uitest.sh coHabit …`, 30.09.).
* **Ein frisch angelegter Simulator bleibt hell.** `XCUIDevice.shared.appearance
  = .dark` wirkt dort erst, nachdem einmal `xcrun simctl ui "<Geraet>"
  appearance light` lief (vorher meldet `simctl ui … appearance` „unknown“) -
  die „dunkel“-Bilder sind sonst still hell (05.10.).
* **„Busy (Application failed preflight checks)" beim Start des Testwirts**:
  der Simulator wurde von `xcodebuild` kalt gebootet, und SpringBoard ist
  noch nicht so weit. Tritt in `verify.sh` meist bei coHabit auf (nach dem
  Healthy-Lauf); vorher booten hilft: `xcrun simctl boot "iPhone 17 Pro" &&
  xcrun simctl bootstatus "iPhone 17 Pro" -b` - `verify.sh` nimmt das erste
  iPhone der Liste, `uitest.sh` das „iPhone 17" (09.10.).
* **Aufraeumen per `addTeardownBlock`, nicht per `defer`.** Schlaegt eine
  Pruefung fehl, bricht XCTest die Methode ab, ohne `defer` auszufuehren - was
  der Test im Dienst angelegt hat, bliebe liegen.

Was der Harness **nicht** kann: Systemdialoge (Health, Face ID) bedienen —
dafür sind die Debug-Schalter da. Den Benachrichtigungs-Dialog kann er
(Springboard-Alert), und Benachrichtigungen selbst kommen von aussen:

```bash
tools/pushtest.sh Healthy                  # Kalorienzaehler-Meldung zustellen und antippen
tools/pushtest.sh Vault                    # "Neue Note" - muss auf dem Noten-Tab landen
tools/pushtest.sh Vault nutzlast.json      # eigene Nutzlast
```

`simctl push` stellt sie zu, der UI-Test tippt sie an und prueft, dass die
App danach noch laeuft. So wurde der Absturz beim Antippen gefunden: die
`async`-Fassung eines `UNUserNotificationCenterDelegate`-Rueckrufs laeuft als
`nonisolated` auf einem Hintergrund-Executor, und UIKit bricht in der
Fertig-Meldung mit einer Assertion ab. **Delegaten-Rueckrufe, die UIKit
abschliesst, als Completion-Handler schreiben, nicht `async`.**

Der Simulator allein kann **nicht tippen, wischen oder scrollen**. Alles, was
hinter einer Geste liegt, ist ohne den Harness nicht zu sehen — dafür gibt es
Debug-Schalter, die nur im Debug-Build wirken:

| Schalter | Wofür |
|---|---|
| `COCKPIT_TAB=weight` | mit welchem Tab die App aufmacht (`dashboard`, `food`, `weight`, `evaluation`, `finance`, `grades`, `todo`, `forest`; coHabit `timeline`, `stats`, `profile`, `new`); `recovery` und `logbook` öffnen in Healthy das Dashboard samt dieser Seite; `setup` öffnet das Zugang-Blatt; `widget` zeigt die Kacheln mit echten Daten |
| `COCKPIT_EVALUATION_DEMO=1` | füllt den Evaluation-Tab (Healthy) mit einem Jahr erfundener Antworten auf drei Platzhalter-Fragen - nur im Speicher, nie gespeichert. Mit `COCKPIT_NO_LOCK=1` |
| `COCKPIT_EVALUATION_SCRATCH=1` | Evaluation mit einer frischen Datei im Temp-Ordner je Start - für UI-Tests, die Fragen anlegen, ohne etwas liegen zu lassen |
| `COCKPIT_DASHBOARD_DEMO=1` | erfundene Werte in Healthy: Dashboard, Recovery-Seite, Logbook mit Platzhaltern („Verhalten A"), Energie (Zeilen im Essen-Tab, Kacheln und Kurve „Verbrauch ⌀" im Gewicht-Tab) - nur im Speicher, nie gesendet, auch Speichern und Anlegen nicht; keine Logbook-Erinnerung. Der Simulator bekommt keine Health-Daten. Mit `COCKPIT_NO_HEALTH=1` |
| `COCKPIT_RANGE=threeYears` | Zeitraum im Gewicht-Tab (`month`, `last90`, `last180`, `year`, `threeYears`, `allTime`) |
| `COCKPIT_DAY=2026-08-10` | Tag im Essen-Tab — ein leerer Tag macht die Liste kurz genug, dass mehr ins Bild passt |
| `COCKPIT_SELECT=2026-08-15` | wählt einen Tag im Diagramm vor, damit die Sprechblase im Bild ist |
| `COCKPIT_SCAN=4000417025005` | liefert im Essen-Tab sofort diesen Produktcode, als wäre er gescannt worden: das Scanner-Blatt geht auf, gibt ihn ohne Kamera ab, danach öffnet sich das Eintrag-Blatt mit dem Produkt aus Open Food Facts — im Simulator gibt es keine Kamera |
| `COCKPIT_NO_LOCK=1` | Face-ID-Sperre aus |
| `COCKPIT_FORCE_LOCK=1` | Sperrbildschirm erzwingen (im Simulator ist kein Gesicht hinterlegt) |
| `COCKPIT_NO_PUSH=1` | keine Push-Anmeldung — sonst meldet jeder Testlauf eine Simulator-Kennung beim food-Backend an |
| `COCKPIT_ASK_PUSH=1` | fragt trotzdem nach der Benachrichtigungs-Erlaubnis (ohne sie zeigt der Simulator nichts an), meldet aber weiterhin keine Kennung an — fuer `pushtest.sh` |
| `COCKPIT_TODO_AREA=Uni` | öffnet im To-Do-Tab eine bestimmte Seite - wischen kann der Simulator nicht |
| `COCKPIT_NO_SCREENTIME=1` | Wald-Tab ohne Bildschirmzeit: kein Erlaubnis-Dialog, kein Schild, keine DeviceActivity — im Simulator gibt es das alles nicht, und so lässt sich eine Session trotzdem pflanzen |
| `COCKPIT_NO_SHORTCUTS=1` | Wald-Tab ohne den Sprung in die Kurzbefehle-App beim Pflanzen - sonst verlässt die App mitten im UI-Test den Vordergrund |
| `COCKPIT_FOREST_RUNNING=45` | zeigt im Wald-Tab eine laufende Session mit 45 Minuten Rest (ohne Schild, ohne Baum am Ende) |
| `COCKPIT_FOREST_RANGE=month` | stellt den Wald auf einen Ausschnitt (`today`, `week`, `month`, `year`) |
| `COCKPIT_FOREST_HOUR=19.5` | stellt die Uhr der Insel (Stunde in UTC) — Tag, Dämmerung und Nacht folgen sonst dem echten Sonnenstand über Hamburg |
| `COCKPIT_URL_GRADES=http://127.0.0.1:48230/grades` | biegt einen Dienst auf eine andere Adresse um (`COCKPIT_URL_<DIENST>`, auch `_HABITS`, `_COHABIT` = `http://127.0.0.1:48792/cohabit/api`, `_WEIGHT`, `_FOOD`) - gegen einen lokal gestarteten Dienst; der Privat-Token (beim Weight Tracker dessen eigener) wird dann auch fuer diesen Rechner als Cookie gesetzt |
| `COCKPIT_URL_KLIPY=http://127.0.0.1:48793/api/v1` | GIF-Suche in coHabit gegen `tools/klipy-stub.py` statt KLIPY - ohne echten Schluessel (nur auf dem Server) antwortet KLIPY nicht. `uitest.sh` reicht es an `testSendAGifFromTheSearch` weiter |
| `COCKPIT_COHABIT_TOKEN=…` | legt in coHabit den Token einer Person ab, als waere ihr Link eingefuegt worden; `none` nimmt ihn weg (Start ohne Zugang - der Schluesselbund ueberlebt jede Neuinstallation) |
| `COCKPIT_LINK=cohabit://cohabit/<id>/chat` | oeffnet in coHabit beim Start einen Deep Link - `simctl openurl` zeigt bei eigenem Schema einen Dialog, den simctl nicht bestaetigen kann. Wirkt auch ohne Zugang: ein Setup-Link (`cohabit://setup?token=…`) meldet dann an, ein Einladungslink oeffnet die Registrierung |
| `COCKPIT_TODAY_MODE=list` | „Heute" in coHabit als Liste statt Dashboard |
| `COCKPIT_CLASSIC=1` | legt in coHabit den Schalter „Klassische Liste" (Profil) beim Start um: „Heute" zeigt die alte Habit-Liste der Fokus-App; `0` schaltet ihn aus (der Schalter überlebt jeden Start - die UI-Tests setzen deshalb immer `0`, außer sie wollen die Liste) |
| `COCKPIT_TIMELINE_HIDDEN=c-1,c-2` | blendet diese Co-Habits im Timeline-Filter von coHabit beim Start aus, `none` keins; ohne Wert bleibt die gemerkte Auswahl (sie ueberlebt jeden Start) |
| `COCKPIT_STATS_RANGE=week` | Statistik in coHabit fuer Woche oder Jahr (`week`, `year`) |
| `COCKPIT_TEST_PHOTO=1` | der Galerie-Knopf im Beweisfoto-Blatt liefert ein erzeugtes Bild statt der Mediathek, je Tipp ein andersfarbiges (mehrere Fotos, Karussell) - nur falls ein UI-Test die Mediathek nicht erreicht |
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

⚠️ **Was der Simulator nicht zeigt, muss Felix auf dem Gerät prüfen** —
Tastaturverhalten, Gesten im Diagramm, Kontextmenüs. Drei Nachbesserungen
kamen genau daher (04.09.).

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
  für die `.entitlements` und die `Info.plist` der Erweiterungen — auch die
  erzeugt XcodeGen. Was alle Apps gemeinsam haben, steht dort **einmal** als
  YAML-Anker (`&app_settings`, `&shared_group`, `&widget_info`).
- **Wohin eine neue Datei gehört:** siehe Tabelle oben. Im Zweifel in die
  App, nicht nach `Core/` — nach `Core/` zieht man, was die zweite App
  wirklich braucht.
- **Healthy behält die Bundle-ID `com.fherrmann.cockpit`.** Nicht
  "aufräumen": daran hängen HealthKit-Berechtigung, Push beim
  Kalorienzähler und die Kalorien-Kacheln, die schon auf dem Homebildschirm
  liegen.
- **Bezeichner englisch, Kommentare deutsch.** Wie im Rest von Felix'
  Projekten. Kommentare erklären das **Warum**, nicht das Was — was der Code
  tut, steht im Code.
- **Keine Evaluation-Fragen im Repo.** Das Repo ist öffentlich; die Fragen
  des Evaluation-Tabs legt Felix in der App fest, Antworten bleiben auf dem
  iPhone. Auch in Tests, Doku, Screenshots und Commit-Nachrichten nur
  Platzhalter („Frage A").
- **Keine Logbook-Verhalten im Repo.** Dasselbe für das Logbook in Healthy:
  die Verhaltensweisen legt Felix in der App an, sie liegen beim Weight
  Tracker. Auch coHabit-Habits erscheinen dort mit Namen. In Code, Tests,
  Demo-Daten, Doku, Screenshots und Commit-Nachrichten nur Platzhalter
  („Verhalten A", „Gewohnheit A").
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
- **Kein Multi-User, keine Registrierung** — außer in coHabit. Healthy,
  Vault, Fokus und Einkaufsliste bleiben bei einer Person, einem Gerät, einem
  geteilten Geheimnis. coHabit hat Personen mit eigenem Token (App-Link,
  Healthy-Link oder beim Annehmen einer Einladung ausgestellt); den
  Master-Token `fh_private` bekommt es nie.
