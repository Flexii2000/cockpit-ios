# Die Backends

Referenz für den Client. **Quelle ist der Code der Dienste** — Java in
`../food` und `../weight-app`, Python in `../grades`. Steht hier etwas anderes
als dort, gilt dort.
Stand: 2026-09-02, gelesen aus den Controllern, Records und Routen.

## Überblick

| Dienst | Basis | Auth | Für die App |
|---|---|---|---|
| Kalorienzähler | `https://food.fherrmann.com` | Cookie `fh_private` | **nativ** (Phase 2) |
| Weight Tracker | `https://weight.fherrmann.com` | Cookie `weight_app_token` | **nativ** (Phase 1) |
| Finance Cockpit | `https://finanzen.fherrmann.com` | Login: Passwort + TOTP → Session-Cookie | **WebView, dauerhaft** |
| Noten | `https://fherrmann.com/grades` | Cookie `grades_token` **und** Anmeldung → Session-Cookie | **nativ** |
| Habits | `https://fherrmann.com/habits` | Cookie `fh_private` (wie der Kalorienzähler) | **nativ**, einziger Client |

Alle sind aus dem Internet über HTTPS erreichbar (Let's-Encrypt-Zertifikate,
also keine ATS-Ausnahme nötig). Kein VPN, kein Heimnetz-Zwang.

## Auth-Modell

Zwei verschiedene Token, beide langlebig, beide als Cookie:

- **`fh_private`** — das geteilte „Privat-Modus"-Token von `fherrmann.com`,
  gesetzt auf `Domain=.fherrmann.com`, gilt also für **alle** Subdomains.
  Im Browser wird es einmalig über `https://fherrmann.com/setup?token=…`
  ausgestellt. Die App macht das nicht nach: sie legt das Cookie direkt an
  (Keychain → Cookie-Store), sonst müsste das Token durch eine Weboberfläche.
- **`weight_app_token`** — eigenes Token nur für den Weight Tracker,
  Gültigkeit 5 Jahre, im Browser über `/setup?token=…`.
- **`grades_token`** — eigenes Token nur für `/grades`, Gültigkeit 5 Jahre,
  im Browser über `/grades/setup?token=…`. Es gilt **nur für diesen Pfad**;
  die App setzt es entsprechend eng (`Path=/grades`).

Die Noten haben als einziger Dienst **zwei** Schranken hintereinander: hinter
dem Geräte-Token steht noch eine Anmeldung mit Benutzer und Passwort. Die App
spielt sie nach, statt sie zu umgehen — Benutzername und Passwort liegen im
Keychain, das Passwort hinter Face ID (siehe `ARCHITEKTUR.md`).

⚠️ **Beide Domains verhalten sich ohne Cookie unhöflich:** nginx schickt bei
`food` einen **302 auf `https://fherrmann.com/`**, die Apps selbst antworten
mit **403 und einer HTML-Seite** statt mit 401/JSON. Ein Client, der auf
Statuscodes hört, sieht also nie ein sauberes „nicht angemeldet" — deshalb im
`APIClient` alles außer 2xx als „Zugang prüfen" behandeln und die Antwort
nicht als JSON zu lesen versuchen.

⚠️ **CORS ist für uns kein Thema.** Die `@CrossOrigin`-Freigaben in beiden
Backends existieren nur, weil sich die beiden Weboberflächen gegenseitig lesen.
Eine native App unterliegt keiner Same-Origin-Policy — sie darf beide APIs
vollständig lesen, nicht nur die drei freigegebenen Endpunkte.

## Datumsformate (der häufigste Stolperstein)

Spring serialisiert `LocalDate` als `"2026-09-01"` und `Instant` als
`"2026-09-01T08:15:30.123Z"`. **In derselben Antwort** (`FoodEntry` hat beides).
Ein `JSONDecoder` mit `.iso8601` scheitert am reinen Datum. Deshalb die
`.custom`-Strategie im `APIClient`, die beides probiert — nicht "wegoptimieren".

## Weight Tracker — `/api/weight`

| Methode | Pfad | Antwort |
|---|---|---|
| GET | `/api/weight/last90` | `[WeightPoint]` |
| GET | `/api/weight/year` | `[WeightPoint]` |
| GET | `/api/weight/month` | `[WeightPoint]` |
| GET | `/api/weight/all-time` | `[WeightPoint]` |
| GET | `/api/weight/vacations` | `[Vacation]` |
| GET | `/api/weight/summary` | `WeightSummary` |
| PUT | `/api/weight/target` | Body `{targetWeightKg}` → `WeightSummary` |
| POST | `/api/weight` | Body `{date, weightKg, keepExisting?}` → `WeightSummary` |
| GET/PUT | `/api/dashboard` | `{widgets: [String], version: 1}` — welche Kacheln sichtbar sind |
| GET | `/api/steps?from=…&to=…` | `[StepDay]` — Tage ohne Messung fehlen |
| POST | `/api/steps` | Body `{days: [StepDay], replace?}` → der **gespeicherte** Stand dieser Tage |
| GET/PUT | `/api/steps/goal` | `{stepsPerDay}` |
| GET | `/setup?token=…` | setzt das Cookie (braucht die App nicht) |

```
WeightPoint    date, measured?, avg7?, avg14?, avg30?,
               avg7Complete, avg14Complete, avg30Complete, target?
WeightSummary  date, current?, avg7?, avg14?, avg30?, target?, targetDate?,
               goalWeight?, startWeight?, recordingStart?,
               corridorLower?, corridorUpper?, corridorReachedOn?
Vacation       start, end, label
```
```
StepDay   date, steps        (beides Pflicht, `steps` >= 0)
```

⚠️ **Bei Schritten gewinnt das Maximum, nicht der letzte Wert.** Eine
Schrittzahl kann innerhalb eines Tages nur wachsen; meldet das Handy weniger,
weil die Uhr ihre Daten noch nicht übertragen hat, ersetzte ein blindes
Überschreiben einen richtigen Wert durch einen falschen — und an einem Tag
ohne weiteren Abgleich bliebe der falsche stehen. Die Antwort enthält deshalb
den **gespeicherten** Stand, der höher sein kann als das Gesendete.
`replace: true` ist der Ausweg für den einen Fall, den das Maximum verbietet:
jemand hat Messungen in Health gelöscht, die Zahl soll wirklich sinken.

⚠️ Das ist bewusst **anders als beim Gewicht**, wo `keepExisting` einen von
Hand eingetragenen Wert schützt. Bei Schritten gibt es keine Handeingabe —
Health ist die einzige Quelle, und der laufende Tag muss wachsen dürfen. Die
naheliegende Kopie der Gewichtsregel würde den ersten Teilstand des Tages für
immer festnageln.

⚠️ **Tage ohne Messung fehlen, statt mit 0 dazustehen.** Health unterscheidet
„nichts gemessen" nicht von „null Schritte" — also unterscheidet es der
Bestand, indem der Tag schlicht fehlt. Dieselbe Regel wie bei
`/api/food/daily`.

⚠️ **`/api/dashboard` speichert seit Version 1 die *vollständige* Liste.**
Vorher standen dort nur die Zusätze, und jede Oberfläche setzte vier
Basis-Kacheln selbst davor — die ließen sich deshalb nicht entfernen. Jetzt ist
jede Kachel entfernbar, auch alle auf einmal.

Die beiden Bedeutungen sehen als JSON identisch aus, deshalb das
`version`-Feld: **fehlt es, behandelt der Server die Liste als Zusätze** und
ergänzt die vier. Ein Client, der die vollständige Liste schickt, muss
`version: 1` mitsenden — sonst löscht ein alter, noch offener Browser-Tab die
Basis-Kacheln. Eine alte Datei wird beim ersten Lesen einmalig umgeschrieben.

⚠️ **`keepExisting` ist die Regel für Importe.** Es gibt genau **einen** Wert
pro Tag. Steht `keepExisting: true` im Body und der Tag ist schon belegt, bleibt
der vorhandene Wert stehen und die Antwort enthält den unveränderten Stand.
Gesetzt wird das **nur vom Health-Abgleich**: ein von Hand eingetragener Wert
ist der verlässlichere, und ohne diese Regel hinge das Ergebnis daran, wer
zuletzt geschrieben hat — je nach Weckzeitpunkt von iOS mal so, mal so. Im
Browser und in der App wird weiterhin überschrieben.

⚠️ **Die Reihen beginnen beim frühesten Messwert, nicht beim
Aufzeichnungsbeginn.** Seit dem Health-Abgleich reicht der Bestand bis 2018
zurück; `year` und `all-time` zeigen das. **Die Zielkurve (`target`) ist vor
`recordingStart` `null`** — sie startet per Definition beim Startgewicht an
diesem Tag, und weiter zurück gezeichnet behauptete sie eine Vorgabe, die es
damals nicht gab. Ein Client muss also damit rechnen, dass `target` fehlt,
während `measured` dasteht.

⚠️ **`corridorReachedOn` betrachtet nur Einträge ab `recordingStart`.** Wer
2022 einmal im Zielkorridor war, ist deshalb heute nicht in der Halte-Phase.
Ohne diese Grenze meldete die Zusammenfassung nach dem Health-Import den
Korridor als erreicht, und jedes Frontend streckte seine Achse, um ein Band
unterzubringen, das über das laufende Vorhaben nichts aussagt.

⚠️ **Es gibt kein DELETE für Messwerte** — aber es braucht auch keins:
`POST /api/weight` mit einem Datum, das schon existiert, **ersetzt** den Wert
(`removeIf` + `add` in `WeightRepository`). Ein Tippfehler wird also durch
erneutes Eintragen korrigiert. Was nicht geht: einen Tag wieder ganz leeren.
Falls das je gebraucht wird, ist das eine Ergänzung im Weight-Backend, nicht
im Client.

`?` = kann `null` sein, in Swift also `Optional`. Die `avg…Complete`-Flags sagen,
ob der Schnitt auf einem vollen Fenster steht — die Weboberfläche zeichnet
unvollständige Schnitte gestrichelt. Das Ziel ist eine **Sättigungskurve**
(0,75 % Körpergewicht pro Woche), kein Datumsziel; der Korridor (±1,5 kg) wird
erst ab dem Tag gezeichnet, an dem seine Oberkante erstmals unterschritten war.

## Kalorienzähler — `/api/food`

| Methode | Pfad | Antwort |
|---|---|---|
| GET | `/api/food/day?date=YYYY-MM-DD` | `DaySummary` (ohne `date` = heute) |
| GET | `/api/food/daily?from=…&to=…` | `[DayTotal]` |
| GET | `/api/food/dishes` | `[Dish]` |
| POST | `/api/food/dishes` | Body `DishRequest` → `Dish` |
| PUT | `/api/food/dishes/{id}` | Body `DishRequest` → `Dish` |
| DELETE | `/api/food/dishes/{id}` | 204 |
| POST | `/api/food/entries` | Body `NewEntryRequest` → `DaySummary` |
| DELETE | `/api/food/entries/{id}` | `DaySummary` |
| GET/PUT | `/api/food/targets` | `Nutrients` / Body `TargetsRequest` |
| GET | `/api/food/features` | `{quickCapture: Bool}` |
| POST | `/api/food/quick-capture` | Body `{date, text, meal}` → `QuickCaptureJob` |
| GET | `/api/food/quick-capture/{id}` | `QuickCaptureJob` |
| GET | `/api/food/status` | `StatusInfo` (für das Statusboard) |
| POST | `/api/food/devices` | Body `{token}` → 204. Meldet ein Gerät für Push an |

```
Nutrients      kcal, proteinG, carbsG, fatG            (alle nicht-optional)
Meal           BREAKFAST | LUNCH | DINNER | SNACK
Dish           id, name, per100g: Nutrients, portionG?, lastUsedOn?
FoodEntry      id, date, dishId?, name, grams, per100g, meal, createdAt: Instant
DaySummary     date, targets, consumed, remaining,
               entries: [FoodEntry], mealTargets: [Meal: Double]
DayTotal       date, consumed: Nutrients
NewEntryRequest date, dishId?, dish?: DishRequest, grams, meal
QuickCaptureJob id, status ("running"|"done"|"failed"), preview?, error?, elapsedSeconds
QuickCapturePreview known, dishId?, name, per100g, portionG?, grams, meal,
               valueSources: [String: String], note?
```

⚠️ **Der Server meldet sich, wenn ein Auftrag fertig ist.** Seit 2026-09-01
schickt er eine Push-Benachrichtigung an alle angemeldeten Geräte
(`/api/food/devices`). Der Schlüssel liegt auf dem Server
(`/etc/apns-cockpit.p8`), die Kennungen in `data/devices.json`; lehnt Apple
eine ab, fliegt sie raus. **`APNS_HOST` steht auf der Sandbox** — das passt zu
einer aus Xcode installierten App. Ein TestFlight- oder App-Store-Build
braucht `https://api.push.apple.com`, sonst kommt nur `BadDeviceToken`.
Nachfragen tut die App trotzdem weiter, solange sie läuft: die
Benachrichtigung ist die Zustellung, nicht die Wahrheit.

⚠️ **Schnellerfassung ist ein Auftrag, kein Aufruf.** `POST /quick-capture`
startet auf dem Server eine Claude-Code-Session und kommt sofort mit einer Job-ID
zurück; das Ergebnis wird per `GET /quick-capture/{id}` abgeholt, bis `status`
nicht mehr `running` ist. Gemessen wurden **bis zu 56 s**, das Server-Timeout
steht auf 180 s. Der Client muss also mit langem Warten umgehen können —
`URLSession`-Timeout entsprechend hoch, und die Ansicht darf derweil nicht
blockieren. Der Vorschlag ist eine **Vorschau**: er wird erst durch ein
normales `POST /entries` zum Eintrag.

⚠️ `GET /features` fragen, bevor die Schnellerfassung angeboten wird — sie ist
abschaltbar (`food.agent.command` leer) und dann gibt es sie schlicht nicht.

⚠️ **`mealShares` ist alles oder nichts.** `PUT /targets` nimmt die Aufteilung
nur an, wenn **jede** der vier Mahlzeiten drinsteht (auch mit Anteil 0) und die
Summe 1,0 ergibt (±0,011) — es sind **Anteile, keine Prozent**. Sonst kommt ein
400 mit Klartext („Die Anteile muessen zusammen 100 % ergeben, sind aber
96,0 %"). Nachzulesen in `validShares()` in `FoodService.java`. Der Client
prüft das vorher, damit man den Fehler nicht erst nach dem Sichern sieht.

⚠️ **Fehlerantworten tragen ihre Begründung im Rumpf.** `APIClient` reicht sie
durch (`APIError.http(Int, String?)`), weil „HTTP 400" die schlechtere von
beiden Meldungen ist.

## Noten — `/grades/api`

Quelle: `../grades/app/api/routen.py` und `../grades/app/lib/berechnung.py`.

| Methode | Pfad | Was |
|---|---|---|
| POST | `/grades/api/login` | `{username, password}` → `{ok: true}`, Sitzung 7 Tage |
| GET | `/grades/api/overview` | der ganze Stand (siehe unten) |
| POST | `/grades/api/overview` | derselbe Stand, gerechnet mit `{annahmen: {"Modulname": 2.3}}` |
| POST | `/grades/api/devices` | `{token}` — Push-Kennung anmelden |

⚠️ **Ohne Geräte-Token antwortet der Dienst mit 404**, nicht mit 403. Ohne
Anmeldung mit **401**. Beide Fälle sehen im Client verschieden aus und haben
verschiedene Auswege: 404 heißt „Token prüfen", 401 heißt „die App meldet
sich einfach neu an" (`GradesAccessProblem`).

⚠️ **Die Feldnamen der Antwort sind deutsch** — sie kommen aus der Rechnung
des Dienstes (`module`, `szenarien`, `ects_erreicht`, `moegliche_noten`,
`einfacher_schnitt`, `regel`). Übersetzt wird in `GradesModels.swift` über
`CodingKeys`. Das ist Absicht: eine zweite Namensgebung auf dem Server wäre
eine Zuordnung, die bei jeder neuen Zahl mitgepflegt werden müsste.

```
Modul       name, ects, bereich, semester, pruefung, benotet,
            note (null = offen), quelle ("name" | "zuordnung"),
            notenchecker_name (nur bei "zuordnung"), annahme
Szenarien   aktuell, best_case, average_case, worst_case, angenommen
Stand       stand (fertig formatiert), stand_iso (mit Zeitzone)
```

⚠️ **`benotet: false` gibt es** (Seminare, Transfermodule). Diese Module
zählen in keiner Rechnung mit und gehören in keine Tabelle — die App filtert
sie heraus, so wie es die Weboberfläche tut.

⚠️ **Annahmen sind zustandslos.** Die Weboberfläche merkt sie sich in ihrer
Sitzung, die App schickt sie bei jeder Anfrage mit. Beides beeinflusst sich
nicht: Gedankenspiele auf dem Handy schreiben keinen offenen Browser-Tab um.
Der Server nimmt nur Werte aus `moegliche_noten` an und wirft alles andere
still weg.

⚠️ **Gerechnet wird nur dort.** Die Regel aus PO-I23 § 8 Abs. 2 (Modulnoten
ECTS-gewichtet, Bachelorthesis dreifach) steht in `berechnung.py` und darf
**nicht** in Swift nachgebaut werden. Eine neue Zahl gehört in
`auswerten()` — dann haben beide Oberflächen sie.

**Push:** `../grades/app/bin/notenwache.py` vergleicht alle fünf Minuten den
Notenchecker-Snapshot mit dem zuletzt gesehenen Stand und schickt neue Noten
selbst über APNs (eigener Schlüssel, nicht über das food-Backend) — an
**Vault** (`APNS_TOPIC=com.fherrmann.vault` in `grades.env`). Die Nutzlast
trägt `"kind": "grade"`; Vaults `AppDelegate` schaltet daraufhin auf den
Noten-Tab. Der Kalorienzähler schickt weiter an `com.fherrmann.cockpit`,
also an Healthy.

## Habits — `/habits/api/habits`

Quelle: `../habits/src/main/java/com/fherrmann/habits/`. Kein Web-UI — die App
ist der einzige Client, deshalb ist die Antwort schon fertig gerechnet
(`HabitStatus`) und die App zählt **nichts** nach.

| Methode | Pfad | Was |
|---|---|---|
| GET | `/api/habits` | alle Habits mit Sträh­ne und Stand von heute |
| POST | `/api/habits` | `{name, kind, weeklyStepGoal?}` → 201 |
| PUT | `/api/habits/{id}` | Name/Wochenziel ändern — **nicht** die Art |
| DELETE | `/api/habits/{id}` | löscht samt aller Einträge, kein Archiv |
| POST | `/api/habits/{id}/marks` | `{date?}` — Haken (BUILD) bzw. Rückfall (QUIT), ohne Datum heute |
| DELETE | `/api/habits/{id}/marks/{date}` | Haken bzw. Rückfall zurücknehmen |

```
HabitStatus  id, name, kind (BUILD|QUIT|FOOD|STEPS), unit (DAYS|WEEKS),
             weeklyStepGoal, streak, doneToday, atRisk,
             progress {value, goal} | null, recent [7 × bool, älteste zuerst],
             unavailable (String | null)
```

⚠️ **`atRisk` ist kein Fehler.** Ein Build-Habit, das heute noch nicht
abgehakt ist, hat seine Sträh­ne nicht verloren — erst um Mitternacht. Bis
dahin ist `streak` der Stand von gestern und `atRisk` gesetzt. Die App zeigt
das als blasse Flamme und „heute noch offen". Bei QUIT gibt es das nicht: ein
Rückfall heute ist entschieden, `streak` ist dann 0.

⚠️ **Was `doneToday` bei QUIT heißt:** *kein* Rückfall heute. Der Knopf in
der App trägt dann einen ein (`POST …/marks`); ist einer eingetragen, nimmt
derselbe Knopf ihn zurück (`DELETE …/marks/{heute}`).

⚠️ **Automatische Habits (FOOD, STEPS) nehmen keine Marks** — `POST …/marks`
ist dort ein 400. Ihr Stand kommt bei jeder Anfrage frisch aus dem
Kalorienzähler bzw. dem Weight Tracker; `progress` ist kcal gegen 80 % des
Tagesziels bzw. Schritte gegen das Wochenziel (Woche ab Montag 0:00
Europe/Berlin). Ist die Quelle weg, steht `unavailable` und alles andere ist
nicht zu gebrauchen.

⚠️ **Fehler kommen als Klartext** (`Ein Habit braucht einen Namen.`), nicht
als JSON-Fehlerseite — `APIClient.shortMessage` reicht sie so durch.

## Finance Cockpit — kein API

Bewusst kein JSON. Die Seite ist statisches HTML, das ein täglicher
Claude-Lauf über `lib/render.py` neu baut, ausgeliefert unter
`script-src 'none'`; der eingebaute Chat läuft als Formular-POST in einem
`<iframe>` mit `<meta refresh>`. Das ist der Kern des Projekts: der Agent
gestaltet das Dashboard jeden Tag neu.

**Deshalb bleibt dieser Tab ein WebView.** Ein nativer Nachbau bräuchte eine
feste Datenstruktur und würde genau die Freiheit nehmen, für die das Cockpit
gebaut wurde. Siehe `ENTSCHEIDUNGEN.md`.

Zugang: Formular-Login mit Passwort **und** TOTP-Einmalcode, danach ein
signierter Flask-Session-Cookie (7 Tage, `SESSION_REFRESH_EACH_REQUEST`, wird
bei Nutzung also verlängert). Kein Token, das die App setzen könnte — der
Login passiert im WebView. Bei aktiver Nutzung läuft er praktisch nie ab.
