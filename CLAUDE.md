# Arbeitsregeln für `cockpit-ios`

Vier iOS-Apps aus einem Repo, die Felix' Heimserver-Dienste bedienen:
**Healthy** (Kalorienzähler `food.fherrmann.com`, Weight Tracker
`weight.fherrmann.com`, Einkaufsliste `fherrmann.com/shopping-list`),
**Vault** (Notenübersicht `fherrmann.com/grades`, Finance Cockpit
`finanzen.fherrmann.com`), **Fokus** (Habits `fherrmann.com/habits`, To-Do
`fherrmann.com/todo`) und **Einkaufsliste** (nur die Einkaufsliste — für das Handy
von Joana, deren Token nur diesen einen Dienst öffnet).

Dieses Repo enthält **nur die Clients**. Änderungen an den Diensten gehören in
deren eigene Repos (`../food`, `../weight-app`, `../finance-cockpit`,
`../grades`, `../habits`, `../todo`, `../shopping`) — von hier aus wird an
ihnen nichts geändert, auch nicht "mal eben". Gerechnet wird in den Diensten (Sträh­nen, Abschlussnote,
Tagessummen); die Apps zeigen.

⚠️ **Wohin eine Datei gehört, entscheidet, wer sie übersetzt:**

| Ordner | übersetzt von | darf |
|---|---|---|
| `Shared/` | alle Apps **und** beide Erweiterungen | nichts, das es in einer Erweiterung nicht gibt (`UIApplication.shared`) |
| `Core/` | alle vier Apps | nichts, das nur eine App kennt (Diagramm-Typen, Tab-Namen) |
| `Shopping/` | Healthy **und** Einkaufsliste | der Einkaufs-Tab samt Store — Typen mit `Shopping`-Präfix, weil Healthy schon ein `DishEditSheet` hat |
| `Healthy/`, `Vault/`, `Fokus/`, `Einkaufsliste/` | genau diese App | alles |

Ein Verstoß fällt erst beim Bauen einer **anderen** App auf — deshalb baut
`tools/verify.sh` immer alle vier. `TabSelection` und `Router` gibt es je App;
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
tools/verify.sh                    # baut alle vier fuer den Simulator, Unit-Tests in Healthy
tools/verify.sh Vault              # nur eine
tools/run-simulator.sh Healthy weight bild.png   # eine App, ein Tab, mit Zugang, als Bild
tools/install-device.sh all --launch             # alle vier aufs iPhone (oder eine)
tools/testflight.sh Einkaufsliste                # archivieren + zu TestFlight hochladen (API-Schluessel noetig)
tools/testflight.sh Einkaufsliste --export-only  # nur .ipa bauen
```

Jedes Skript nimmt die App als **erstes** Argument (`Healthy`, `Vault`,
`Fokus`, `Einkaufsliste`). Tabs: Healthy `food|weight|shopping|widget`, Vault
`grades|finance`, Fokus `habits|todo|widget`, Einkaufsliste hat nur die eine Seite;
`setup` öffnet das Zugang-Blatt. Der Einkaufs-Token kommt wie die anderen aus
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
App liest sie nur im Debug-Build (`Access.seedFromEnvironment`).

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
  muss sie erst wegraeumen (`clearAssumptions`).

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
| `COCKPIT_TAB=weight` | mit welchem Tab die App aufmacht (`food`, `weight`, `finance`, `grades`, `habits`); `setup` öffnet das Zugang-Blatt |
| `COCKPIT_RANGE=threeYears` | Zeitraum im Gewicht-Tab (`month`, `last90`, `year`, `threeYears`, `allTime`) |
| `COCKPIT_DAY=2026-08-10` | Tag im Essen-Tab — ein leerer Tag macht die Liste kurz genug, dass mehr ins Bild passt |
| `COCKPIT_SELECT=2026-08-15` | wählt einen Tag im Diagramm vor, damit die Sprechblase im Bild ist |
| `COCKPIT_NO_LOCK=1` | Face-ID-Sperre aus |
| `COCKPIT_FORCE_LOCK=1` | Sperrbildschirm erzwingen (im Simulator ist kein Gesicht hinterlegt) |
| `COCKPIT_NO_PUSH=1` | keine Push-Anmeldung — sonst meldet jeder Testlauf eine Simulator-Kennung beim food-Backend an |
| `COCKPIT_ASK_PUSH=1` | fragt trotzdem nach der Benachrichtigungs-Erlaubnis (ohne sie zeigt der Simulator nichts an), meldet aber weiterhin keine Kennung an — fuer `pushtest.sh` |
| `COCKPIT_TODO_AREA=Uni` | öffnet im To-Do-Tab eine bestimmte Seite - wischen kann der Simulator nicht |
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
