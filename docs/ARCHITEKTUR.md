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
M2        [nativ][nativ][Web]     <- Zielbild Stufe 2   erledigt
M3        + HealthKit, Widget, Shortcuts, Face-ID-Sperre
danach    + Noten (nativ, hinter Face ID, mit Push bei neuer Note)
          + Habits (nativ; der Dienst hat kein Web-UI, die App ist sein einziger Client)
          + To-Do in Fokus (Bereiche als Seiten im Tab; der Dienst hat daneben Kacheln im Browser)
2026-09   + coHabit als fünfte App: die Habits ziehen aus Fokus aus und werden
            gemeinsam mit Freunden verfolgt (eigene Anmeldung je Person, Web daneben)
2026-10   + Sport als sechste App: Padel nativ (bis dahin nur die Seite des Dienstes) und
            das Gym aus Healthy, eigene Uhr-App für Krafttraining und Padel-Matches
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
Healthy/            App: Dashboard, Essen, Gewicht, Health-Abgleich, Diagramm-Bausteine (Gym seit 23.10. in Sport)
  App/              Einstieg, Tab-Gerüst, AppDelegate (HealthKit, Push-Kennung), HealthyRoute
  Dashboard/        der erste Tab: Karten für Recovery, Energie (EnergyCardModel), Gewicht, Essen, darunter
                    das Logbook; Vorführdaten - auch für Essen- und Gewicht-Tab
  Recovery/         Recovery-Seite (Ring, Bausteine, HRV-Kurve), Nächte und Recovery beim Weight Tracker
  Energy/           Energiebilanz beim Weight Tracker und ihre Formate
  Logbook/          Logbook und Effekte im Dashboard (LogbookSection, LogbookDays), Verhalten-Blatt,
                    Erinnerung 09:00, beim Weight Tracker
  Charts/           Callout, DaySeries, SeriesChip, Palette; „Defizit ⌀": Skala, Fläche, Zahlen innen
  Watch/            WatchLink: Token und kcal-Stand an die Uhr (WatchConnectivity)
  Health/           HealthKit lesen (HealthReader), Tage und Nächte bilden, Abgleich (HealthSync),
                    Schritte für die Sperrbildschirm-Kacheln (StepsWidgetBridge)
  Food/ Weight/
Vault/              App: Noten, Finanzen - eine Sperre vor allem
  App/ Grades/ Finance/ Web/
Fokus/              App: To-Do, Wald (Fokus-Sessions mit Bildschirmzeit-Sperre), Einkauf, Evaluation
  App/ Todo/ Forest/ (Store, Schild, Kurzbefehle, die Insel in SceneKit, Tagesziel aus coHabit)
  Evaluation/       persönliche Fragen je Tag, nur auf dem iPhone, Face ID mit 5 Minuten Frist -
                    seit 14.10. hier statt in Healthy (EvaluationImport übernimmt die Datei)
coHabit/            App: Habits mit Freunden - Heute, Timeline, Statistik, Profil, Detail + Chat,
                    Anlegen, Einladen, Abhaken mit Beweisfoto, Health, Push, Kachel-Vorschau
  App/ Design/ Today/ Detail/ Chat/ CheckIn/ Timeline/ Stats/ Profile/ Create/ Invite/ Onboarding/ Health/
  Classic/          die alte Habit-Liste der Fokus-App als „Heute" (Schalter im Profil)
coHabitWidget/      Kacheln von coHabit: klein/rund (konfigurierbar, Abhak-Knopf), mittel, gross, rechteckig
coHabitNotifications/ Notification Service Extension von coHabit: haengt Foto bzw. GIF an eine Meldung -
                    eine Datei plus NotificationImage, ImageFormat, CohabitToken, Keychain, Backend
CohabitShared/      was coHabit UND coHabitWidget teilen: API mit Bearer, Modelle, Postausgang,
                    App-Gruppe group.com.fherrmann.cohabit, App-Intents, Kachel-Ansichten, Farben
Einkaufsliste/            App: nur die Einkaufsliste (zweites Handy) - Einstieg und Icon, sonst nichts
  App/
Shopping/           der Einkaufs-Tab: Store, Liste, Gerichte, Regeln - in Fokus UND Einkaufsliste
                    (bis 14.10. Healthy statt Fokus)
Sport/              App (seit 23.10.): Padel und Gym
  App/              Einstieg, Tab-Gerüst, AppDelegate (gespiegeltes Training, Draht zur Uhr)
  Padel/            Autobuchung bei Playtomic über den Padel-Dienst: nächster Termin, Buchungen,
                    Ergebnisse von der Uhr, Geplant, Serien, Plätze; Vorführdaten
  Gym/              Trainingstage, Haken, Trainingsansicht (seit 14.10., bis 23.10. in Healthy),
                    beim Weight Tracker; WorkoutMirror: das gespiegelte Training der Uhr
  Watch/            SportWatchLink: Token an die Uhr, Ergebnisse und Trainings-Botschaften als Rückfall
Core/               was alle sechs Apps brauchen, aber keine Erweiterung (coHabit nur Notifications):
                    Zugang (Cookies, Keychain-Wanderung), Sperre samt Sperrbildschirm,
                    Benachrichtigungen, Zugang-Blatt, Fehler-/Offline-Leisten
Shared/             was Apps UND Erweiterungen übersetzen: APIClient, Keychain,
                    Offline-Cache, Postausgang, Modelle und APIs, Kachel-Ansichten
HealthyWidget/      Kalorien-Kacheln (Bundle-ID com.fherrmann.cockpit.widget, unverändert), seit 14.10.
                    dazu Schritte (Ring) und „Heute" (kcal + Schritte) auf dem Sperrbildschirm
HealthyWatch/       Uhr-App von Healthy (watchOS 11, in Healthy.app/Watch/): Tagesstand (das Training
                    seit 23.10. in SportWatch)
HealthyWatchWidget/ kcal-Komplikation der Uhr (Stil der Temperatur-Komplikation)
HealthyWatchShared/ was iPhone und Uhr teilen: Botschaften (WatchMessages), Komplikations-Stand
                    und -Ansicht - Healthy, HealthyWatch und HealthyWatchWidget übersetzen es
SportWatch/         Uhr-App von Sport (watchOS 11, in Sport.app/Watch/): Krafttraining (vom iPhone
                    gestartet und gespiegelt) und Padel-Match (auf der Uhr gestartet), beide in Health
SportWatchShared/   was Sport und SportWatch teilen: Trainings-Botschaften, das Zählen beim Padel,
                    Postausgang der Ergebnisse
FokusWidget/        Fokus-Countdown-Kachel (ohne Session: Stand von heute), Live-Aktivität der Session
FocusShared/        was Fokus UND FokusMonitor teilen: laufende Session, erlaubte
                    Apps, Schild-Regel - in der App-Gruppe group.com.fherrmann.fokus
FokusMonitor/       DeviceActivity-Erweiterung von Fokus: legt beim Intervallstart
                    den Schild (neu), nimmt ihn am Ende weg - eine Datei plus FocusShared/
Tests/              Unit-Tests, ein Bundle (Wirt: Healthy)
FokusTests/         Unit-Tests der Evaluation samt Übernahme aus Healthy (Wirt: Fokus)
CohabitTests/       Unit-Tests von coHabit (Wirt: coHabit - CohabitShared liegt nur dort)
SportTests/         Unit-Tests von Gym, Padel-Tab und dem Zählen beim Padel (Wirt: Sport)
UITests/            Harness.swift (gemeinsam) + je App eine Datei, sechs Bundles
project.yml         Quelle des Xcode-Projekts - sechs App-Targets, YAML-Anker für Gemeinsames
tools/              bootstrap · verify · run-simulator · uitest · pushtest · install-device · make-icon
docs/               diese Doku
```

⚠️ **Sechs Apps, ein Repo.** Nicht sechs Repos: Zugang, Cookies, Cache,
Postausgang, Sperre, Tools und Harness würden sonst sechsfach gepflegt. Was
in `Core/` liegt, muss in allen Apps übersetzen — wer dort etwas
einbaut, das nur eine App kennt (Diagramm-Typen, Tab-Namen), bricht die
anderen. `Shopping/` ist der eine Ordner, den genau zwei Apps teilen: der
Einkaufs-Tab in Fokus (bis 14.10. in Healthy) und die ganze App Einkaufsliste sind derselbe Code. `TabSelection` und `Router` sind deshalb **je App** klein
neu geschrieben statt geteilt.

⚠️ **Was in `Shared/` liegt, darf nichts benutzen, das es in einer
App-Erweiterung nicht gibt.** `UIApplication.shared` etwa ist dort gesperrt —
deshalb bleibt `Notifications.swift` in `Cockpit/Core/`, und `Palette.swift`
ist geteilt: die Farb-Initialisierer liegen in `Shared/Color+Hex.swift`, der
Rest (mit der `WeightSeries`-Erweiterung) im App-Target.

## Zugang im Client

Die Token liegen im **Keychain**, eingegeben einmalig über den
Einrichtungs-Bildschirm. Beim Start werden daraus Cookies gebaut und in
**zwei** Speicher gelegt:

- `WKWebsiteDataStore.default().httpCookieStore` — für die WebView-Tabs
- `HTTPCookieStorage.shared` — für die `URLSession` der nativen Tabs

Das erspart das `\/setup?token=…`-Ritual pro Gerät und überlebt einen
App-Neustart. Der Finanzen-Tab bleibt außen vor: dort meldet man sich im
WebView mit Passwort + Einmalcode an, das Session-Cookie hält 7 Tage und
verlängert sich bei Nutzung.

⚠️ **Erst alle Cookies in den gemeinsamen Speicher, dann in den von WebKit.**
Wer beides verschränkt (`setCookie` … `await` … `setCookie`), lässt zwischen
dem ersten und dem letzten Cookie ein Fenster offen, in dem eine schon
laufende Anfrage ohne ihres losgeht. Genau daran ist der Noten-Tab beim ersten
Versuch gescheitert: er fragt beim Erscheinen, und das war früher als sein
Cookie.

**Die Noten brauchen zwei Schranken.** Hinter dem Geräte-Token steht eine
Anmeldung. Die App hält Benutzer und Passwort im Keychain und meldet sich
selbst an, wenn die Sitzung abgelaufen ist — sichtbar wird das nie, ein 401
ist für sie kein Fehler, sondern ein Arbeitsschritt.

**Die Einkaufsliste hat ihren eigenen Token je Person.** Er liegt als
`shopping_token` im Keychain und wird als Cookie nur für den Pfad
`/shopping-list` gesetzt — der Dienst nimmt denselben Cookie wie der Browser
nach `/shopping-list/setup?token=…`. Healthy zeigt den Tab nur, wenn der
Token da ist; Einkaufsliste besteht aus nichts anderem. So sieht Joana
mit ihrem Token genau eine Liste und sonst nichts von diesem Server.

## coHabit: eine App mit Personen

coHabit ist die eine App, hinter der **mehrere Personen** stehen (Vertrag:
../habits/docs/COHABIT-CONTRACT.md). Der Dienst ist der frühere Habits-Dienst
unter `fherrmann.com/cohabit/api`; die Weboberfläche daneben hat denselben
Funktionsumfang, Android kommt aus `../cohabit-android`. Gerechnet wird nur im
Dienst - Serien, Quoten, Ränge, alle Texte der Kennzahlen kommen fertig an,
die App formatiert nur Datum und Uhrzeit.

**Zugang: ein Token je Person, als Bearer.** Kein Cookie, kein `fh_private`
(den bekommt die App nie). Der Token kommt als eingefügter Link - App-Link aus
dem Profil (`/cohabit/setup?token=…`), Healthy-Link (`food.fherrmann.com/setup?token=…`)
oder beim Annehmen einer Einladung ohne Zugang (der Dienst stellt ihn aus) -
und wird erst gespeichert, wenn `GET /me` damit 200 liefert. Er liegt in einer
eigenen Keychain-Gruppe (`ZWFV263P59.com.fherrmann.cohabit`), die nur App und
Kachel tragen. Eine 401 irgendwo heißt: lokal alles löschen, zurück zum Start.

**Schichten wie in den anderen Tabs**, aber mit eigenem Client: `CohabitAPI`
(Bearer, JSON-Fehlermeldungen des Dienstes, Fotos als Multipart mit
Idempotenz-Schlüssel), je Bildschirm ein `…Store`, Views ohne Rechnerei.
`Session` hält, wer angemeldet ist, `Router` den Bereich, geschobene Seiten und
Deep Links (`cohabit://…`, Vertrag §4; ohne Sitzung meldet ein Link mit Token
sofort an, ein Einladungslink öffnet die Registrierung, nur der Rest wartet in
`pendingLink`), `CheckInController` das Abhaken von
überall (Karte, Zeile, Detail, Chat) - mit Foto-Blatt, Wert-Blatt oder direkt.
`DataBus` zählt hoch, wenn sich etwas geändert hat; offene Bildschirme laden
dann neu.

**Die Oberfläche ist selbst gezeichnet** nach den Entwürfen (Farben nach
Vertrag §2.1 in `CohabitShared/CohabitPalette.swift`, hell und dunkel): eigene
untere Leiste über einer `TabView` mit versteckter Systemleiste, Karten mit
großen Radien und angeschnittenem Kreis, Primärknöpfe in Tinte. Gefärbt wird
**nach Typ**, nicht nach der gespeicherten Farbe, und zwar in den Farben, die
die Person je Typ gewählt hat (Vertrag §5.2b): die Zuordnung `TypeColors` und
`CohabitRef.typeColor(in:)` stehen in `CohabitShared/CohabitKinds.swift`, dort
auch die Reihenfolge von „Heute" (`typeOrder`, wie die klassische Liste). In
der App heißt das `CohabitRef.typeColor` (`@MainActor`, `Session.swift`) und
liest `Session.typeColors` - jede Ansicht, die so färbt, zeichnet sich nach
einer Wahl auf „Farben" über Observation von selbst neu. Die Kacheln kennen die
Sitzung nicht und nehmen `CohabitGroup.typeColors(for:)` (die von `/widget`,
dann `cohabit.me` der App, dann die Vorgaben); der Compiler hält sie davon ab,
`typeColor` ohne Zuordnung zu benutzen, weil es das in der Erweiterung nicht
gibt.

**Ohne Netz** zeigt jeder Bildschirm den letzten Stand aus dem `OfflineCache`
mit „Offline · Stand: …"; Einträge (auch mit Foto), Nachrichten und
Reaktionen gehen in `CohabitOutbox` (App-Gruppe, typisierte Aufträge: erst das
Foto, dann der Eintrag mit dessen Kennung). Idempotent über die Kennungen, die
die App vergibt. Nachgerechnet wird nichts - der Abhak-Knopf zeigt eine Uhr,
wartende Nachrichten stehen mit Uhr im Chat.

**Klassische Liste** (`coHabit/Classic/`): Der Schalter „Klassische Liste" im
Profil (`@AppStorage("today.classic")`, je Gerät) tauscht im Tab „Heute"
`TodayView` gegen `ClassicHabitsView` - die Habit-Liste der Fokus-App (Stand
`529c651`) in System-Optik, gespeist aus `GET /classic/habits` über
`ClassicAPI`, das auf `CohabitAPI` aufsetzt (kein `APIClient`). Was es damals
nicht gab, kommt aus coHabit: das Beweisfoto-Blatt (`CheckInController`), die
Detailseite (`Route.cohabit`), `SyncLine`, `ErrorLine` und der Postausgang
(`classicMark`/`classicUnmark`). Nach jeder Änderung stößt `ClassicStore`
`DataBus` und `WidgetSync` an wie die übrigen Aktionen.

**Push:** Topic `com.fherrmann.cohabit`, der Dienst schickt selbst
(`POST /devices` meldet die Kennung an). Jede Meldung trägt einen `link`; ein
Tipp führt genau dorthin (`CohabitNotificationDelegate`, Completion-Handler
wie in Core). Beim Abmelden wird die Kennung ausgetragen. Gehört ein Bild dazu
(`photoId` bzw. `imageUrl`, dann `mutable-content`), startet iOS die
Erweiterung **coHabitNotifications** (`com.fherrmann.cohabit.notifications`,
eingebettet in coHabit): sie liest den Token aus derselben Keychain-Gruppe
(lesbar ab dem ersten Entsperren), lädt das Foto vom Dienst bzw. das GIF direkt
von KLIPY und hängt es an; ein GIF bleibt animiert. Was sie lädt und wie die
Anlage heißt, steht in `CohabitShared/NotificationImage.swift` (prüfbar in
`CohabitTests`); sie übersetzt nur die paar Dateien, die sie braucht, nicht
`CohabitAPI`. Im Debug-Build reicht die App ihre umgebogene Dienst-Adresse
über die App-Gruppe weiter - Umgebungsvariablen bekommt eine Erweiterung nicht.

**Chat-Medien** (seit 05.10., Vertrag §2.7a): GIFs aus der Suche fragt die App
direkt bei KLIPY (`KlipyClient`, Schlüssel aus `GET /gifs/config`), eigene GIFs
gehen unverändert hoch. Animiert wird alles über ImageIO (`AnimatedImageView`),
KLIPY-Medien liegen nur im Speicher und im HTTP-Cache (`KlipyMedia`), eigene
Fotos und GIFs wie bisher auf der Platte (`PhotoLoader`). Reaktionen sind
Emojis, eine je Person (`Reactions`, `ReactionViews.swift`).

**Health:** nur lesend (Schritte, Lauf-/Gehdistanz, Trainings), je Co-Habit
mit Metrik und Einwilligung ein Tageswert pro Tag der Nachtragsfrist,
mindestens heute und gestern, in der Zone des Co-Habits
(`PUT /cohabits/{id}/health/{date}`). Abgleich beim Öffnen, höchstens alle
zehn Minuten, nur geänderte Werte.

**Die Kacheln** (`coHabitWidget`): klein und rund zeigen ein gewähltes
Co-Habit (App-Intent `SelectCohabitIntent`), mittel „Heute", groß Challenge,
Teamziel und offenen Streak, rechteckig den Challenge-Platz. Sie holen
`GET /widget` selbst mit dem Token aus der Zugriffsgruppe; ohne Netz zeigen sie
den Stand, den App oder Kachel zuletzt in die App-Gruppe gelegt haben. Der
Haken auf der kleinen Kachel ist ein `CheckInIntent` (läuft in der
Erweiterung, ohne Netz in den Postausgang) und zeigt sofort „erledigt"; Foto-
Pflicht öffnet stattdessen `cohabit://cohabit/{id}/checkin`. Die Ansichten
liegen in `CohabitShared/`, damit die App sie mit `COCKPIT_TAB=widget` zeigen
kann.

## Was ausserhalb der Oberfläche läuft

Zwei Dinge passieren, ohne dass jemand die App offen hat — und beide brauchen
deshalb einen `AppDelegate` statt einer `.task` an einer View: wird die App im
Hintergrund geweckt, gibt es gar keine Oberfläche.

**HealthKit.** Drei `HKObserverQuery` mit Hintergrundzustellung; iOS weckt die
App, wenn ein neuer Gewichtswert oder Schlaf geschrieben wird - und seit 14.10.
höchstens stündlich für Schritte, nur damit die Sperrbildschirm-Kacheln einen
frischen Health-Stand haben (`StepsMirror`; ohne Upload, gesperrt scheitert das
Lesen ohnehin). Beim Gewicht
merkt sich ein Anker, was schon geholt wurde, und wird erst **nach**
erfolgreichem Senden gespeichert — sonst gingen Werte verloren, wenn der
Server gerade nicht erreichbar war. Beim Schlaf bildet der Weckruf die letzten
14 Nächte neu und schickt sie nur, wenn sich ihr Inhalt geändert hat (Hash)
und das iPhone entsperrt ist.

Den Rest macht `HealthSync` als Dirigent im Vordergrund: Nächte → Energie →
Schritte → Gewicht, beim Wechsel in den Vordergrund und beim Öffnen von
Dashboard und Gewicht-Tab höchstens alle zehn Minuten (`syncIfDue`), beim
Ziehen sofort (`syncAll(force:)`). Die Erlaubnis fragt das Dashboard
(`connect()`), und war die Frage neu, wird gleich alles geholt. Gelesen wird in `HealthReader` (jede
Abfrage `async`, Ergebnis sofort in eigene Typen), aus Rohdaten werden Tage
und Nächte in `HealthEnergy` und `HealthNights` — rein und getestet, genau nach
den Regeln im Healthy-Vertrag, damit iOS und Android dieselbe Nacht bilden.
Danach, nicht abgewartet und nur im Vordergrund, die einmalige Rückholung
(`HealthBackfill`: 425 Nächte in Blöcken zu 60, zehn Jahre Energie in Blöcken
zu 365, Cursor in den UserDefaults). Wer etwas hochgeladen hat, zählt
`HealthSync.uploads` hoch; Dashboard, Recovery-Seite und Gewicht-Tab laden
darauf neu.

**Die Kacheln.** Healthy hat die Kalorien (Homebildschirm klein/mittel,
Sperrbildschirm als Ring und Rechteck; ein Tipp öffnet `healthy://food`, also
Essen mit heute), seit 14.10. die Schritte als Ring und „Heute" (zwei Ringe,
kcal gegessen und Schritte) auf dem Sperrbildschirm (`healthy://dashboard`) und
die kcal-Komplikation auf der Uhr; Fokus den Countdown der Session (ohne
Session den Stand von heute aus der App-Gruppe); die Habits-Kachel ist mit den
Habits nach coHabit umgezogen (siehe oben). Eigener Prozess, eigener
Container.
Sie holt sich `/api/food/day` **selbst** und liest das Token aus der geteilten
Keychain-Gruppe — die Vorgabegruppe der App, in der es ohnehin schon liegt.
Cookies der App sieht sie nicht, sie hängt ihren eigenen an die Anfrage. Die
App stößt nach jeder Änderung nur ein Neuzeichnen an; Daten reicht sie keine
weiter. Ausnahmen, weil die Kachel sie nicht selbst holen kann: wartende
Einträge (`PendingFoodMirror`) und die Schritte (`StepsMirror` - Health ist
gesperrt nicht lesbar; die Kachel nimmt das Größere aus diesem Stand und dem
Schrittzähler des iPhones, `StepsNow`). Die Uhr hat ihren eigenen Schlüsselbund:
Token und kcal-Stand schickt `WatchLink` per WatchConnectivity, die Komplikation
fragt danach selbst beim Kalorienzähler (`HealthyWatchWidget/KcalComplication`).

**Die Fokus-Sperre.** Während einer Fokus-Session (Wald-Tab in Fokus) liegt
ein Schild auf allen App-Kategorien außer den erlaubten Apps —
`ManagedSettingsStore().shield` aus dem Screen-Time-API, Erlaubnis einmal per
`FamilyControls` („Bildschirmzeit"). Das Ende meldet die App bei
`DeviceActivityCenter` an; wenn das Intervall endet, startet iOS die
Erweiterung **FokusMonitor** (`com.apple.deviceactivity.monitor-extension`),
die den Vorgabe-Store leert und die vorgeplante Ende-Meldung durch „Apps
wieder frei" ersetzt — die App muss dafür nicht laufen. Kürzer als 15 Minuten
nimmt DeviceActivity kein Intervall; eine kürzere Session (der Testbaum) wird
mit zurückverlegtem Anfang angemeldet, das Ende bleibt das echte. **Ein
Neustart des Handys nimmt den Schild weg**, das Intervall überlebt ihn aber:
iOS ruft die Erweiterung dann erneut mit `intervalDidStart`, und die legt den
Schild neu — dafür stehen laufende Session und erlaubte Apps in der
App-Gruppe (`FocusShared/FocusHandoff`), nicht in den UserDefaults der App.
Die App legt ihn zusätzlich bei jedem Vordergrund noch einmal. Die laufende Session liegt in den UserDefaults; sobald
die App danach wieder aktiv ist (`ForestStore.reconcile`, beim Start und bei
jedem Vordergrund), nimmt sie den Schild sicherheitshalber selbst weg, meldet
den Baum an den Habits-Dienst (`/habits/api/focus/sessions`, unverändert seit
dem Umzug der Habits). Das Tagesziel für „Heute" holt der Wald aus dem
coHabit-Co-Habit mit der Quelle FOCUS (`FocusGoal`, mit dem Privat-Cookie). Abbrechen gibt es nicht: keinen Knopf, keinen
Weg über die App. Den Fokus-Modus (Sperrbildschirm, Mitteilungen) schaltet
nicht die App (das darf sie nicht), sondern Felix' Kurzbefehl „Fokus an", den
die App beim Pflanzen per x-callback-URL mit der Restdauer in Minuten
aufruft — befristet bis zum Ende, ein „Fokus aus" braucht es nicht; zurück
kommt sie über das eigene URL-Schema `cockpit-fokus://forest` (deshalb hat
Fokus als einzige App eine eigene `Info.plist` in `project.yml`).

**Der Fokus-Modus ohne Sprung.** `FocusMinutesLeftIntent` (App Intent)
liefert der Kurzbefehle-App die Restminuten der laufenden Session aus der
App-Gruppe. Eine Automation „Wenn Fokus geschlossen wird" fragt sie ab und
befristet den Fokus-Modus — im Hintergrund, ohne dass die Kurzbefehle-App
aufspringt. Der URL-Aufruf beim Pflanzen bleibt als Rückfall hinter dem
Schalter „Kurzbefehl".

**Die Live-Aktivität.** Jede Fokus-Session startet eine Live-Aktivität
(`FocusActivityAttributes` in `Shared/`, Ansicht `FocusActivityView`, Widget
`FocusLiveActivity` in der Kachel-Erweiterung): Sperrbildschirm groß und ohne
Hintergrund, Dynamic Island klein. Sie braucht keine Aktualisierung — Anfang
und Ende stehen fest, Countdown und Balken zählen aus dem `timerInterval`.
Beenden kann nur die App; bis dahin markiert `staleDate` das Ende.

**Push.** Mehrere Dienste melden sich von selbst: der Kalorienzähler an
**Healthy** (Topic `com.fherrmann.cockpit`), die Notenübersicht an **Vault**
(Topic `com.fherrmann.vault`), der To-Do-Dienst an **Fokus**
(`com.fherrmann.fokus`) und coHabit an **coHabit** (`com.fherrmann.cohabit`,
Weiche über den `link` der Meldung statt über `kind`). Derselbe APNs-Schlüssel, aber zwei Apps und
damit zwei Gerätekennungen; jeder Dienst hält seine eigene Liste und
verschickt selbst. `NotificationDelegate` in `Core` zeigt an und meldet
`kind` an die App, die daraus ihren Tab wählt.

Die Nutzlast trägt ein `kind`; daran entscheidet der `AppDelegate`, welcher Tab
sich öffnet, wenn jemand die Meldung antippt. Ohne das landete man dort, wo man
zuletzt war.

**Healthy: eine Weiche für alles, was von außen kommt** (`HealthyRoute`).
Seit die App im Dashboard aufmacht, muss jeder Weg sagen, wohin er will:
Mitteilung **ohne** Art oder mit `quick-capture` → Essen (die APNs-Meldung des
Kalorienzählers hat keine Art), `logbook` → Dashboard, gescrollt zum Logbook auf
gestern (`Router.logbookRequests`); Link `healthy://food` (Kalorien-Kachel) → Essen
mit heute, `healthy://dashboard` (Schritte-Kacheln) → Dashboard. `evaluation` führt
seit 14.10. nirgends mehr hin - die Erinnerung kommt aus Fokus. Das URL-Schema steht in
einer eigenen `Healthy/Info.plist` (wie bei Fokus und coHabit erzeugt aus
`project.yml`, die übrigen Schlüssel kommen weiter aus den
`INFOPLIST_KEY_`-Settings). `Router.follow(_:)` setzt den Tab, `Router.open`
eine Seite im Dashboard, `showFoodToday()` zählt eine Bitte hoch, auf die der
Essen-Tab mit `show(.today())` antwortet.

**Healthy: das Dashboard.** Der erste Tab, und dort macht die App auf. Er
rechnet nichts: Recovery, Energie-Summary, Gewichts-Summary und der Tag beim
Kalorienzähler kommen parallel aus ihren Endpunkten (`DashboardStore`); jede
Karte fällt für sich aus, ein 404 heißt „gibt es beim Dienst noch nicht" und
lässt sie weg, nur fehlender Zugang wird zum Banner. Die Recovery-Seite liegt
im `NavigationStack` des Dashboards (`Router.dashboardPath`), nicht als Tab:
was zum Dashboard gehört, bleibt dort. Die Leiste: Dashboard, Essen, Gewicht, Gym
(Evaluation und Einkauf seit 14.10. in Fokus). Das Logbook steht seit 12.10.2026 im Dashboard
selbst, unter den Halbkarten, mit eigenem Store (`LogbookStore`); Sprungziele
im Scrollbereich sind `DashboardAnchor.logbook` und `.effects`. Eine
Offline-Leiste für beide Dienste (`OfflineBanner(backends:)`), sonst zählte sie
die wartenden Änderungen doppelt. Nicht zu verwechseln mit `/api/dashboard`
des Weight Trackers - das ist die Auswahl der Kacheln im Gewicht-Tab.

⚠️ **Die Noten melden ihre Kennung erst an, wenn eine Sitzung steht** — ihr
Endpunkt liegt hinter der Anmeldung. Der Kalorienzähler bekommt sie beim Start,
die Noten beim ersten Öffnen des Tabs. Wer den Tab nie aufmacht, bekommt keine
Meldung über Noten; das ist die Folge davon, dass diese Anmeldung etwas wert
sein soll.

**Die Token gelten in allen drei Apps.** Keychain-Zugriffsgruppe
`com.fherrmann.shared` in jedem Target. Healthy - dieselbe Bundle-ID wie die
frühere eine App - holt beim ersten Start die vorhandenen Einträge aus der
alten Vorgabegruppe in die geteilte (`Access.migrateToSharedGroup`); Vault
und Fokus finden sie danach ohne Eingabe. Nur das Noten-Passwort wandert
nicht: es liegt hinter Face ID, und eine Abfrage beim Start einer App, die
es gar nicht braucht, wäre Unsinn.

**Zugang ist ein Blatt, kein Tab** (in coHabit gibt es keins: dort ist der
Zugang ein eingefügter Link). Mit Habits gab es fünf Dienste — und
iOS zeigt höchstens fünf Tabs, alles darüber landet unter „Mehr". Zugang wird
selten gebraucht: ein Zahnrad in der Leiste der nativen Tabs (bei Essen und
Gewicht im „…"-Menü, weil dort die Leiste voll ist) öffnet dasselbe Blatt.
`Router.showsSetup` hält den Zustand; ohne Token geht es beim Start von
selbst auf.

**Vault: eine Sperre vor der ganzen App.** In der einen App standen zwei
Sperren vor zwei Tabs; in Vault liegt hinter jedem Tab etwas, das nicht
offen herumstehen soll - also `BiometricLock` um alles, Sichtschutz im
App-Umschalter immer, und beim Zurückkommen fragt sie gleich wieder.

**Fokus (bis 14.10. Healthy): eine Sperre vor der Evaluation, mit Frist.** Derselbe
`BiometricLock`, aber in `EvaluationLock` gewickelt: er geht erst zu, wenn der
Tab oder die App fünf Minuten verlassen war (`ContinuousClock`, läuft im
Ruhezustand weiter). Die Frist lebt in `RootView`, weil nur die Wurzel jeden
Tabwechsel sieht. Sichtschutz im App-Umschalter, solange der Tab offen ist.
**Kein Dienst dahinter:** Fragen und Antworten liegen in einer Datei der App
(`Application Support/Evaluation/evaluation.json`, Datenschutz „vollständig"),
gerechnet wird ausnahmsweise in der App (`EvaluationChartData`). Die Erinnerung
um 21:30 sind lokale Mitteilungen je Tag (`EvaluationReminder`).
**Umzug von Healthy nach Fokus (14.10.):** die Datei liegt im Container der App,
an den keine andere herankommt. Healthy legt die Bytes in den geteilten
Schlüsselbund (`Core/EvaluationHandoff`, nur entsperrt lesbar), liest zurück und
bietet sie bei jedem Start erneut an, bis Fokus mit dem SHA-256 quittiert; seine
eigene Datei behält Healthy als Sicherung und nimmt seine 21:30-Erinnerungen
zurück. Fokus (`Fokus/Evaluation/EvaluationImport`) prüft, schreibt, liest zurück,
quittiert und räumt den Eintrag weg - Antworten, die es schon hat, überschreibt es
nie (die aus Healthy liegen dann daneben als `evaluation-healthy.json`).

**Sport: Gym und Uhr (14.10. in Healthy, seit 23.10. in Sport).** Trainingstage, Geräte, Besuche und Haken liegen
beim Weight Tracker (Vertrag §6); jeder Schreibweg ist ein PUT mit der Kennung der
App und geht durch die Warteschlange (`GymChange`), angezeigt wird der Stand des
Dienstes mit `GymOverlay` darüber. Welcher Tag dran ist und „letztes Mal" rechnet
der Dienst. Ob ein Training läuft, merkt sich die App (`ActiveWorkout`). „Training
starten" weckt die Uhr-App von Sport mit einem Krafttraining (`HKHealthStore.startWatchApp`);
die Uhr führt `HKWorkoutSession` + `HKLiveWorkoutBuilder`, spiegelt die Session
aufs iPhone (`startMirroringToCompanionDevice`) und speichert am Ende in Health.
Über die gespiegelte Session gehen `WorkoutMessage`s: Puls und kcal von der Uhr,
der Plan zur Uhr (`WorkoutPlan`: das aktuelle Gerät, alle Geräte des Tages mit ihren
Haken, der letzte Satz für die Pausenzeit), „Satz erledigt" und „anderes Gerät"
(`choose`) mit Kennung und Quittung zurück (nur das iPhone schreibt zum Dienst;
quittiert es nicht, geht die Botschaft nach fünf Versuchen per WatchConnectivity).
90 Sekunden nach dem letzten Satz vibriert die Uhr einmal. Der Handler für die
Spiegelung steht im `AppDelegate`, weil iOS die App dafür im Hintergrund weckt; die
HealthKit-Delegaten sind `nonisolated` und reichen nur Werte weiter.

**Sport: Padel auf der Uhr (23.10.).** Ein Match startet auf der Uhr
(`WorkoutManager.startPadel`): ein eigenes `HKWorkoutSession` (`.paddleSports`, drinnen),
nicht gespiegelt - das iPhone muss nicht dabei sein. Gezählt wird in `PadelScore`
(`SportWatchShared`, getestet): Golden oder Silver Point (erst Vorteil, beim zweiten
40:40 entscheidet der nächste Punkt), Tie-Break bei 6:6, der Aufschlag wechselt je
Spiel und läuft über das Satzende weiter - je Team abwechselnd der linke und der rechte
Spieler (`PadelServers`, anfangs rechts; der Ball auf der Uhr tauscht beim Antippen).
Der Stand wird nach jedem Punkt gemerkt, ein Absturz der App verliert ihn nicht;
„Zurück" (auf der Zählseite und auf der Steuerseite) nimmt Punkte und das Antippen des
Balls zurück. Am Ende
speichert die Uhr das Training in Health (kcal) und gibt ein gültiges Ergebnis ab:
direkt an den Padel-Dienst (`POST /api/results` mit dem Privat-Token, den
`SportWatchLink` als Kontext schickt) und zugleich übers iPhone (`transferUserInfo`),
beide über `PadelReportOutbox`; der Dienst nimmt jede Kennung nur einmal an. Welche
Buchung dazugehört und wann es bei Playtomic eingetragen wird, entscheidet der Dienst
(`padel/README.md`), nicht die App.

**Sport: der Padel-Tab (23.10.).** Nativ, nach dem Muster API · Store · View, mit dem
Privat-Cookie wie To-Do (`Backend.padel`). Er zeigt, was die Seite des Dienstes zeigt,
in derselben Reihenfolge und mit denselben Texten (`PadelPlan` bildet `app.js` nach:
ein Eintrag je Tag und Mitspieler, Status, Freigabe, Rückfall); gerechnet wird beim
Dienst - jede Änderung antwortet mit der neuen Übersicht. Die Buchungen kommen live von
Playtomic und dürfen für sich scheitern. Die Farbe eines Mitspielers (die beiden mit
eigener Seite haben je eine) kommt vom Dienst (`partnerColor`), die App kennt keine Namen.

**Healthy: das Logbook liegt beim Dienst, die Erinnerung auf dem iPhone.**
Verhaltensweisen und Werte stehen im Weight Tracker (je Person, die Effekte
gegen die Recovery rechnet er dort). Seit 12.10.2026 **speichert jeder Tipp**
einen Wert (`PUT /api/logbook/days/{date}/values/{id}`), über die
Warteschlange (`LogbookChange`): sofort zu sehen, ohne Netz mit Uhr. Eine
Zeile zeigt, was am Zähler getippt ist, sonst was wartet, sonst den Stand des
Dienstes (`LogbookDays.value`); fehlt alles, ist sie **offen** - nicht „nein".
Die Antwort des Dienstes (der ganze Tag) ersetzt diesen Tag im Stand. Die
Erinnerung um 09:00 „Logbook" / „gestern offen" ist wie die der Evaluation
eine lokale Mitteilung je Tag (`LogbookReminder`), aber nur 14 Tage voraus -
iOS hält höchstens 64 je App bereit (bis 14.10. belegte die Evaluation hier 30). Sie kommt,
solange am Vortag etwas offen ist (ein wartender Wert gilt als beantwortet);
neu verteilt nach jeder Antwort und bei jedem Wechsel in den Vordergrund; im
Vorführmodus nie.

**Das Passwort der Noten liegt hinter Face ID.** Als einziges Geheimnis der
App: die übrigen sind Geräte-Token, die das Widget bei gesperrtem Bildschirm
lesen können muss. Beim Entsperren des Tabs bleibt der geprüfte `LAContext`
stehen, und die Keychain gibt das Passwort damit **ohne zweite Abfrage**
heraus. Sperrt der Tab wieder zu, wird er ungültig gemacht. Die App meldet ihre Kennung bei jedem
Start neu an (`/api/food/devices`), weil iOS sie gelegentlich austauscht.
Unabhängig davon fragt die App weiter selbst nach, solange sie läuft: die
Benachrichtigung ist ein Zustellweg, keine Voraussetzung.

## Ohne Netz

Drei Dinge: der Zwischenspeicher fürs Lesen und der alte Postausgang in
`Shared/Offline.swift`, dazu die Warteschlange der sofort gezeigten Änderungen
in `Shared/PendingChanges.swift` (seit 12.10.2026).

**Lesen.** `APIClient` legt jede erfolgreiche GET-Antwort als Datei ab
(`OfflineCache`, eine je Adresse samt Abfrageparametern, verschlüsselt bei
gesperrtem Gerät). Scheitert eine Anfrage am **Transport** — kein Netz, kein
Host, Timeout — kommt die Datei zurück, und `OfflineStatus` merkt sich je
Dienst, von wann sie ist. Die Tabs zeigen das als Leiste: „Offline – Stand von
02.09., 21:14". Bei 403 oder 500 gibt es keinen Rückgriff: der Dienst hat
geantwortet.

**Sofort sichtbar: To-Do, Einkaufsliste, Logbook, Essen, Gewicht** (`PendingChanges`). Anlegen
(auch Unteraufgaben und die Zutaten eines Gerichts), Abhaken, Ändern, Löschen,
„Abgehakte entfernen" gehen nicht mehr direkt an den Dienst, sondern als
**typisierte Änderung** in die Warteschlange (`TodoChange`, `ShoppingChange`;
seit Runde 3 auch jeder Logbook-Wert als `LogbookChange` auf der Spur des
Weight Trackers - je Tag und Verhaltensweise gilt der neueste, die Antwort ist
kein Brett und landet nicht im Offline-Stand; seit Runde 4 Essenseinträge als
`FoodChange` (Kennung der App, Summen vorläufig über `FoodOverlay`, die Kachel
bekommt die wartenden Einträge über die geteilte Keychain-Gruppe,
`PendingFoodMirror`) und das Gewicht von Hand als `WeightChange`, je Tag das
neueste).
Angezeigt wird der letzte Stand des Dienstes und darüber, was wartet
(`TodoOverlay`, `ShoppingOverlay` — reine Funktionen, getestet). Gesendet wird
sofort, mit 15 s Zeitlimit; ohne Netz bleibt die Änderung stehen und eine
kleine Uhr am Haken sagt es.

- **Kennungen vergibt die App** (kleingeschriebene UUID): Haken und Ändern
  brauchen ein Ziel, bevor der Dienst geantwortet hat. todo und shopping
  übernehmen sie; dieselbe Kennung zweimal legt nichts an (Nachsenden nach
  verlorener Antwort), bei der Einkaufsliste trifft eine in einem gleichnamigen
  Eintrag aufgegangene Kennung diesen (`clientIds` beim Dienst).
- **Je Dienst eine Spur**, darin der Reihe nach: erst das Anlegen, dann der Haken
  darauf. Ein Dienst, der nicht antwortet, hält die anderen nicht auf.
- **Einordnung der Antwort** (`APIClient.deliver`): 2xx mit JSON → angekommen,
  die Antwort (das ganze Brett) ersetzt den Stand und auch den Offline-Stand;
  404 beim Löschen → erledigt; 401/403 oder eine Anmeldeseite mit 200 →
  behalten, Spur steht („kein Zugang"); Netzfehler, 5xx, 408/425/429 →
  behalten, neuer Versuch nach 5, 15, 30, 60 s, dann alle 2 Min., solange die
  App vorn ist; sonstige 4xx → **abgelehnt**.
- **Abgelehnt heißt zurückgedreht:** die Änderung fliegt raus, und mit ihr, was
  darauf aufbaut (Unteraufgaben einer nicht angelegten Aufgabe, Haken darauf) —
  die Anzeige springt zurück. Eine Meldung oben über allem (`NoticeCenter`,
  eigenes Fenster wie `ToastWindow` in coHabit) nennt den Eintrag und den Grund
  des Dienstes; ist der Eintrag schlicht weg (404), ein grauer Hinweis statt
  eines Fehlers. Die Ablehnung steht außerdem in der Leiste, bis man sie
  wegtippt.
- **Zusammenfassen:** zweimal Abhaken → der letzte Stand gilt; Ändern wird in ein
  wartendes Anlegen gefaltet; Löschen von etwas nur Lokalem schickt gar nichts.
  Was gerade unterwegs ist, bleibt unberührt.
- **Auslöser** (`Core/PendingSync.swift`): Start der App (nach den Cookies),
  Vordergrund, Netz wieder da (`NWPathMonitor`), direkt nach dem Eintragen, nach
  jeder Antwort eines Dienstes. Kein Senden im Hintergrund.
- **Ablage** `Application Support/Pending/changes.json` mit
  `.completeFileProtectionUntilFirstUserAuthentication`; nicht lesbar → später
  erneut, kaputt → daneben gelegt und gemeldet, nie still geleert. Ein
  gelöschter Token nimmt die wartenden Änderungen seines Dienstes mit.
- **Stand gegen Stand:** jede Anfrage bekommt eine Nummer; ein Abruf, der vor
  einer Antwort losging und nach ihr ankommt, ersetzt den neueren Stand nicht.
  Vor einem Abruf wartet der Store bis zu 3 s, bis seine Spur nicht sendet.

**Der alte Postausgang** (`Outbox`, rohe `URLRequest`s mit
`queueWhenOffline: true`) bleibt nur noch für die Waldsitzungen; was eine ältere
Fassung von Healthy dort hinterlassen hat (Essen, Gewicht, ganze Logbook-Tage),
schickt er weiter. Nachgesendet wird der Reihe nach, sobald
irgendeine Anfrage wieder durchkommt oder die App in den Vordergrund kehrt;
wird der Ausgang leer, laden die Tabs neu. Bis dahin: alter Stand und „2
Änderungen warten auf Netz" in der Leiste — gezählt je Dienst des Tabs
(`OfflineStatus.pendingByBackend`).

⚠️ **Fehlender Zugang ist keine Ablehnung.** 401/403 und eine Anmeldeseite mit
200 (nginx leitet ohne Privat-Cookie um, `URLSession` folgt) lassen die
Änderung liegen. Bis 12.10.2026 flog sie als „abgelehnt" raus, und die
Anmeldeseite galt sogar als Erfolg.

⚠️ **Der Postausgang liest seine Datei, bis es gelingt.** Sie liegt wie der
Cache mit `.completeFileProtection` und ist bei gesperrtem iPhone nicht
lesbar. Weckt HealthKit die App in diesem Moment, darf das nicht „leer"
heißen: bis zum ersten erfolgreichen Lesen wird nichts gespeichert, jeder
Zugriff (`count`, `enqueue`, `replay` im Vordergrund) versucht es erneut, und
was inzwischen im Speicher dazukam, hängt hinter den gelesenen Einträgen
(bis 09.10.2026 überschrieb der nächste Eintrag die wartenden).

⚠️ **Ein neuerer PUT überholt einen wartenden an dieselbe Adresse.** Ein PUT
ersetzt beim Dienst den ganzen Stand (Logbook-Tag, Essenseintrag). Kommt ein
zweiter in den Postausgang, fliegt der ältere raus; kommt einer mit Netz an,
fallen die wartenden an dieselbe Adresse weg - und zwar bevor `APIClient` das
Nachsenden anstößt, sonst schickte das den alten Rumpf hinterher. POST und
DELETE bleiben alle stehen; das Nachsenden nimmt Erledigtes nach der Kennung
heraus, nicht als „den ersten". Offen bleibt ein schmales Fenster: startet ein
Nachsenden, während der neue PUT noch unterwegs ist, ist die Reihenfolge beim
Dienst nicht sicher.

⚠️ **Gerechnet wird nur die Liste selbst.** Die Overlays fügen ein, haken ab,
benennen um, entfernen, fassen gleiche Namen zusammen und sortieren wie der
Dienst — keine Sträh­ne, keine Tagessumme, keine Kachel. Die Regeln dahinter
bleiben in den Diensten; nach dem Senden gilt deren Brett.

## Was die App bewusst nicht tut

- **Keine eigene Datenhaltung.** Die Wahrheit steht in `food.json` und
  `weight.json` auf dem Server. Ein lokaler Cache wäre ein zweiter Stand mit
  Konfliktlogik — dafür ist die Datenmenge zu klein und die Verbindung zu gut.
- **Keine Backend-Änderungen.** Wenn ein Endpunkt fehlt, wird er im
  jeweiligen Repo ergänzt und dort deployt, nicht hier umschifft.
