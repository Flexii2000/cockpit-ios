# Die drei Backends

Referenz für den Client. **Quelle ist der Java-Code** in `../food` und
`../weight-app` — steht hier etwas anderes als dort, gilt dort.
Stand: 2026-09-01, gelesen aus den Controllern und Records.

## Überblick

| Dienst | Basis | Auth | Für die App |
|---|---|---|---|
| Kalorienzähler | `https://food.fherrmann.com` | Cookie `fh_private` | **nativ** (Phase 2) |
| Weight Tracker | `https://weight.fherrmann.com` | Cookie `weight_app_token` | **nativ** (Phase 1) |
| Finance Cockpit | `https://finanzen.fherrmann.com` | Login: Passwort + TOTP → Session-Cookie | **WebView, dauerhaft** |

Alle drei sind aus dem Internet über HTTPS erreichbar (Let's-Encrypt-Zertifikate,
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
| GET | `/setup?token=…` | setzt das Cookie (braucht die App nicht) |

```
WeightPoint    date, measured?, avg7?, avg14?, avg30?,
               avg7Complete, avg14Complete, avg30Complete, target?
WeightSummary  date, current?, avg7?, avg14?, avg30?, target?, targetDate?,
               goalWeight?, startWeight?, recordingStart?,
               corridorLower?, corridorUpper?, corridorReachedOn?
Vacation       start, end, label
```
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
