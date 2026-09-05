# Plan: Aufteilung in Healthy, Vault und Fokus

Stand 2026-09-04. **Schritt 1 gebaut** (Punkte 1–10 erledigt), die Abnahme
auf dem Gerät steht aus. Wer weitermacht, liest `STAND.md` und arbeitet ab
Schritt 2 weiter.

Abweichungen bei der Umsetzung, festgehalten statt nur im Code:

- `ChartCallout`, `DaySeries`, `SeriesChip`, `Palette` liegen in
  `Healthy/Charts/`, nicht in `Core/` — sie brauchen Typen, die nur Healthy
  hat.
- Der Zustand des Zugang-Blatts liegt in `Core/SetupPresenter`, nicht im
  Router: die Knöpfe, die es öffnen, stehen in geteilten Tabs, und die
  kennen die Tabs der App nicht.
- Das Zugang-Blatt hat schon jetzt je Dienst einen eigenen Speichern-Knopf
  (war für Schritt 3 vorgesehen) — Fokus brauchte einen Abschnitt, der nur
  den Privat-Token speichert.

## Warum

Fünf Tabs sind voll (Zugang musste schon ins Zahnrad), und es kommen drei
Dienste dazu: To-Do, Roadmap, Einkaufsliste. Die Logik liegt in den Backends,
die Apps zeigen nur — die Querverbindungen (Track food, Schritte-Sträh­ne,
Widgets) laufen serverseitig. Der Schnitt kostet deshalb Struktur, keine
Funktion.

## Zielbild

| App | Bundle-ID | Tabs (heute) | Tabs (später) | Widgets | Sperre | Push von |
|---|---|---|---|---|---|---|
| **Healthy** | `com.fherrmann.cockpit` (**bleibt**) | Essen, Gewicht | + Einkaufsliste | Kalorien (Home + Sperrbildschirm) | keine | food (Schnellerfassung) |
| **Vault** | `com.fherrmann.vault` | Noten, Finanzen | — | keine | **ganze App**, Face ID | grades (neue Note) |
| **Fokus** | `com.fherrmann.fokus` | Habits | + To-Do, Roadmap | Habits (Home) | keine | später To-Do |

Healthy behält die Bundle-ID: damit bleiben Health-Berechtigung, Hintergrund-
zustellung, Push-Anmeldung beim Kalorienzähler und die vorhandenen
Kalorien-Kacheln (`com.fherrmann.cockpit.widget`) unangetastet. Vault und
Fokus sind neue Apps — mit allem, was das heißt (neue Berechtigungen, neue
Push-Kennungen, Kacheln neu auflegen).

**Ein Repo, drei App-Targets.** Nicht drei Repos: Zugang, Cookies, Offline-
Cache, Postausgang, Sperre, Tools und Harness würden sonst dreifach gepflegt —
genau das, wovor `CLAUDE.md` seit dem ersten Tag warnt. Der Repo-Name
`cockpit-ios` bleibt; „Cockpit" ist der Familienname, die Apps heißen Healthy,
Vault, Fokus.

## Zielstruktur

```
project.yml         drei App-Targets, zwei Widget-Targets, Tests, drei UI-Test-Bundles
Shared/             wie heute: was Apps UND Erweiterungen übersetzen
Core/               NEU - was alle Apps brauchen, aber keine Erweiterung:
                    Access, BiometricLock, Notifications, SetupView, WebView,
                    MessageViews, Palette, ChartCallout, DaySeries, SeriesChip
Healthy/            App/ (Einstieg, Tab-Gerüst, AppDelegate mit HealthKit), Food/, Weight/, Health/
Vault/              App/ (Einstieg, Sperre, AppDelegate mit Noten-Push), Grades/, Finance/
Fokus/              App/ (Einstieg, Tab-Gerüst), Habits/
HealthyWidget/      heute CaloriesWidget/ - Bundle-ID bleibt com.fherrmann.cockpit.widget
FokusWidget/        die Habits-Kachel, com.fherrmann.fokus.widget
Tests/              Unit-Tests, ein Bundle (Shared + Core sind der Kern)
UITests/            Harness.swift (gemeinsam) + je App eine Datei; drei Bundles
tools/              jedes Skript bekommt die App als erstes Argument
docs/               eine Doku, drei Kapitel wo nötig
```

Was **nicht** geteilt wird: `TabSelection`, `Router`, `RootView` — jede App
hat ihr eigenes kleines Gerüst. Ein gemeinsamer Router mit den Tabs aller
drei Apps wäre ein Aufzählungstyp, dessen Fälle in zwei von drei Apps nie
vorkommen.

## Schritt 1 — Der Schnitt (nichts Neues, alles funktioniert wie heute)

Erst wenn alle drei Apps auf dem Gerät laufen und alles tun, was die eine
heute tut, kommt etwas Neues dazu. Reihenfolge innerhalb des Schritts:

1. **`project.yml`.** Drei App-Targets mit gemeinsamen Projekt-Settings (Team,
   `MARKETING_VERSION`, Swift 6, strict concurrency). Je Target: eigene
   `PRODUCT_BUNDLE_IDENTIFIER`, `INFOPLIST_KEY_CFBundleDisplayName`, eigener
   Asset-Katalog fürs Icon, eigene Entitlements:
   - Healthy: HealthKit + Hintergrundzustellung, `aps-environment`, Keychain-Gruppe
   - Vault: `aps-environment`, Keychain-Gruppe, Face-ID-Beschreibung
   - Fokus: Keychain-Gruppe
   Widget-Targets: `HealthyWidget` (eingebettet in Healthy), `FokusWidget`
   (eingebettet in Fokus). Ein Schema je App; `verify.sh` baut alle drei.
   ⚠️ Die Fallstricke aus `ENTSCHEIDUNGEN.md` gelten je Erweiterung:
   `NSExtensionPointIdentifier` **unter** `NSExtension`, Version aus
   `$(MARKETING_VERSION)`, `embed: true`.

2. **Geteilte Keychain-Gruppe.** Alle fünf Targets bekommen
   `$(AppIdentifierPrefix)com.fherrmann.shared`; `Keychain.accessGroup`
   zeigt darauf. Die vorhandenen Einträge liegen in der alten Vorgabegruppe
   (`…com.fherrmann.cockpit`), an die nur Healthy und ihre Kachel herankommen.
   Deshalb beim ersten Start von Healthy eine **Wanderung**: alte Gruppe lesen,
   in die neue schreiben (`migrateToSharedGroup`, einmalig, Merker in
   UserDefaults wie bei `migrateAccessibility`). Danach finden Vault und Fokus
   die Token, ohne dass etwas eingetippt wird. Das Noten-Passwort (hinter Face
   ID) wandert mit — `saveProtected` in die neue Gruppe.

3. **Dateien verschieben** (`git mv`, damit die Geschichte bleibt):
   `Cockpit/Food`, `Weight`, `Health` → `Healthy/`; `Grades`, `Finance` →
   `Vault/`; `Habits` → `Fokus/`; aus `Cockpit/Core` wird `Core/`;
   `Cockpit/App` wird dreimal neu geschrieben (klein). `Cockpit/` verschwindet.

4. **Je App ein Einstieg.** `@main`, `RootView` mit zwei bis drei Tabs,
   Zugang als Blatt hinter dem Zahnrad (wie heute). Vault: **eine** Sperre
   vor der ganzen App statt zwei vor Tabs — `BiometricLock` bleibt, wird aber
   im RootView um alles gelegt; Sichtschutz im App-Umschalter immer; das
   Noten-Passwort kommt mit dem `LAContext` dieser einen Sperre. Die
   Finanzen behalten ihren WebView-Login (Passwort + Einmalcode).

5. **AppDelegate dreimal, mit einem gemeinsamen Kern.** HealthKit-Beobachtung
   nur in Healthy. Benachrichtigungs-Delegat als `Core/NotificationDelegate`
   mit einer Weiche je App: Healthy ohne Umschalten (Essen ist der erste
   Tab), Vault schaltet bei `kind == "grade"` auf Noten. ⚠️ Completion-Handler,
   nicht `async` (siehe `STAND.md`, Absturz vom 03.09.).

6. **Push-Kennungen.** Healthy meldet sich wie heute beim Kalorienzähler an.
   Vault meldet sich beim Notendienst an, sobald eine Sitzung steht (wie
   heute). `Notifications.deviceToken` bleibt in `Core`, jede App hat ihre
   eigene Kennung — sie liegt in den UserDefaults der jeweiligen App, nicht im
   Keychain, also automatisch getrennt.

7. **Backends.** `grades.env`: `APNS_TOPIC=com.fherrmann.vault`. Der
   `.p8`-Schlüssel gilt für alle Apps des Teams, sonst ändert sich dort
   nichts. Die alte Kennung der Cockpit-App in `data/devices.json` beantwortet
   Apple mit `BadDeviceToken`; die Notenwache räumt sie beim ersten Versand
   selbst weg. `food.env` bleibt (Topic = Healthy = alte Bundle-ID).
   `SERVER-CONTEXT.md` nachziehen.

8. **Tools.** `run-simulator.sh <app> <tab> [bild]`, `install-device.sh <app>
   [--launch]`, `uitest.sh <app> [filter]`, `pushtest.sh <app> [nutzlast]`,
   `verify.sh` (alle drei). `make-icon.swift` mit eigenem Motiv je App (Felix' Wunsch, 04.09.):
   Healthy ein Herz mit Pulslinie auf Grün, Vault ein Vorhängeschloss auf
   Dunkelblau, Fokus eine Zielscheibe auf Orange.
   `COCKPIT_TAB` behält seine Werte, jede App kennt nur ihre.

9. **Tests.** Unit-Tests bleiben ein Bundle (sie prüfen `Shared` und `Core`).
   UI-Tests: `UITests/Harness.swift` (start, scrollDown, shoot, waitFor …)
   in alle drei Bundles einbinden, je App eine Testdatei;
   `TEST_TARGET_NAME` je Bundle. Die Noten-Tests laufen in Vault mit
   `COCKPIT_NO_LOCK=1` wie heute.

10. **Doku.** `README.md` (drei Apps, drei Schnellstarts), `ARCHITEKTUR.md`
    (Zielstruktur oben ist die Vorlage), `CLAUDE.md` (Ordnerregeln:
    `Core/` vs. `Shared/` vs. App-Ordner), `STAND.md`, `ENTSCHEIDUNGEN.md`
    (der Schnitt selbst, Keychain-Gruppe, „ein Repo").

**Abnahme von Schritt 1:** `verify.sh` grün für alle drei; alle drei auf dem
iPhone; Token **einmal** eingegeben (in Healthy) und in Vault/Fokus ohne
Eingabe da; Schnellerfassung meldet sich in Healthy; eine Testnote (Notenwache
`--probelauf` reicht nicht — echter Versand) meldet sich in Vault und öffnet
den Noten-Tab; Kalorien-Kacheln laufen weiter; Habits-Kachel in Fokus neu
aufgelegt; Offline-Leiste in allen drei.

## Schritt 2 — Aufräumen, was der Schnitt freilegt

- Vault: `FinanceLock`/`GradesLock` sind eine Sperre geworden — die
  `lockedTabs`-Logik und der Sichtschutz je Tab verschwinden.
- Healthy: `Backend`-Fälle `grades`/`habits` werden dort nie benutzt; das
  Enum bleibt in `Shared` (Cookies für alle Dienste), aber jede App setzt nur
  die Cookies, die sie braucht.
- Der Vorschau-Tab (`COCKPIT_TAB=widget`) je App nur mit den eigenen Kacheln.

## Schritt 3 — Die neuen Dienste, je ein eigenes Projekt

Nicht Teil des Schnitts; hier nur, damit die Struktur sie schon vorsieht.

- **To-Do (Fokus).** Neuer Spring-Dienst `todo` unter `fherrmann.com/todo`,
  Bauart wie `habits`: Listen, Einträge mit Fälligkeit, erledigt/offen, kein
  Web-UI, Offline über den Postausgang. Die **Roadmap** ist darin eine Liste
  je App/Projekt mit Meilensteinen — kein vierter Dienst.
- **Einkaufsliste (Healthy).** Der einzige Punkt, der ein Backend *umbaut*:
  Gerichte bekommen Zutaten mit Mengen und eigenen Nährwerten je 100 g, die
  Nährwerte des Gerichts leiten sich daraus ab, und die Einkaufsliste ergibt
  sich aus den geplanten Gerichten (Zukunftstage gibt es im Essen-Tab schon).
  Eigener Plan, wenn es so weit ist — mit Migration der bestehenden Gerichte,
  die heute nur Werte je 100 g haben.

### Einkaufsliste: Zugang für eine zweite Person

> **Umgesetzt am 2026-09-05** — mit drei Abweichungen: der Pfad heißt
> `fherrmann.com/shopping-list` (Felix' Wortlaut), die Gerichte liegen als
> Zutatenlisten **im Einkaufs-Dienst** statt im Kalorienzähler (siehe
> `ENTSCHEIDUNGEN.md`), und statt TestFlight gibt es erst einmal eine eigene
> App **Einkaufsliste** (`com.fherrmann.einkauf`), die wie die anderen per Kabel
> installiert wird. Die Frage am Ende des Abschnitts ist damit entschieden:
> Gerichte darf jeder pflegen, weil sie nicht am Kalorienzähler hängen.

Joana soll die Einkaufsliste bedienen können — **und sonst nichts.**
Das verträgt sich nicht mit dem heutigen Modell (`SERVER-CONTEXT.md`: „ein
Token, ein Cookie, alles-oder-nichts"): wer `fh_private` hat, hat den
Kalorienzähler, den Statusboard-Privatteil, Habits. Deshalb:

- **Eigener Dienst, eigene Token.** Die Einkaufsliste wird ein eigener
  Spring-Dienst (`fherrmann.com/einkauf`, Bauart wie `habits`) und liegt
  **nicht** hinter dem Privat-Gate. Er prüft seine eigenen Token — eine kleine
  Liste in seiner Umgebung, je Token ein Name und ob es schreiben darf
  (`EINKAUF_TOKENS=felix:…:edit,joana:…:edit`). Gerichte und Zutaten liest
  er serverseitig aus dem Kalorienzähler, mit Felix' Privat-Token aus seiner
  eigenen Umgebung — genau wie `habits` die Schritte liest. Ihr Token öffnet
  damit nur diesen einen Dienst, und der Dienst gibt vom Kalorienzähler nur
  weiter, was die Liste braucht (Namen, Mengen), keine Tagebucheinträge.
- **Die App zeigt, wofür ein Token da ist.** Kein Rollenmodell, kein
  Anmelden: Healthy zeigt den Essen- und Gewicht-Tab, wenn `fh_private` und
  `weight_app_token` im Keychain liegen, und den Einkaufs-Tab, wenn ein
  Einkaufs-Token da ist. Felix trägt alle ein; sie trägt eines ein und sieht
  eine App mit einem Tab. Das Zugang-Blatt bekommt dafür je Dienst einen
  eigenen Abschnitt mit eigenem Speichern (heute hängen Privat- und
  Gewichts-Token an einem Knopf). Die Kalorien-Kachel zeigt auf ihrem Gerät
  „Kein Zugang" — richtig so, aber sie sollte sie gar nicht erst auflegen
  müssen: Kacheln nur anbieten, wenn der Zugang dafür da ist, geht mit
  WidgetKit nicht — also in der Beschreibung der Kachel sagen, wofür sie ist.
- **Zwei Personen, eine Liste.** Der Dienst führt **eine** Liste, beide
  Token schreiben in dieselbe; wer etwas abgehakt hat, steht am Eintrag
  (Name des Tokens). Kein Konfliktmodell darüber hinaus — abhaken ist
  idempotent, und der Postausgang der App reicht dafür aus.
- **Wie die App auf ihr Handy kommt.** Ein Entwickler-Install wie heute
  bräuchte ihr Gerät im Developer-Konto und den Mac in Reichweite - bei
  jedem Update. **TestFlight** ist der Weg für eine zweite Person: einmal
  eine App-Store-Connect-Eintragung für Healthy, dann Builds hochladen,
  sie installiert über die TestFlight-App. ⚠️ TestFlight-Builds sprechen
  den APNs-**Produktionshost**; `food.env` hat heute die Sandbox
  (`SERVER-CONTEXT.md`). Sobald Healthy über TestFlight läuft — auch auf
  Felix' Gerät — muss `APNS_HOST` dort umgestellt werden, sonst kommt nur
  `BadDeviceToken`.

**Offen, Felix entscheidet:** ob sie auch Gerichte anlegen/ändern darf
(dann bräuchte ihr Token Schreibzugriff auf den Kalorienzähler, was das
Modell wieder aufweicht) oder nur die Liste bedient — Vorschlag: nur die
Liste; neue Gerichte pflegt Felix, sie ergänzt freie Einträge („Milch").

## Risiken und wie sie abgefangen sind

| Risiko | Abfangen |
|---|---|
| Signieren dreier neuer Bundle-IDs | Automatisch mit Team `ZWFV263P59` — sobald das Apple-Konto **in Xcode angemeldet** ist. Vorher meldete `xcodebuild` „No Accounts" und konnte keine App-ID mit Push anlegen (Vault musste einmal aus Xcode heraus); nach der Anmeldung legte es die ID für Fokus mit Push von der Kommandozeile an (04.09.) |
| Keychain-Wanderung geht schief | Alte Gruppe wird **nicht** gelöscht; Healthy liest im Zweifel weiter aus ihr. Vault/Fokus zeigen dann „Kein Zugang" — sichtbar, nicht still |
| Noten-Push kommt nicht in Vault an | `devices.json` auf dem Server prüfen (wie am 02.09.), `APNS_TOPIC` prüfen, `journalctl -u grades-notenwache` |
| Habits-Kachel verschwindet vom Homebildschirm | Erwartet — sie zieht in die Fokus-Erweiterung um und muss neu aufgelegt werden. In `STAND.md` ankündigen |
| `project.yml` wächst auf das Dreifache | YAML-Anker für die gemeinsamen Blöcke (Entitlements, Info, Settings) — XcodeGen versteht sie |

## Aufwand

Schritt 1 ist eine lange Sitzung, der Rest davon steckt in `project.yml`,
Signieren und dem Gerätetest. Schritt 2 ist klein. Schritt 3 sind zwei
eigene Vorhaben; die Einkaufsliste das größere.
