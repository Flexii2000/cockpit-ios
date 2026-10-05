# Die Backends

Referenz für den Client. **Quelle ist der Code der Dienste** — Java in
`../food`, `../weight-app` und `../habits` (coHabit), Python in `../grades`. Steht hier etwas anderes
als dort, gilt dort. Die Android-App (`../healthy-android`) spricht dieselben
Endpunkte von Kalorienzähler und Weight Tracker, mit einem persönlichen Token
statt der Cookies (siehe „Persönliche Token" unten).
Stand: 2026-09-02, gelesen aus den Controllern, Records und Routen.

## Überblick

| Dienst | Basis | Auth | Für die App |
|---|---|---|---|
| Kalorienzähler | `https://food.fherrmann.com` | Cookie `fh_private` | **nativ** (Phase 2) |
| Weight Tracker | `https://weight.fherrmann.com` | Cookie `weight_app_token` | **nativ** (Phase 1) |
| Finance Cockpit | `https://finanzen.fherrmann.com` | Login: Passwort + TOTP → Session-Cookie | **WebView, dauerhaft** |
| Noten | `https://fherrmann.com/grades` | Cookie `grades_token` **und** Anmeldung → Session-Cookie | **nativ** |
| coHabit (früher Habits) | `https://fherrmann.com/cohabit/api` | `Authorization: Bearer` — Token **je Person** | **nativ** (App coHabit), daneben Web unter `/cohabit/` und Android |
| Wald-Sessions | `https://fherrmann.com/habits/api/focus` | Cookie `fh_private` | **nativ** (Fokus, Wald) |
| To-Do | `https://fherrmann.com/todo` | Cookie `fh_private` | **nativ** (Fokus) — daneben eine Weboberfläche |

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
- **`health_token`** / `Authorization: Bearer` — seit 2026-09 ein
  **persönlicher Token je Person**, derselbe für Kalorienzähler **und** Weight
  Tracker (siehe „Persönliche Token" unten). Die iPhone-App braucht ihn nicht:
  `fh_private` und `weight_app_token` meinen weiterhin Felix.
- **`shopping_token`** — eigenes Token **je Person** nur für
  `/shopping-list`, im Browser über `/shopping-list/setup?token=…`. Der
  Dienst liegt **nicht** hinter dem Privat-Gate und nimmt den Token als
  Cookie oder als `Authorization: Bearer`; die App setzt das Cookie mit
  `Path=/shopping-list`. Der Name zum Token steht an jedem Eintrag
  (`addedBy`, `checkedBy`).

Die Noten haben als einziger Dienst **zwei** Schranken hintereinander: hinter
dem Geräte-Token steht noch eine Anmeldung mit Benutzer und Passwort. Die App
spielt sie nach, statt sie zu umgehen — Benutzername und Passwort liegen im
Keychain, das Passwort hinter Face ID (siehe `ARCHITEKTUR.md`).

⚠️ **Beide Domains verhalten sich ohne Cookie unhöflich:** die Dienste
antworten mit **403 und einer HTML-Seite** statt mit 401/JSON. (Bis 2026-09
schickte nginx bei `food` zusätzlich einen **302 auf `https://fherrmann.com/`**;
das Gate ist mit den persönlichen Token weggefallen, ältere Clients müssen den
302 trotzdem weiter als „kein Zugang" lesen.) Ein Client, der auf
Statuscodes hört, sieht also nie ein sauberes „nicht angemeldet" — deshalb im
`APIClient` alles außer 2xx als „Zugang prüfen" behandeln und die Antwort
nicht als JSON zu lesen versuchen.

⚠️ **CORS ist für uns kein Thema.** Die `@CrossOrigin`-Freigaben in beiden
Backends existieren nur, weil sich die beiden Weboberflächen gegenseitig lesen.
Eine native App unterliegt keiner Same-Origin-Policy — sie darf beide APIs
vollständig lesen, nicht nur die drei freigegebenen Endpunkte.

### Persönliche Token (seit 2026-09)

Damit Torben einen eigenen Zugang hat, kennen Kalorienzähler und Weight
Tracker **je Person einen Token** (`HEALTH_TOKENS=torben:…` in
`/etc/food.env` **und** `/etc/health-viz.env`, wortgleich). Er kommt an als

- `Authorization: Bearer <token>` — die Android-App, oder
- Cookie `health_token` auf `Domain=fherrmann.com` — ein Browser, einmal
  eingerichtet über `https://food.fherrmann.com/setup?token=…` (oder dasselbe
  unter `weight.`), öffnet damit beide Dienste.

Der Dienst setzt den Namen zur Person als Principal; **jeder Endpunkt arbeitet
dann auf ihren Daten** (Dateien unter `data/users/<name>/`, Felix' bleiben, wo
sie waren). Die alten Cookies `fh_private` und `weight_app_token` meinen
weiterhin Felix. Kommen persönlicher Token und alter Cookie zusammen an,
gewinnt der persönliche. Angelegt werden die Token von
`food/deploy/setup-health-users.sh`.

Was damit dazukam:

| Dienst | Methode | Pfad | Was |
|---|---|---|---|
| food | GET | `/api/food/features` | zusätzlich `me` (Name zum Token), `detailedNutrients` und `micronutrients`; `quickCapture` ist **pro Person** schaltbar (`FOOD_QUICK_CAPTURE`) |
| food | POST | `/api/food/devices` | zusätzlich `platform: "android"` → Firebase-Kennung; ohne → APNs wie bisher |
| food | GET | `/api/app/android` | `{versionCode, versionName, sizeBytes, sha256}` der Android-App, 404 ohne |
| food | GET | `/api/app/android/apk` | die APK |
| food | GET | `/setup?token=` | setzt `health_token` (nie `fh_private`) |
| weight | PUT | `/api/weight/height` | `{heightCm}` (100–250) → `WeightSummary` |
| weight | GET | `/setup?token=` | alter Token → `weight_app_token` wie bisher; persönlicher → `health_token` |

⚠️ **`WeightSummary` hat `heightCm`** — für Felix `194` als Vorgabe
(`weight.owner-height-cm`), solange nichts gespeichert ist. Die iOS-App rechnet
den BMI weiter mit ihrem festen `WeightWidget.heightM`; beides ergibt für Felix
dieselbe Zahl.

⚠️ **Eine neue Person hat kein Vorhaben**, bis sie ein Ziel setzt: dann sind
`target`, `targetDate`, `goalWeight`, `startWeight`, `recordingStart`, die
Korridorfelder und `residual7` `null`, in den Reihen `target` überall `null`.
Ohne jede Messung liefern die Reihen `[]` und `summary` ein Objekt aus lauter
`null` (vorher: leerer Rumpf). `PUT /api/weight/target` startet das Vorhaben
**heute** mit der jüngsten Messung; ohne Messung **409**.

⚠️ **Detailwerte je Person** (`FOOD_DETAILED_NUTRIENTS`, für Torben): `Nutrients`
hat vier **optionale** Felder `saturatedFatG`, `sugarG`, `fiberG`, `saltG` (die
übrigen Zeilen der EU-Nährwerttabelle, je 100 g bzw. als Tagessumme). Sie fehlen
im JSON, wo sie nicht gesetzt sind — Felix' Tagebuch hat sie nie, die iPhone-App
sieht also nichts Neues. `DishRequest` nimmt sie freiwillig mit (0–100);
`DaySummary.detailGaps` nennt die Felder, bei denen ein Eintrag des Tages keine
Angabe hat (die Summe ist dort eine Untergrenze), und fehlt, wenn es keine Lücke
gibt. Für Detailwerte gibt es kein Ziel und keinen Rest. Die Schnellerfassung
liefert sie nur für diese Personen, mit Herkunft in `valueSources`.

⚠️ **Mikronährstoffe je Person** (`FOOD_MICRONUTRIENTS`, für Torben, seit
2026-09-29): `Nutrients` hat ein **optionales** Objekt `micros` mit 14 Schlüsseln,
die Einheit steckt im Namen — `vitaminAUg`, `vitaminDUg`, `vitaminEMg`,
`vitaminCMg`, `vitaminB2Mg`, `vitaminB12Ug`, `folateUg`, `calciumMg`,
`magnesiumMg`, `potassiumMg`, `ironMg`, `zincMg`, `iodineUg`, `seleniumUg`
(Vitamin A als Retinol-Aktivitäts-, Folat als Folat-Äquivalente). Ein fehlender
Schlüssel heißt „keine Angabe", nie 0; leer fehlt `micros` ganz — Felix' JSON
ist unverändert. Anders als die Detailwerte haben sie **Tagesziele**:
`targets.micros`, vorbelegt mit den DGE-Referenzwerten für Männer 25 bis unter
51 Jahre (Vitamin E 8 mg, Eisen 11 mg, Jod 150 µg, Zink 16 mg für hohe
Phytatzufuhr …, Quelle `Micronutrient.java` im Dienst), solange die Person
nie eigene gespeichert hat. `PUT /targets` nimmt `micros` (jeder Wert > 0, ein
fehlender Schlüssel = kein Ziel); fehlt `micros` im Rumpf ganz, bleiben die
gespeicherten stehen. `remaining` hat nie `micros`. `DaySummary.microGaps` wie
`detailGaps`. `DishRequest.micros` je 100 g, höchstens das Gegenstück von 10 g
(10 000 mg bzw. 10 000 000 µg); **PUT eines Gerichts ersetzt es ganz**, wer
`micros` hat, schickt sie mit. Für alle anderen wird `micros` ignoriert. Die
Schnellerfassung schätzt sie mit (Herkunft in `valueSources` unter dem
Mikro-Schlüssel). Die iPhone-App braucht nichts davon — nur Torben nutzt es,
über Web und Android.

⚠️ **Veganer Modus je Person** (seit 2026-09-29, Torbens Wunsch): `features.veganMode`
(immer da, Vorgabe `false`); `PUT /api/food/vegan-mode {enabled}` antwortet mit den
neuen Features. Beim **ersten** Einschalten werden alle Gerichte mit unbekanntem
Kennzeichen vegan. Gerichte, `DishRequest` und der Vorschlag der Schnellerfassung
tragen optional `vegan` (fehlt = unbekannt, Herkunft in `valueSources.vegan`);
`PUT /dishes/{id}` ersetzt ganz. Im Modus lehnt der Dienst Einträge nicht-veganer
Gerichte und neue Gerichte mit `vegan:false` mit 400 ab. Wer den Modus nie
einschaltet (Felix, iPhone-App), bekommt alles wie bisher. Außerdem:
`DELETE /feature-requests/api/requests/{id}` (nur Eigentümerin) löscht eine
Anfrage samt Unteraufgabe im To-Do.

⚠️ **Schnellerfassung je Person:** ohne Freischaltung antwortet
`POST /quick-capture` mit 403, der Auftrag einer anderen Person ist 404, und die
Benachrichtigung geht nur an die Geräte dessen, der ihn gestartet hat — iPhones
über APNs, Android über Firebase (reine Datennachricht
`{kind: "quick-capture", jobId, status, title, body}`; bei neuer Android-Version
`{kind: "app-update", versionCode, versionName, title, body}`).

## Datumsformate (der häufigste Stolperstein)

Spring serialisiert `LocalDate` als `"2026-09-01"` und `Instant` als
`"2026-09-01T08:15:30.123Z"`. **In derselben Antwort** (`FoodEntry` hat beides).
Ein `JSONDecoder` mit `.iso8601` scheitert am reinen Datum. Deshalb die
`.custom`-Strategie im `APIClient`, die beides probiert — nicht "wegoptimieren".

## Weight Tracker — `/api/weight`

| Methode | Pfad | Antwort |
|---|---|---|
| GET | `/api/weight/last90` | `[WeightPoint]` |
| GET | `/api/weight/last180` | `[WeightPoint]` — wie `last90`, rollierend 180 Tage (seit 2026-10-03; ein älterer Dienst antwortet 404) |
| GET | `/api/weight/year` | `[WeightPoint]` |
| GET | `/api/weight/month` | `[WeightPoint]` |
| GET | `/api/weight/all-time` | `[WeightPoint]` |
| GET | `/api/weight/highlights` | `[Highlight]` — Zeiträume (`band`) und Linien (`line`), nach `start` sortiert |
| POST | `/api/weight/highlights` | Body `{kind, start, end?, label?, color?}` → die **ganze** Liste (201); die Id vergibt der Dienst |
| DELETE | `/api/weight/highlights/{id}` | → die verbleibende Liste; 404 bei unbekannter Id |
| GET | `/api/weight/vacations` | **veraltet**, Alias für `/highlights` — bleibt, bis jedes Gerät einen Build mit dem neuen Pfad hat |
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
               corridorLower?, corridorUpper?, corridorReachedOn?,
               residual7?, residual7Days
Highlight      id, kind ("band" | "line"), start, end, label?, color ("#rrggbb")
               bei "line" ist end gleich start; color ist immer gesetzt (Vorgabe #7c9cfa)
```
```
StepDay   date, steps        (beides Pflicht, `steps` >= 0)
```

`residual7` ist das Mittel aus **Messwert minus Target je Tag** über die sieben
Kalendertage bis `date` — nicht `avg7` gegen das heutige Target, das hinkt am
aktuellen Rand nach. `residual7Days` sagt, wie viele dieser Tage gemessen waren;
Tage ohne Messung und Tage vor `recordingStart` zählen nicht. Beides seit
2026-09-17; ein älterer Dienst liefert die Felder nicht, deshalb decodiert die
App sie optional (`WeightSummary.residual7`).

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
| GET | `/api/food/daily-average?from=…&to=…` | `[DayAverage]` — gleitendes 7-Tage-Mittel der kcal je Tag (seit 2026-09-20) |
| GET | `/api/food/dishes` | `[Dish]` |
| POST | `/api/food/dishes` | Body `DishRequest` → `Dish` |
| PUT | `/api/food/dishes/{id}` | Body `DishRequest` → `Dish` |
| DELETE | `/api/food/dishes/{id}` | 204 |
| POST | `/api/food/entries` | Body `NewEntryRequest` → `DaySummary` |
| DELETE | `/api/food/entries/{id}` | `DaySummary` |
| PUT | `/api/food/entries/{id}` | `{grams, meal?, date?}` — Menge, Mahlzeit, Tag berichtigen; das Gericht bleibt. Antwort: der Tag, auf dem der Eintrag danach liegt — bei einem Tagwechsel also **nicht** der angezeigte |
| GET/PUT | `/api/food/targets` | `Nutrients` / Body `TargetsRequest` |
| GET | `/api/food/features` | `{quickCapture: Bool}` |
| POST | `/api/food/quick-capture` | Body `{date, text, meal, imageJpegBase64?}` → `QuickCaptureJob`; mit Foto darf `text` leer sein (Kontext) |
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
DayAverage     date, kcal, days, complete   (zentriertes 7-Tage-Fenster, nur abgeschlossene Tage
               mit Eintrag - heute und vorerfasste kuenftige Tage zaehlen nicht;
               complete = false, solange das Fenster bis heute oder darueber hinaus reicht)
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

⚠️ **Foto in der Schnellerfassung** (seit 2026-09-23): `imageJpegBase64` ist
ein JPEG als Base64 ohne Präfix (`MealPhoto.base64`, 1280 px lange Kante,
unter 700 kB — nginx lässt 1 MB durch). Der Dienst legt es als
`data/inbox/<auftrag>.jpg` ab, der Agent liest genau diese Datei, danach ist
sie weg. Werte aus dem Bild kommen als `estimated` zurück.

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

⚠️ **Fehlerantworten tragen ihre Begründung im Rumpf** — beim Kalorienzähler
und Weight Tracker erst seit 2026-09-26 wirklich: Spring Boot ließ das Feld
`message` per Vorgabe weg, die Clients sahen nur „Bad Request". Jetzt steht
`spring.web.error.include-message=always` in beiden Diensten (in Spring Boot 4
heißt es so; das alte `server.error.include-message` wirkt nicht mehr).
`APIClient` reicht die Begründung durch (`APIError.http(Int, String?)`), weil
„HTTP 400" die schlechtere von beiden Meldungen ist.

### Open Food Facts — externe Quelle für den Barcode-Scanner (seit 2026-09-21)

Kein eigener Dienst: die App fragt Open Food Facts **direkt** (Begründung in
`ENTSCHEIDUNGEN.md`), der Kalorienzähler bekommt erst das fertige Gericht
über `POST /api/food/entries` mit `dish`.

```
GET https://world.openfoodfacts.org/api/v2/product/<code>.json
    ?fields=product_name,brands,quantity,serving_size,nutriments
User-Agent: Cockpit-iOS/0.2 (private, non-commercial)     (Pflicht laut OFF; sonst nichts - keine Cookies, keine Kennung)
```

```
gefunden       HTTP 200  {"code":"4000417025005","status":1,"status_verbose":"product found",
                          "product":{"product_name":"…","brands":"Ritter Sport","quantity":"100g",
                                     "serving_size":"1 Cube (6.52 g)","nutriments":{…}}}
nicht gefunden HTTP 404  {"code":"…","status":0,"status_verbose":"product not found"}
```

Gelesen wird (`OpenFoodFactsParser`): `product_name`; `brands` (Liste mit
Komma, nur der erste Name); `nutriments["energy-kcal_100g"]`, ersatzweise
`energy_100g` (immer kJ) / 4,184; `proteins_100g`, `carbohydrates_100g`,
`fat_100g`; die Portion in Gramm aus `serving_size`, ersatzweise `quantity`
(erste Zahl mit `g`/`ml` irgendwo im Text — `1 Cube (6.52 g)` → 6,52,
`6 x 125 g` → 125, `1 l` → nichts).

⚠️ **Zahlen kommen mal als Zahl, mal als String** (`"proteins_100g":"1.1"`),
je nachdem, wer den Eintrag angelegt hat — der Parser nimmt beides. Fehlende
Nährwerte bleiben `nil` und im Blatt leer; eine Null wäre eine Behauptung.

⚠️ **`status` sagt es doppelt:** ein unbekannter Code kommt als 404 **mit**
JSON-Rumpf; die App wertet 404 wie 200 aus und liest `status`. Alles andere
außerhalb von 2xx ist ein Fehler („Open Food Facts hat mit 503 geantwortet.").

⚠️ **Codes normalisiert OFF selbst** (eine GTIN-14 `04000417025005` liefert
das Produkt `4000417025005`); die App schneidet die führende 0 trotzdem vorher
ab (`ProductCode`), damit „Nicht in der Datenbank: <code>" und der
Namensabgleich mit der Merkliste denselben Code sehen.

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

## coHabit — `/cohabit/api`

Quelle: `../habits`, Branch `cohabit` (Controller unter
`src/main/java/com/fherrmann/habits/cohabit/`, Antwortformen in
`cohabit/api/*.java`), verbindlich beschrieben im Vertrag
`../habits/docs/COHABIT-CONTRACT.md` §3. Stand 2026-09-30: **nicht ausgerollt** —
bis `update-habits.sh` und `setup-cohabit.sh` gelaufen sind, gibt es
`fherrmann.com/cohabit/` nicht.

**Zugang:** `Authorization: Bearer <token>` — ein App-Token (im Profil unter
„App verbinden" erzeugt, `https://fherrmann.com/cohabit/setup?token=<48 hex>`),
ein Healthy-Token (`HEALTH_TOKENS`, Link `food.fherrmann.com/setup?token=…`)
oder der, den `POST /invite-links/{code}/accept` einer neuen Person ausstellt.
Der Dienst nimmt auch `fh_private` (als Bearer oder Cookie = Felix) — die
coHabit-App schickt ihn nie; nur der Wald in Fokus fragt so nach seinem
Tagesziel (`FocusGoal`, liest `GET /cohabits` und `/cohabits/{id}`).

**Fehler kommen sauber:** 401 ohne gültige Anmeldung, sonst Status plus
`{"message":"Klartext auf Deutsch"}` (400, 403, 404, 409, 410, 413, 429). Die App
zeigt `message` (`CohabitAPI.message`), bei einer HTML-Seite (nginx) einen Satz
mit dem Status.

| Methode | Pfad | Was die App damit macht |
|---|---|---|
| GET | `/me` · PUT `/me` · PUT/DELETE `/me/avatar` | Anmeldung prüfen, Profil, Profilbild (multipart `photo`, quadratisch von der App) |
| GET/PUT | `/me/notifications` | globale Schalter |
| GET/POST/DELETE | `/me/app-links[/{id}]` | „App verbinden"; `DELETE /me/app-links/current` beim Abmelden |
| GET | `/me/export` | ZIP → Teilen |
| DELETE | `/me` | `{"confirm":"LÖSCHEN"}` |
| GET | `/today` | „Heute" (Dashboard und Liste) |
| GET/POST/PUT/DELETE | `/classic/habits[/{id}[/marks[/{date}]]]` | „Heute" als klassische Liste (Schalter im Profil) - siehe unten |
| GET/POST | `/cohabits` | Liste (Timeline-Filter), Anlegen mit `invitePersonIds` |
| GET/PUT/DELETE | `/cohabits/{id}` | Detail, Bearbeiten (ohne Typwechsel), Löschen `{"confirm":true}` |
| POST | `/cohabits/{id}/archive` · `/unarchive` | Admin |
| GET/POST | `/cohabits/{id}/invite-candidates` · `/invitations` · `/invite-link` | Einladen |
| DELETE · PUT | `/cohabits/{id}/members/{personId\|me}` · `/admin` | Mitglieder, Verlassen, Admin übertragen |
| PUT | `/cohabits/{id}/settings/me` | Stumm, Check-ins/Chat (`null` = wie global), Unterbrechungen teilen, Health-Einwilligung |
| POST/DELETE | `/cohabits/{id}/pauses[/{pauseId}]` | Pausen (Streak) |
| POST/PUT/DELETE | `/cohabits/{id}/checkins[/{checkinId}]` | Abhaken, eigene Einträge bearbeiten/löschen; bis zu vier Fotos (`photoIds`), bei Laufpunkten mit `durationMinutes`/`distanceKm` (siehe unten) |
| PUT | `/cohabits/{id}/health/{date}` | `{"value"}` — ein Tageswert aus Health; nicht bei `KCAL` (400 „Die kcal kommen aus Healthy.“) |
| GET/POST/DELETE | `/cohabits/{id}/messages[/{id}]` · `/report` · `/read` | Chat; Nachricht mit `gif` (KLIPY) oder eigenem GIF (`photoAnimated`), siehe unten |
| POST · DELETE | `/reactions` · `/reactions?target=…&reaction=…` | `{"target":"event:…\|message:…","reaction":"🔥"}` setzt die **eigene** (eine je Person), DELETE nimmt sie zurück → `{"reactions":[ReactionView]}` (seit 2026-10-05, siehe unten) |
| GET | `/gifs/config` | → `{"enabled":true,"apiKey","customerId","locale","contentFilter"}` bzw. `{"enabled":false}` - Zugang zur GIF-Suche bei KLIPY (seit 2026-10-05) |
| POST | `/cohabits/{id}/nudges` · `/nudges/{id}/seen` | Stupsen, Stupser gesehen |
| POST | `/cohabits/{id}/dialogs/{dialogId}/seen` | Abschlussdialog gesehen |
| GET | `/timeline?exclude=<id>,<id>&before=&limit=30` · POST `/timeline/seen` | Timeline ohne die Co-Habits, die der Filter ausblendet; „neue Beweisfotos" zurücksetzen (siehe unten) |
| GET | `/stats?range=WEEK\|MONTH\|YEAR&anchor=` | Statistik |
| GET | `/widget` | die Kacheln (holen sie selbst) |
| POST | `/photos` · GET `/photos/{id}?size=thumb\|full` | Fotos und eigene GIFs (siehe unten) |
| GET/POST/DELETE | `/friends…` · `/people/search` · `/me/friend-link` · `/blocks…` | Freunde & Einladungen |
| GET/POST | `/invite-links/{code}` · `/accept` | Einladungslink - ohne Zugang mit Anzeigename, Nutzername, `acceptTerms` |
| GET/POST | `/me/invitations` · `/invitations/{id}/accept\|decline` | offene Einladungen |
| POST/DELETE | `/devices[/{token}]` | `{"token","platform":"ios"}` — Push-Kennung |
| GET | `/focus/categories` | → `[{"id","name"}]`: die Kategorien aus dem Wald zur Auswahl für Fokus-Habits; nur für Felix, sonst `[]` (seit 2026-10-01) |

⚠️ **Kennungen vergibt die App** für Einträge und Nachrichten (UUID klein
geschrieben); dieselbe noch einmal liefert das bestehende Objekt. Bei Fotos
vergibt der **Dienst** die Kennung (Antwort von `POST /photos`), wiederholbar
macht das Hochladen der `Idempotency-Key` - er gilt je Person. Darauf baut der
Postausgang (`CohabitOutbox`): nichts entsteht doppelt, auch nicht nach einem
Neustart mitten im Nachsenden.

⚠️ **kcal aus Healthy (seit 2026-10-01, `../habits` Commit `a5288a5`):** die
Health-Metrik `KCAL` (Einheit `KCAL`, Text „kcal“) holt der **Dienst** selbst
aus dem Kalorienzähler (`KcalSync`) - je Mitglied mit `healthConsent` und
Healthy-Zugang (Quelle `FOOD` in `MeView.sources`), gleich nach der Zustimmung
für die ganze Frist, danach alle 15 Minuten heute und gestern. Der Health-Block
im Detail trägt `source`: `DEVICE` (die App liest Apple Health und schickt) oder
`HEALTHY` (KCAL). Zustimmen ohne Quelle `FOOD` → 400 „Dafür braucht es einen
Healthy-Zugang.“, `PUT …/health/{date}` bei KCAL → 400. Die App liest für
`HEALTHY` nichts aus Apple Health, fragt nicht nach einer Erlaubnis
(`CohabitHealthSync.readsFromDevice`) und zeigt statt „Verbinden“ den Schalter
(`HealthyCard`, `PUT …/settings/me {healthConsent}`), gesperrt ohne `FOOD`.

⚠️ **Fokus-Habits nach Kategorie und Zeitraum (seit 2026-10-01, `../habits`
Commit `10536d7`):** `config.auto` hat bei `FOCUS` drei Felder mehr:
`focusCategoryId` (nur Bäume dieser Wald-Kategorie, `null` = alle),
`focusCategoryName` (trägt der **Dienst** aus dem Wald ein und zieht ihn bei
Umbenennung nach - was ein Client schickt, gilt nicht) und `focusPeriod`
(`DAY` Vorgabe, `WEEK` = Summe Mo–So, bis 10.080 Minuten, Streak dann in Wochen
wie bei den Schritten). Eine Kategorie, die nicht zur Auswahl steht → 400
„Unbekannte Kategorie.“; eine inzwischen gelöschte darf ein bestehendes
Co-Habit behalten. ⚠️ Beim Bearbeiten liest der Dienst ein fehlendes Feld als
`null` - die App schickt `focusCategoryId` und `focusPeriod` deshalb immer
(`CohabitConfig.Auto.encode`), den Namen nie. Typzeile und Regel kommen fertig
(„Streak · 60 Min. Bachelorarbeit täglich“, „Automatisch: 240 Min.
Bachelorarbeit/Woche“). Das Formular zeigt Zeitraum, Minuten (je Tag 15 bis
960 in Viertelstunden wie bisher, je Woche 60 bis 10.080 in Stunden) und die
Kategorie als Chips („Alle Bäume“ + `GET /focus/categories`, eine gelöschte des
Habits bleibt wählbar, `FocusCategoryChoices`).

⚠️ **Kalorienziel im Wochenmittel (seit 2026-10-01, `../habits` Commit
`f0f69c6`):** Quelle `FOOD_TARGET_WEEKLY` in `MeView.sources` für alle mit
Healthy-Zugang (Reihenfolge FOOD, FOOD_TARGET_WEEKLY, STEPS_WEEKLY, FOCUS). Eine
Woche zählt, wenn der Schnitt der getrackten Tage höchstens beim kcal-Ziel
liegt; entschieden wird nach Sonntag (Status `RUNNING`, `listLine` „Ø 2.250 von
2.300 kcal“, darunter „bisher im Ziel“/„bisher über dem Ziel“). Keine eigenen
Ziele - im Formular nur der Chip „Kalorienziel im Wochenmittel“, Rhythmus
einmal pro Woche (setzt der Dienst ohnehin). Quellen sind in der App Text, kein
Enum: eine unbekannte steht mit ihrem Namen da und kippt nichts.

⚠️ **Mehrere Beweisfotos (seit 2026-10-03, `../habits` Commit `0cf85ed`, Vertrag §2.3a):** ein Eintrag trägt
bis zu vier. `POST …/checkins` mit `"photoIds":[…]` (1–4, Reihenfolge =
Anzeige; 400 „Höchstens 4 Fotos.“ / „Ein Foto ist doppelt.“), das erste wird
`photoId` - die App schickt es zusätzlich einzeln, ein älterer Dienst versteht
so wenigstens das. `PUT …/checkins/{id}`: `photoIds` fehlt oder `null` =
unverändert, eine Liste (0–4) = der neue Satz; weggefallene löscht der Dienst,
neue müssen vorher über `POST /photos` hoch; bei Foto-Pflicht bleibt eins (400
„Ein Beweisfoto ist Pflicht.“). Bekommt ein Eintrag ohne Foto seine ersten,
entsteht der Chat-Post (ohne Push), fallen alle weg, verschwindet er. Antworten:
`Checkin.photoIds`, `Message.photoIds` (Check-in-Post: alle des Eintrags,
Foto-Nachricht: das eine, sonst `[]`) und `TimelineItem.photoIds` - immer eine
Liste; die App liest sie optional und fällt auf `photoId` zurück (`photos`,
`PhotoList`). Push ohne Caption: „Neues Beweisfoto“ / „3 neue Beweisfotos“.
⚠️ **Postausgang:** jedes Foto eines wartenden Eintrags ist eine eigene Datei
(`photoFiles`, Dateiname = Idempotenz-Schlüssel), sie gehen der Reihe nach hoch
und hängen sich an `photoIds`; ein Abbruch mittendrin lädt nichts doppelt.
Aufträge der Fassung mit einem Foto (`photoFile`) gehen weiter raus.

⚠️ **Laufpunkte (seit 2026-10-03, `../habits` Commit `259bec7`, Vertrag
§2.6a):** Challenge-Wertung `RUN_POINTS` - Punkte je Lauf aus Dauer und
Distanz, gerechnet nur im Dienst (bei jedem Abruf neu). `config.challenge.run`
= `{"basePoints":10,"pointsPerKm":1,"minutesPerPoint":6,"baseMinMinutes":20,
"paceLimitSeconds":480}` (die Vorgaben; ein fehlendes Feld bekommt sie, auch in
der App, `RunScoring`), bei anderen Wertungen `null`. Der Dienst erzwingt
`tracking: CHECK` und lehnt `health` ab (400 „Laufpunkte trägt man von Hand
ein.“); Wertung und `run` einer laufenden Runde sind nicht änderbar (400 „Die
Wertung einer laufenden Runde lässt sich nicht ändern.“). Die App schickt `run`
bei `RUN_POINTS` immer ausgeschrieben, sonst `null`; `scoring` bleibt in der App
Text (`ChallengeScoring`). `CohabitSummary.runEntry: true` heißt: das
Eintragsblatt fragt Dauer und Distanz (`valueUnit` ist dann `null`,
`checkInLabel` „Lauf eintragen“, in `/widget` `quickCheckIn: false`) - fehlt
das Feld (älterer Dienst), dekodiert die App `nil`. `POST …/checkins` braucht
dann `"durationMinutes"` (1–1440) und `"distanceKm"` (0,01–500, der Dienst
rundet auf zwei Stellen); eine Ø-Pace, die nicht schneller ist als die Grenze,
lehnt er ab, ohne etwas zu speichern (400 „Ø-Pace 8:30 min/km – zählt nur unter
8:00 min/km.“). `PUT …/checkins/{id}`: `null` heißt „unverändert“, die App
schickt beim Bearbeiten eines Laufs beide Werte. `Checkin.run` =
`{"durationMinutes","distanceKm","paceText","points","pointsText","breakdownText"}`
oder `null` (die App dekodiert jedes Feld optional), `valueText` eines Laufs
„5,8 km · 35 Min. · 6:02 min/km · +20 P“; Timeline-Titel „… ist 5,8 km in 35
Min. gelaufen · +20 P“. ⚠️ Ohne Netz geht ein Lauf in den Postausgang wie jeder
Eintrag; lehnt der Dienst ihn beim Nachsenden ab, fliegt er raus und die Leiste
nennt ihn („Lauf 4,1 km in 35 Min. nicht angenommen: …“).

⚠️ **Timeline-Filter (seit 2026-10-01, `../habits` Commit `c536f66`):**
`exclude` nimmt die Co-Habits, die der Filter ausblendet - kommagetrennt oder
mehrfach, unbekannte Kennungen stören nicht, `before` blättert auch gefiltert.
Ausblenden statt auswählen, damit neue Co-Habits von selbst erscheinen;
`cohabitId` (genau eines) gibt es im Dienst weiter, die App schickt es nicht
mehr. Die App schickt nur die ausgeblendeten unter den aktiven (`GET /cohabits`)
und sortiert sie (dieselbe Auswahl, dieselbe Adresse im `OfflineCache`); ist
alles ausgeblendet, fragt sie gar nicht. `POST /timeline/seen {lastEventId}`
setzt „neue Beweisfotos" auf „Heute" zurück - der Dienst zählt die Fotos der
anderen nach diesem Ereignis, **ohne den Filter zu kennen**. Gefiltert meldet
die App deshalb das neueste Ereignis überhaupt (`GET /timeline?limit=1` ohne
`exclude`), ungefiltert wie bisher das oberste der Liste.

⚠️ **Typ, Quelle, Anlegedatum (seit 2026-10-05, `../habits` Branch
`today-types`, Commit `bdac077`):** `CohabitRef` trägt zusätzlich
`"autoSource"` (`null` bei manuellen, sonst die Quelle wie `auto.source`:
`FOOD`, `FOOD_TARGET_WEEKLY`, `STEPS_WEEKLY`, `FOCUS`, `EVALUATION` - eine
unbekannte gilt als automatisch) und `"createdAt"` (ISO-Zeitpunkt). Damit ordnet
„Heute" nach Typ wie die klassische Liste und färbt nach Typ
(`CohabitShared/CohabitKinds.swift`); `color` liest die App als `storedColor`
und zeigt es nicht mehr, schickt beim Anlegen aber die Typfarbe mit. Ein älterer
Dienst schickt beide Felder nicht: dann gilt alles als manuell und innerhalb
der Gruppe zählt der Name. `CohabitSummary.progress` gibt es jetzt auch bei
**CHALLENGE** (laufend oder beendet, vor dem Start `null`): der eigene Stand
gegen `target` bzw. ohne Zielwert gegen den Führenden (wer führt, hat 1).
Wie bisher: GOAL Summe gegen Ziel, automatisch STEPS_WEEKLY Schritte der Woche
gegen das Wochenziel, FOCUS Minuten gegen das Ziel (Tag oder Woche).

⚠️ **Fotos:** `POST /photos` als `multipart/form-data`, Feld `photo`, JPEG
(oder PNG, GIF), höchstens 10 MB, Kopfzeile `Idempotency-Key: <uuid>` →
`{"id","width","height","animated"}`; danach steht die `id` im Eintrag oder in
der Nachricht. `GET /photos/{id}` ohne `size` liefert `full`. Der Dienst dreht
**nicht** nach EXIF — die App zeichnet das Bild aufrecht neu (≤ 2048 px, JPEG
0,85, `PhotoEncoding`). Abrufen nur mit Token (`PhotoLoader`, kein
`AsyncImage`); Fotos ändern sich nie und bleiben im Cache.

⚠️ **Eigene GIFs (seit 2026-10-05, Vertrag §2.7a, `../habits` Commit `49c9a6b`):**
ein GIF mit mehr als einem Bild legt der Dienst **unverändert** ab (nur
Kommentare und fremde Application-Extensions fliegen raus) → `"animated":true`;
`size=full` liefert dann `image/gif`, `size=thumb` das erste Bild als JPEG.
Grenzen: 10 MB, 2048 px je Kante (400 „Das GIF ist zu groß (höchstens 2048 px).“),
Breite × Höhe × Bilder ≤ 120 Mio. („Das GIF hat zu viele Bilder.“). Ein GIF mit
einem Bild ist ein gewöhnliches Foto. Animiert geht es **nur** in eine
Chat-Nachricht: die bleibt `kind: PHOTO` mit `photoAnimated: true`, als
Beweisfoto 400 „Ein GIF ist kein Beweisfoto.“. Die App erkennt ein GIF am
Dateianfang (`GIF8`, `ImageFormat.sniff`) und schickt es als `photo.gif`/
`image/gif`, alles andere als JPEG - auch aus dem Postausgang, dessen Datei
dafür `.gif` heißt.

⚠️ **GIFs aus der Suche (KLIPY, seit 2026-10-05):** `GET /gifs/config` liefert
Schlüssel, `customerId` (zufällig, stabil je Person), `locale`, `contentFilter`;
ohne `KLIPY_API_KEY` auf dem Server `{"enabled":false}` - dann kein GIF-Knopf.
Gesucht wird **direkt vom Gerät** bei `https://api.klipy.com/api/v1/{key}/gifs/trending`
bzw. `…/search?q=` (immer `page`, `per_page=24`, `customer_id`, `locale`,
`content_filter`), nach dem Senden `POST …/gifs/share/{slug}` mit
`{"customer_id","q"}` - KLIPYs Bedingung, kein Umweg über den Dienst
(`KlipyClient`). Antwort `{"result","data":{"data":[Item],"current_page","has_next"}}`,
`Item.id` ist eine **Zahl**, `file.{hd|md|sm|xs}.{gif|webp|jpg|mp4|webm}` mit
`url`, `width`, `height`. Gesendet wird `POST …/messages` mit
`"gif":{"slug","title","width","height","gifUrl","webpUrl","mp4Url","stillUrl"}`
aus `md` (sonst `hd`, `sm`); der Dienst prüft jede URL auf
`^https://static[0-9]*\.klipy\.com/` (sonst 400 „Das GIF ist ungültig.“) und
liefert `kind: "GIF"` mit `gif` (dieselben Felder plus `"provider":"KLIPY"`).
Medien von KLIPY nur im Speicher und im HTTP-Cache (`KlipyMedia`), nie als
eigene Datei. Ohne echten Schlüssel (überall außer auf dem Server) antwortet
KLIPY nicht: `tools/klipy-stub.py` spielt KLIPY für Simulator und UI-Tests
(`COCKPIT_URL_KLIPY=http://127.0.0.1:48793/api/v1`), ein lokaler Dienst mit
`KLIPY_API_KEY=irgendwas` meldet `enabled:true`.

⚠️ **Emoji-Reaktionen (seit 2026-10-05):** `ReactionView` ist
`{"reaction":"💪","label":"💪","count","mine","people":[PersonView]}`, nach
`count` absteigend. Je Person **eine** Reaktion je Ziel: `POST` setzt (ersetzt
das eigene alte Emoji), `DELETE …?reaction=` nimmt zurück - ist die eigene
inzwischen eine andere, bleibt sie. Kein Emoji → 400 „Das ist kein Emoji.“. Die
alten Namen (`STARK` → 💪, `RESPEKT` → 🙌, `WEITER_SO` → 🔥, `HAHA` → 😂) nimmt
der Dienst weiter an und deutet gespeicherte um; die App liest sie genauso
(`Emoji.fromService`), damit ein alter Postausgang-Auftrag oder ein älterer
Dienst nichts kippt. Sie schreibt Emojis wie der Dienst (ohne U+FE0E, ❤ → ❤️).

⚠️ **Leere Felder schickt die App als `null`**, nicht weggelassen
(`CohabitConfig`, `MySettings`, `CheckinRequest`, `CheckinUpdate`) — beim Bearbeiten hieße ein
fehlender Schlüssel sonst womöglich „nicht ändern".

⚠️ **Tage** (`yyyy-MM-dd`) gelten in der Zone des Co-Habits, nicht des Geräts;
ohne Netz abgelegte Haken bekommen deshalb ein ausdrückliches Datum in dieser
Zone (die App merkt sich die Zone je Co-Habit in der App-Gruppe).

⚠️ **Wo das Backend vom Vertrag abweicht** (../habits/docs/COHABIT-CONTRACT.md, Anhang,
für die Clients verbindlich):
- `FinishedDialog.reactionTarget` (`message:<id>`) nennt die Systemmeldung zum
  Ende - „Gratulieren" setzt dort 💪 (bis 05.10. „Stark"); `kind` ist `CHALLENGE` oder `GOAL`.
  Die App dekodiert `reactionTarget` optional.
- Mitglieder im Detail haben `state` `ACTIVE`, `INVITED` (`joinedAt: null`)
  oder `PAUSED`; `DELETE …/members/{id}` auf eine eingeladene Person zieht die
  Einladung zurück.
- Ein Health-Wert ≤ 0 in `PUT …/health/{date}` löscht den Health-Eintrag des
  Tages - die App schickt 0, wenn ein Tag in Health leer geworden ist, für den
  sie schon einen Wert geschickt hatte. Ein manueller STREAK-Eintrag an einem
  Tag mit Health-Eintrag ist ein 409.
- „Zurückstupsen" geht immer, auch wenn der Absender heute schon fertig ist.
- `POST /friends/requests` antwortet 200, nicht 201; `fulfillmentRate` der
  Statistik ist 0 statt null, wenn nichts fällig war.
- `typeLine` hat die Form „Streak · 3× pro Woche"; die Zeile oben auf den
  Dashboard-Karten („Laufen · Streak") setzt die App selbst zusammen.

**Push** (Vertrag §4): APNs mit Topic `com.fherrmann.cohabit`, Sandbox; die
Nutzlast trägt `kind` und `link` (`cohabit://…`), die App folgt dem Link. Gehört
ein Bild dazu (`photo`, einzelne `chat`-Meldungen), stehen daneben `photoId`
bzw. `imageUrl` (KLIPY-GIF) und `imageStillUrl`, und `aps.mutable-content` ist 1:
dann lädt die Erweiterung `coHabitNotifications` das Bild (Foto mit Bearer
`GET /photos/{id}?size=full`, GIF ohne Token direkt von `static*.klipy.com`) und
hängt es an. `simctl push` startet die Erweiterung **nicht** (die Meldung wird
direkt zugestellt) - prüfen lässt sie sich nur auf dem Gerät.

### Klassische Liste — `/cohabit/api/classic/habits` (seit 2026-09-30)

Quelle: `../habits` Commit `4acd5a7` (`cohabit/web/ClassicController.java`,
`cohabit/service/ClassicService.java`, `cohabit/api/ClassicHabit.java`),
Vertrag §3.10. Für den Schalter „Klassische Liste" im Profil: die alte
Habit-Liste der Fokus-App, gespeist aus coHabit. Zugang und Fehler wie alle
coHabit-Aufrufe (Bearer, 4xx mit `{"message"}`); die App spricht es über
`ClassicAPI` (`coHabit/Classic/`).

| Methode | Pfad | Rumpf → Antwort |
|---|---|---|
| GET | `/classic/habits` | → `[ClassicHabit]`: **alle** aktiven Co-Habits der Person, **auch geteilte**, seit 2026-10-01 (`../habits` `21f20d8`) auch Ziele und Challenges, in Anlegereihenfolge — sortiert (`classicOrder`) wird in der App |
| POST | `/classic/habits` | `{"name","kind","weeklyStepGoal","focusMinutesGoal","period","timesPerPeriod"}` (das alte `HabitDraft`, `kind` BUILD\|QUIT\|FOOD\|STEPS\|FOCUS), bei FOCUS dazu `"focusCategoryId"` und `"focusPeriod":"DAY\|WEEK"` (seit 2026-10-01) → 201 `ClassicHabit`; allein, Europe/Berlin, Nachtragsfrist 336 h; fremde Quelle → 403 „Diese Quelle hast du nicht." |
| PUT | `/classic/habits/{id}` | gleicher Rumpf → `ClassicHabit`; nur Admin; andere Art → 400; `period: null` lässt den Rhythmus, wie er ist; Farbe, Erinnerung, Foto-Pflicht, Frist, Health bleiben. Fokus: `focusCategoryId` weglassen = unverändert, `""` = alle Bäume, sonst die Kategorie; `focusPeriod` weglassen = unverändert. Bei Ziel und Challenge 400 „Ziele und Challenges trägst du im Co-Habit ein.“ |
| DELETE | `/classic/habits/{id}` | → 204; allein: löschen, geteilt: **verlassen** (die anderen behalten es) — für jede Art |
| POST | `/classic/habits/{id}/marks` | `{"date":"yyyy-MM-dd","id":"<8–64 Zeichen [A-Za-z0-9-]>"}` → `ClassicHabit`; BUILD = Haken, QUIT = Rückfall; Foto-Pflicht 400, außerhalb der Frist 400, Tag schon erledigt 409, automatisch 403, Ziel/Challenge 400; **dieselbe `id` noch einmal → 200, nichts Neues** |
| DELETE | `/classic/habits/{id}/marks/{date}` | → `ClassicHabit`; nimmt den eigenen Eintrag des Tages zurück, ohne Eintrag unverändert (wiederholbar) |

```
ClassicHabit  das alte HabitStatus: id (= Co-Habit-ID "c-…"), name,
              kind (BUILD|QUIT|FOOD|STEPS|FOCUS|GOAL|CHALLENGE), unit (DAYS|WEEKS|MONTHS|WINDOWS),
              weeklyStepGoal, focusMinutesGoal, period (DAY|WEEK|MONTH|null),
              timesPerPeriod, streak, doneToday, atRisk, progress {value, goal} | null,
              recent [7 × bool, älteste zuerst; leer bei unavailable], unavailable,
              markedDays [letzte 31 Tage; BUILD Haken, QUIT Rückfälle; leer bei automatischen],
              createdAt (Start bzw. eigener Beitritt)
              + photoRequired, shared (mehr als ein Mitglied), admin, backfillFrom,
              summary (nur GOAL/CHALLENGE: das CohabitSummary wie in GET /cohabits, sonst null),
              focus (nur FOCUS: {categoryId, categoryName, period DAY|WEEK}, sonst null; seit 2026-10-01)
```

⚠️ **Fokus-Zeit je Woche** (`focus.period` WEEK): `unit` WEEKS, `progress` die
Minuten der Woche gegen das Ziel, `atRisk` nie - wie die Schritte. Die Zeile
zeigt die Kategorie im Untertitel („3 Tage · Bachelorarbeit“, `subtitleText`).
Der Editor schickt bei Fokus-Zeit `focusCategoryId` immer (`""` für alle Bäume)
und `focusPeriod`; bei den anderen Arten fehlen beide Schlüssel.

⚠️ **Das Kalorienziel im Wochenmittel** (`FOOD_TARGET_WEEKLY`) steht hier als
Art FOOD mit `unit` WEEKS: `progress` ist der Wochenschnitt gegen das Ziel
(die Zeile schreibt „Ø 2.191/2.300 kcal“, `kcalText`), `doneToday` und `atRisk`
sind immer `false`. Der Editor nennt die Art „Kalorienziel im Wochenmittel“;
anlegen lässt sie sich nur in coHabit selbst.

⚠️ **Ziele und Challenges** (seit 2026-10-01): die alten Felder stehen
neutral (`unit` DAYS, `streak` 0, leere Listen, `doneToday` = heute schon
eingetragen, `unavailable` = `summary.unavailableText`) - bis auf `recent`:
die letzten sieben Tage mit eigenem Eintrag (seit `fe93938`, davor `[]`; die
App zeigt die Punkte nur, wenn welche kommen). Was die Zeile sonst zeigt,
steht in `summary` - Kennzahl (`headline.value`: „#1“, „30%“), `listLine`,
`progress` (nur Ziele; Challenges haben einen Platz, keinen Stand),
`canCheckIn`, `valueUnit`, `checkInLabel`. Eingetragen wird nicht über
`…/marks`, sondern wie in der neuen Liste über `POST /cohabits/{id}/checkins`
(`CheckInController`: Wert-Blatt bei `valueUnit`, Beweisfoto bei
`photoRequired`, sonst gleich +1).

⚠️ **`id` ist die Kennung des Co-Habits.** Deshalb gehen Beweisfoto
(`POST /cohabits/{id}/checkins` über das Blatt von coHabit) und Detailseite
(`cohabit://cohabit/{id}`) direkt mit ihr.

⚠️ **`period: null` bei BUILD** heißt: ein Rhythmus, den das alte Formular
nicht kennt (Wochentage, „alle n Tage"). Die App blendet den Rhythmus im
Editor dann aus und schickt `period`/`timesPerPeriod` als `null` — der Dienst
lässt ihn stehen. `unit: WINDOWS` ist „alle n Tage": „n Mal", „noch offen".
Unbekannte Werte von `kind`, `unit` und `period` dekodiert die App nachsichtig
(`ClassicHabit.init(from:)`, Test `ClassicModelTests`).

⚠️ **Foto-Pflicht gilt nur beim Abhaken.** `photoRequired` ist bei QUIT immer
`false`; ein BUILD mit Foto-Pflicht nimmt über `…/marks` keinen Haken (400) —
die App öffnet stattdessen das Beweisfoto-Blatt.

⚠️ **Eigenheiten der alten Antwort bleiben:** `atRisk` ist bei QUIT und bei
den Schritten nie gesetzt, `recent` bei QUIT zählt Tage ohne Rückfall ab dem
Start. `backfillFrom` ist der früheste Tag, den der Dienst noch annimmt — die
App zeigt im Nachtragen-Blatt nur Tage ab `createdAt` **und** ab `backfillFrom`.

⚠️ **Ohne Netz:** Haken und Rücknahme gehen in `CohabitOutbox` (Aufträge
`classicMark` mit der Kennung aus dem ersten Versuch, `classicUnmark`); ein 409
beim Nachsenden eines Hakens heißt „steht schon". Anlegen, Ändern und Löschen
warten nicht, sie enden ohne Netz in „Kein Netz.".

## Habits — `/habits/api/habits` (umgezogen)

Seit coHabit antwortet `/habits/api/habits/**` mit **410** und
`{"message":"Die Habits sind nach coHabit umgezogen: https://fherrmann.com/cohabit/"}`.
Die Habits stehen als Co-Habits in coHabit (Migration im Dienst, Vertrag §7);
Fokus hat keinen Habits-Tab und keine Habits-Kachel mehr. Was folgt, ist der
Stand bis dahin - aufgehoben, weil `habits.json` als Sicherung liegen bleibt.

Quelle: `../habits/src/main/java/com/fherrmann/habits/`. Kein Web-UI — die App
war der einzige Client, deshalb ist die Antwort schon fertig gerechnet
(`HabitStatus`) und die App zählte **nichts** nach.

| Methode | Pfad | Was |
|---|---|---|
| GET | `/api/habits` | alle Habits mit Sträh­ne und Stand von heute |
| POST | `/api/habits` | `{name, kind, weeklyStepGoal?, focusMinutesGoal?, period?, timesPerPeriod?}` → 201 |
| PUT | `/api/habits/{id}` | Name/Wochenziel/Tagesziel/Rhythmus ändern — **nicht** die Art |
| DELETE | `/api/habits/{id}` | löscht samt aller Einträge, kein Archiv |
| POST | `/api/habits/{id}/marks` | `{date?}` — Haken (BUILD) bzw. Rückfall (QUIT), ohne Datum heute |
| DELETE | `/api/habits/{id}/marks/{date}` | Haken bzw. Rückfall zurücknehmen |

```
HabitStatus  id, name, kind (BUILD|QUIT|FOOD|STEPS|FOCUS), unit (DAYS|WEEKS|MONTHS),
             weeklyStepGoal, focusMinutesGoal (nur FOCUS, sonst null),
             period (DAY|WEEK|MONTH, bei BUILD der Rhythmus), timesPerPeriod,
             streak, doneToday, atRisk,
             progress {value, goal} | null, recent [7 × bool, älteste zuerst],
             unavailable (String | null),
             markedDays [yyyy-MM-dd …] (BUILD/QUIT: Tage mit Eintrag, letzte 31 Tage),
             createdAt (yyyy-MM-dd)
```

`markedDays` und `createdAt` decodieren optional (älterer Dienst). Die App
nutzt sie für „Frühere Tage …" (Langdruck auf ein Habit): `POST …/marks {date}`
und `DELETE …/marks/{date}` nehmen jeden Tag ab `createdAt` bis heute.

`focusMinutesGoal`, `period` und `timesPerPeriod` decodieren optional — ein
älterer Dienst kennt die Felder nicht, und die Liste muss trotzdem laden;
ohne `period` gilt täglich.

⚠️ **BUILD mit `period` WEEK/MONTH** („Zeitungsartikel lesen 1× die Woche",
„politisch aktiv 2× im Monat"): abgehakt werden weiter einzelne Tage
(`POST …/marks`), `doneToday` ist der Haken von heute (der Knopf), `progress`
zählt die Haken im laufenden Zeitraum gegen `timesPerPeriod`, `streak` und
`recent` gehen in Wochen (ab Montag) bzw. Monaten (ab dem Ersten), `atRisk`
heisst „dieser Zeitraum noch offen". Die App zeigt „1/2" neben dem Haken.

⚠️ **`atRisk` ist kein Fehler.** Ein Build-Habit, das heute noch nicht
abgehakt ist, hat seine Sträh­ne nicht verloren — erst um Mitternacht. Bis
dahin ist `streak` der Stand von gestern und `atRisk` gesetzt. Die App zeigt
das als blasse Flamme und „heute noch offen". Bei QUIT gibt es das nicht: ein
Rückfall heute ist entschieden, `streak` ist dann 0.

⚠️ **Was `doneToday` bei QUIT heißt:** *kein* Rückfall heute. Der Knopf in
der App trägt dann einen ein (`POST …/marks`); ist einer eingetragen, nimmt
derselbe Knopf ihn zurück (`DELETE …/marks/{heute}`).

⚠️ **Automatische Habits (FOOD, STEPS, FOCUS) nehmen keine Marks** — `POST …/marks`
ist dort ein 400. Ihr Stand kommt bei jeder Anfrage frisch aus dem
Kalorienzähler, dem Weight Tracker bzw. den Fokus-Sessions; `progress` ist kcal
gegen 80 % des Tagesziels, Schritte gegen das Wochenziel (Woche ab Montag 0:00
Europe/Berlin) bzw. Fokus-Minuten des Tages gegen `focusMinutesGoal` (die
App zeigt „2:15/4:00 h"). Ist die Quelle weg, steht `unavailable` und alles
andere ist nicht zu gebrauchen.

### Der Wald — `/habits/api/focus/sessions`

Die Fokus-Sessions der Fokus-App liegen beim Habits-Dienst (`FocusController`,
`data/focus.json`) — derselbe Bestand, aus dem das Co-Habit mit der Quelle
FOCUS in coHabit rechnet. Unverändert seit dem Umzug der Habits (Vertrag §7.3);
die App spricht es über `FocusSessionsAPI` (`Shared/FocusAPI.swift`).

| Methode | Pfad | Was |
|---|---|---|
| POST | `/api/focus/sessions` | `{id, start, end, categoryId?}` → 201; **dieselbe Id noch einmal → 200**, nichts ändert sich; unbekannte Kategorie → 400 „Unbekannte Kategorie.“ (eine inzwischen gelöschte gilt) |
| GET | `/api/focus/sessions?from=&to=` | Sessions, deren `day` im Zeitraum liegt, neueste zuerst |
| GET | `/api/focus/categories` | `[{id, name}]` zur Auswahl, in der Reihenfolge des Anlegens (seit 2026-10-01, `../habits` `10536d7`) |
| POST | `/api/focus/categories` | `{id?, name}` → 201; dieselbe Id noch einmal → 200; Name schon da (ohne Groß/klein) → 409 „Diese Kategorie gibt es schon.“; Name 1–40 Zeichen |
| PUT | `/api/focus/categories/{id}` | `{name}` → `{id, name}`; coHabit zieht den Namen in seinen Fokus-Habits nach |
| DELETE | `/api/focus/categories/{id}` | → 204, nur aus der Auswahl: Bäume und Co-Habits behalten den Namen |

```
FocusSession  id, start, end (Instant, ISO-8601 mit Z), minutes,
              day (yyyy-MM-dd: der Tag des BEGINNS in Europe/Berlin),
              categoryId, categoryName (null bei Bäumen ohne Kategorie - alle vor dem 01.10.2026)
```

⚠️ **Kategorien:** vor dem Pflanzen gewählt (Knopf über „Baum pflanzen“, Blatt
`ForestCategorySheet`), vorbelegt mit der zuletzt benutzten (je Gerät,
`FocusCategoryMemory`). `categoryId` geht mit dem Baum - auch aus dem
Postausgang. Anlegen, Umbenennen und Löschen nur mit Netz und **ohne**
Postausgang: eine offline angelegte Kategorie, die beim Nachsenden scheitert
(Name inzwischen vergeben), nähme jeden Baum mit ihr mit. Ohne Netz bleibt die
Auswahl aus dem `OfflineCache`. Die App schickt keine eigene Kennung beim
Anlegen. Der Wald selbst bleibt, wie er war - keine Farben je Kategorie; die
Tageszeile nennt darunter die Kategorien mit ihren Minuten.

⚠️ **Die Id vergibt die App** (`FocusSessionDraft`), damit ein Nachsenden aus
dem Postausgang keinen zweiten Baum pflanzt — deshalb darf `plant` mit
`queueWhenOffline: true` gehen. Abgelehnt (400) werden unter einer und über
1440 Minuten sowie ein Ende mehr als fünf Minuten in der Zukunft — die 30
Minuten sind die Regel des Rads in der App. Der Testbaum aus dem Menü (20
Sekunden) erreicht den Dienst nie.

⚠️ **`start`/`end` gehen als ISO-Zeitpunkt raus**, nicht als Sekunden seit
2001: `APIClient.encoder()` setzt `.iso8601`, sonst antwortete der Dienst mit
400. `day` rechnet der Dienst, die App nicht — auch nicht für lokal wartende
Bäume, die nimmt sie mit dem Tag des Beginns in der Gerätezeit an.

⚠️ **Fehler kommen als Klartext** (`Ein Habit braucht einen Namen.`), nicht
als JSON-Fehlerseite — `APIClient.shortMessage` reicht sie so durch.

## To-Do — `/todo/api`

Quelle: `../todo/src/main/java/com/fherrmann/todo/`. Anders als Habits hat der
Dienst eine Weboberfläche (Kacheln nebeneinander); die App ist der zweite
Client. **Jede Antwort ist das ganze Brett** — die App ersetzt ihren Stand und
setzt nichts zusammen.

| Methode | Pfad | Was |
|---|---|---|
| GET | `/api/board?all=false` | Bereiche mit sichtbaren Aufgaben; `all=true` auch ältere erledigte |
| POST/PUT/DELETE | `/api/areas[/{id}]` | Bereich anlegen `{name}`, umbenennen, löschen (samt Aufgaben) |
| POST | `/api/todos` | `{areaId, parentId?, title, link?, notification?}` — `parentId` macht eine Unteraufgabe (eine Ebene); `notification` `{title, body}` schickt beim Anlegen einen Push an Fokus (nutzt nur der Kalorienzähler) |
| PUT | `/api/todos/{id}` | `{title, dueAt?}` — ohne `dueAt` gibt es keine Fälligkeit mehr; `link` bleibt, wie er ist |
| POST | `/api/todos/{id}/reminders` | `{at}` als Zeitpunkt **mit Zone** (`ReminderDraft` schreibt ISO mit `Z`), nur Zukunft |
| DELETE | `/api/todos/{id}/reminders/{rid}` | Erinnerung weg |
| POST | `/api/devices` | `{token}` — Push-Kennung von Fokus, für die Erinnerungen |
| POST | `/api/todos/{id}/done` | abhaken — idempotent, der erste Zeitpunkt bleibt |
| DELETE | `/api/todos/{id}/done` | Haken zurück, auch nach dem Verschwinden |
| DELETE | `/api/todos/{id}` | wirklich löschen, samt Unteraufgaben |

```
Board     areas[], includesHidden, hiddenDoneCount, now
AreaView  id, name, position, openCount, hiddenDoneCount, todos[]
TodoView  id, title, link | null, createdAt, doneAt | null, visibleUntil | null,
          dueAt | null (ISO-Datum), reminders[] {id, at, sentAt | null}, children[]
```

⚠️ **Den Link setzt nur das Anlegen** (seit 2026-09-26): Torbens
Feature-Wünsche legt der Kalorienzähler als Unteraufgabe unter „Healthy“
(Bereich Server) an, mit Link auf ihre Wunsch-Seite
(`https://fherrmann.com/feature-requests/<id>`). `link` ist eine absolute
Adresse mit `https://` oder `http://`, höchstens 500 Zeichen, getrimmt; leer
heißt keiner, alles andere ist ein 400 im Klartext. `PUT` lässt ihn stehen —
die App schickt ihn nie mit, und eine Fokus-Version ohne das Feld kann ihn so
nicht löschen. Die App dekodiert ihn nachsichtig (`TodoItem.webLink`): fehlt
er, ist er kein Text oder keine http(s)-Adresse mit Host, ist er `nil`; das
Brett lädt trotzdem. Er steht in jeder `TodoView`, auch als `null`.

⚠️ **Erinnerungen schickt der Dienst**, jede Minute geprüft, als Push an
Fokus (Topic `com.fherrmann.fokus`, Nutzlast `"kind": "todo"`). Die App
meldet ihre Kennung nach dem ersten erfolgreichen Laden des Bretts an. Eine
erledigte Aufgabe erinnert an nichts mehr; eine um mehr als eine Stunde
verpasste Erinnerung ist verpasst.

⚠️ **Feature Requests von anderen kommen ebenfalls als Push** (seit
2026-10-05): der Kalorienzähler gibt beim Anlegen der Unteraufgabe
`notification` mit, das To-Do schickt sie nach dem Speichern, im Hintergrund.
Nutzlast wie bei Erinnerungen plus `"link"` = Link der Aufgabe (die
Kartenseite). Fokus öffnet ihn beim Tipp (`NotificationDelegate.link(in:)`, nur
http(s) mit Host); eine ältere Fokus-Version übergeht ihn und zeigt den
To-Do-Tab.

⚠️ **Erledigtes verschwindet nach drei Tagen, wird aber nicht gelöscht.**
`visibleUntil` sagt, wann; danach fehlt die Aufgabe im Brett, bis `all=true`
oder ein Zurücknehmen des Hakens sie holt. Eine Unteraufgabe hängt am
Schicksal ihrer Aufgabe. Abhaken und Zurücknehmen dürfen offline warten
(`queueWhenOffline`); Anlegen nicht — dafür braucht man die Antwort.

## Einkaufsliste — `/shopping-list/api`

Quelle: `../shopping/src/main/java/com/fherrmann/shopping/`. Eigene Token je
Person (`SHOPPING_TOKENS=felix:…,joana:…` in `/etc/shopping.env`), kein
Privat-Gate. **Jede Antwort ist das ganze Brett.**

| Methode | Pfad | Was |
|---|---|---|
| GET | `/api/board` | `me`, `categories[]` (Reihenfolge = Sortierung), `items[]`, `dishes[]`, `recurring[]` |
| POST | `/api/items` | `{name, quantity?, note?, category?}` — ohne `category` ordnet der Dienst zu |
| PUT | `/api/items/{id}` | dasselbe; mit `category` **lernt** der Dienst den Namen |
| POST / DELETE | `/api/items/{id}/check` | abhaken (idempotent, `checkedBy` = Name zum Token) / wieder öffnen |
| POST | `/api/items/clear-checked` | alle abgehakten sofort weg |
| DELETE | `/api/items/{id}` | löschen |
| POST/PUT/DELETE | `/api/dishes[/{id}]` | `{name, ingredients:[{name, quantity?}]}` |
| POST | `/api/dishes/{id}/add` | alle Zutaten auf die Liste (`dishId`, `note` = Gerichtname); antwortet **201**, 400 bei einem Gericht ohne Zutaten |
| POST/PUT/DELETE | `/api/recurring[/{id}]` | `{name, quantity?, everyDays, nextAt?}` (`yyyy-MM-dd`) |
| GET | `/setup?token=…` | Cookie setzen, Weiterleitung auf die Oberfläche |

```
Board     me, categories[] {key, label, emoji, symbol, color (#RRGGBB)}, items[], dishes[], recurring[]
Item      id, name, quantity? (Text: „500 g", „2 Stk" - siehe ShoppingQuantity), note?,
          addedAt, addedBy, checkedAt?, checkedBy?,
          dishId?, ruleId?, category (Schlüssel, nie leer)
Dish      id, name, ingredients[] {name, quantity?}, createdAt
Rule      id, name, quantity?, everyDays, nextAt (ISO-Datum), createdAt
```

Null-Felder kommen als `null`, nicht weggelassen; Zeitpunkte tragen
Mikrosekunden (`2026-09-04T22:29:08.516444Z`) — `APIClient.parseInstant`
streicht den Bruchteil, bevor `ISO8601DateFormatter` ihn sieht.

Regeln, die der Dienst durchsetzt: **derselbe Name wird ein Eintrag** —
Groß-/Kleinschreibung und Leerraum zählen nicht; Mengen gleicher Einheit
werden addiert („500 g“ + „500 g“ = „1000 g“), verschiedene stehen nebeneinander
(„500 g + 1 Pck“); ein abgehakter Eintrag zählt nicht mehr als „steht schon
drauf“. Gilt für Eingaben, Gerichte und Regeln (eine Regel hängt sich an einen
vorhandenen Eintrag). Offene Einträge stehen in
Kategorie-Reihenfolge (Supermarkt-Rundgang), darin nach `addedAt`; abgehakte
bleiben bis zum Tageswechsel (Europe/Berlin) sichtbar und liegen danach noch
90 Tage in der Datei. Abhaken eines Regel-Eintrags setzt `nextAt` der Regel
auf heute + `everyDays`; der Regel-Lauf (stündlich, beim Start, nach dem
Anlegen) fügt nichts doppelt hinzu, solange ein offener Eintrag der Regel da
ist. Haken, Einträge, Gerichte-auf-die-Liste dürfen offline warten
(`queueWhenOffline`); Gerichte und Regeln pflegen nicht.

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
