# Entscheidungen

Neueste zuerst. Jede mit Datum, Begründung und der verworfenen Alternative —
sonst wird sie in drei Monaten neu diskutiert.

## 2026-09-22 — Essen-Tab: drei Karten im Pager statt einer Wisch-Geste
Der Tag im Essen-Tab ist eine von drei Karten in einem `TabView(.page)`;
Nachbarn liegen vorgeladen daneben. **Warum:** Felix will beim Wischen
sehen, wie die Karten verschoben werden, nicht ein Umblenden am Ende der
Geste. Ein Pager macht das nativ, samt Richtungserkennung gegen das
senkrechte Scrollen und Abbremsen. **Verworfen:** (a) die bisherige
`DragGesture` mit Übergang am Ende (kein Mitziehen, „Blink"); (b) eine eigene
Zieh-Animation über der Liste (zwei Listen übereinander versetzen, Richtung
selbst erkennen, Rand selbst abfedern — alles, was der Pager schon kann).

## 2026-09-22 — Fokus-Modus per Automation und App Intent statt URL-Sprung
Die App bietet die Aktion „Fokus-Restminuten" an; eine Automation „Wenn
Fokus geschlossen wird" holt sie sich und befristet den Fokus-Modus. **Warum:**
Der Sprung in die Kurzbefehle-App beim Pflanzen störte. Eine App kann keinen
Kurzbefehl im Hintergrund starten, eine Automation aber läuft still — ihr
fehlte nur die Endzeit, und die kann ein App Intent liefern. **Verworfen:**
(a) nur der URL-Sprung (bleibt als Rückfall hinter dem Schalter); (b) die
Automation auf „App geöffnet" (läuft dann vor dem Pflanzen).

## 2026-09-21 — Schild auch aus der Erweiterung, Session in einer App-Gruppe
Die Erweiterung `FokusMonitor` legt den Schild beim Start ihres Intervalls
(neu), nicht nur die App beim Pflanzen; laufende Session und erlaubte Apps
liegen dafür in der App-Gruppe `group.com.fherrmann.fokus` (`FocusShared/`).
**Warum:** Ein Neustart des Handys nimmt den Schild weg — Felix hat es so an
der Sperre vorbei geschafft. Das DeviceActivity-Intervall überlebt den
Neustart, und iOS ruft `intervalDidStart` erneut; das ist auch Apples
Muster (Schild in `intervalDidStart`, weg in `intervalDidEnd`). Die
Erweiterung sieht die UserDefaults der App nicht, daher die Gruppe.
**Verworfen:** (a) nur die App beim nächsten Öffnen (bis dahin ist alles
frei — genau die Lücke); (b) Hintergrund-Auffrischung (`BGAppRefreshTask`,
Zeitpunkt nicht steuerbar); (c) die Whitelist in den Store-Namen kodieren
(Stores lassen sich nicht aufzählen).

## 2026-09-21 — Wald in 3D mit SceneKit, aus Grundkörpern statt Modellen
Der Wald ist eine Insel in SceneKit (`ForestScene`), die Bäume aus Kegeln,
Kugeln und Zylindern, je Session eine Pflanzstelle in einer
Sonnenblumen-Spirale. **Warum:** Felix will einen Wald, der „richtig
ausgeschmückt, mindestens 3D" ist. SceneKit läuft in SwiftUI (`SceneView`)
und im Simulator, kennt Schatten, Nebel und Aktionen (der wachsende Baum ist
eine `scale`-Aktion), und ein paar hundert Knoten aus Grundkörpern reichen für
den Low-Poly-Stil — keine USDZ-Dateien im Repo, nichts zu laden. Die Varianz
je Baum kommt aus einem stabilen Hash der Session-Id, damit der Wald bei jedem
Start gleich aussieht. **Verworfen:** (a) RealityKit/`RealityView` (mächtiger,
aber auf Modelle und Materialien ausgelegt; für Kegel und Kugeln nichts
gewonnen, und die Simulator-Unterstützung ist dünner); (b) ein 2D-Wald aus
SF-Symbolen (war der erste Wurf, „noch nicht so schön"); (c) fertige
3D-Modelle (Lizenzfragen, Dateien im Repo, eine Pipeline für einen Baum).

## 2026-09-21 — Kurzbefehl „Fokus an" bekommt Minuten, kein Datum
Die App übergibt dem Kurzbefehl die Restdauer in Minuten („30"), nicht mehr den
Endzeitpunkt als Text. **Warum:** Ein Datum als Text muss der Kurzbefehl erst
lesen — Format, Sprache, Zeitzone —, und beim Testbaum lag die Zeit ohne
Sekunden schon in der Vergangenheit, was „Fokus einschalten bis" als „bis
morgen" nahm. Eine Zahl kennt keinen dieser Fehler; der Kurzbefehl rechnet sie
mit „Datum anpassen" auf das aktuelle Datum. **Verworfen:** (a) ISO-8601-Text
(löst Format und Zeitzone, nicht das Aufrunden und nicht das Lesen); (b) „Fokus
aus" aus der Erweiterung (Erweiterungen können keine Kurzbefehle starten).

## 2026-09-21 — Open Food Facts direkt aus der App, nicht über den Kalorienzähler
Der Barcode-Scanner fragt `world.openfoodfacts.org/api/v2/product/<code>.json`
selbst ab (`OpenFoodFactsAPI`, nur `product_name`, `brands`, `quantity`,
`serving_size`, `nutriments`, User-Agent `Cockpit-iOS/0.2 (private,
non-commercial)`, keine Cookies, keine Kennung). **Warum:** Es ist eine
öffentliche, anonyme Leseanfrage ohne Geheimnis — es gibt nichts, was ein
Server dazwischen schützen oder berechnen müsste; der Kalorienzähler bekommt
wie bisher nur das fertige Gericht (`POST /entries` mit `dish`). Ein Umweg
über `../food` hieße einen neuen Endpunkt, ein Ausrollen und eine zweite
Stelle, die die Antwort liest, nur um sie durchzureichen. Das Parsen liegt
in einem eigenen Typ (`OpenFoodFactsParser`) und ist aus echten Antworten
ohne Netz getestet. **Verworfen:** (a) ein Proxy-Endpunkt im Kalorienzähler
(`GET /api/food/lookup/{code}`) — mehr Code an zwei Stellen für dieselbe
Antwort, und ohne den Dienst geht dann auch das Scannen nicht; (b) eine
Produkt-Datenbank im Dienst spiegeln — Open Food Facts ist zu groß und
ändert sich laufend. Wird eine zweite Quelle nötig (Nutritionix, fddb),
ist das der Punkt, an dem ein Dienst-Endpunkt sinnvoll wird.

## 2026-09-21 — Scanner mit VisionKit statt AVFoundation
Der Scanner ist `VisionKit.DataScannerViewController` in einem
`UIViewControllerRepresentable`, nicht eine eigene `AVCaptureSession` mit
`AVCaptureMetadataOutput`. **Warum:** VisionKit bringt Kamera-Vorschau,
Fokus, Hervorheben des erkannten Codes, Zoom per Fingergeste und die
Anleitung („Code ausrichten") fertig mit — mit AVFoundation wären das alles
eigene Layer und eigene Delegaten. Die Abfrage `isSupported`/`isAvailable`
sagt vorher, ob es geht (im Simulator: nein), und die Kamera-Erlaubnis
holt die App selbst über `AVCaptureDevice`, bevor der Scanner steht. Preis:
iOS 16+, kein Simulator — beides gilt hier ohnehin (Deployment iOS 18, und
der Ablauf hinter dem Scan ist über `COCKPIT_SCAN` ohne Kamera prüfbar).
**Verworfen:** (a) `AVCaptureSession` + `AVCaptureMetadataOutput` — läuft
auch im Simulator nicht, aber deutlich mehr Code für weniger; (b) eine
Fremdbibliothek (z. B. CodeScanner) — eine Abhängigkeit für das, was das
System selbst kann.

## 2026-09-20 — Wald: Sperre über das Screen-Time-API, Ende in einer eigenen Erweiterung
Eine Fokus-Session sperrt alle anderen Apps über `ManagedSettings` (Schild auf
alle Kategorien außer der Whitelist aus Apples `FamilyActivityPicker`); das
Ende ist bei `DeviceActivity` angemeldet, und die Erweiterung `FokusMonitor`
leert den Store, wenn das Intervall abläuft. **Warum:** Felix will, dass
„alle anderen Apps gesperrt" sind — das kann auf iOS nur das Screen-Time-API,
und nur eine DeviceActivity-Erweiterung läuft garantiert am Ende, auch wenn
die App längst beendet ist. Die App räumt zusätzlich selbst auf, sobald sie
wieder aktiv ist, weil Apples Rückruf „zeitnah" kommt, nicht auf die Sekunde.
**Verworfen:** (a) nur ein Timer in der App (räumt nichts weg, wenn die App
nicht läuft — die Sperre bliebe stehen); (b) Geführter Zugriff / Sperren der
App auf sich selbst (sperrt nichts anderes, und Abbrechen wäre ein Dreifachklick
entfernt); (c) eine Fremd-App wie Forest (die kann weder das Habit speisen noch
Felix' Whitelist und Kurzbefehle).

## 2026-09-20 — Wald: Sessions liegen beim Habits-Dienst, Tag = Tag des Beginns
Die durchgestandenen Sessions speichert der Habits-Dienst
(`/api/focus/sessions`, `data/focus.json`), und das neue Habit „Fokus-Zeit"
(FOCUS, Tagesziel 240 Minuten) rechnet aus demselben Bestand. **Warum:** Felix
will das Habit mit dem Wald „synchronisiert" — ein Bestand, eine Regel, gerechnet
im Dienst wie alle Sträh­nen. Eine Session gehört zum Tag ihres **Beginns**
(Europe/Berlin), nicht anteilig zu beiden Tagen: wer um 23:30 pflanzt, hat am
Abend fokussiert, und eine Aufteilung machte aus einem Baum zwei halbe.
**Verworfen:** (a) Sessions nur auf dem Gerät (das Habit könnte sie nicht sehen,
und ein neues Handy hätte einen leeren Wald); (b) ein eigener Dienst (ein
vierter Spring-Boot-Prozess für eine Liste von Zeitpunkten); (c) Aufteilen an
Mitternacht.

## 2026-09-20 — Wald: kein Abbrechen, Mitteilungen über Felix' Kurzbefehle
Eine laufende Session hat keinen Abbrechen-Knopf und keinen Weg über die App
hinaus; Mitteilungen schaltet nicht die App, sondern die Kurzbefehle „Fokus an"
und „Fokus aus", die sie per x-callback-URL aufruft (mit dem Endzeitpunkt als
Eingabe). **Warum:** Beides Felix' Entscheidung — „vorzeitig abbrechen soll
nicht möglich sein", Mitteilungen „per Kurzbefehl automatisch". Den
Fokus-Modus des Systems darf eine App nicht selbst schalten; ein Kurzbefehl
darf es. „Fokus aus" kann erst laufen, wenn die App nach dem Ende wieder im
Vordergrund ist (Kurzbefehle starten nicht aus dem Hintergrund) — deshalb geht
der Endzeitpunkt mit, damit „Fokus an" den Modus bis dahin befristen kann.
**Verworfen:** (a) Abbrechen mit Strafe (verfaulter Baum) — ausdrücklich nicht
gewollt; (b) Mitteilungen nur über den Schild (der sperrt Apps, keine Banner);
(c) Felix schaltet den Fokus-Modus von Hand (vergisst man, und die Session
ist dann keine).

## 2026-09-20 — kcal als 7-Tage-Mittel, zentriert, gerechnet im Kalorienzähler
Die kcal-Kurven in beiden Verlaufsdiagrammen (Gewicht-Tab, Essen-Tab; Web
genauso) zeigen standardmäßig das **gleitende 7-Tage-Mittel**, der Tageswert
ist ein zweiter, blasserer Umschalter und aus. **Warum:** Felix will ein
„sinnvolles Mittel" statt der springenden Tageswerte; Tage ohne Eintrag
dürfen nicht als null einrechnen. Das Fenster ist **zentriert** (3 davor, der
Tag, 3 danach) wie das 7-Tage-Mittel des Gewichts – im selben Diagramm decken
beide Kurven dieselben Tage ab, und der vorläufige Rand ist gepunktet wie beim
Gewicht. Gerechnet wird im Kalorienzähler (`/api/food/daily-average`), nicht
in den Clients: vier Oberflächen, ein Wert. Felix hat zentriert gewählt und
für das Web das Mittel standardmäßig an (vorher waren die kcal dort aus).
**Verworfen:** (a) rückblickendes Fenster (steht am Rand sofort fest, läuft
dem Gewichtsmittel aber drei Tage hinterher); (b) 14 Tage (träger);
(c) Rechnen im Client (zweimal Swift, zweimal JS, und die App hat nur den
sichtbaren Zeitraum, das Fenster des ersten Tages bräuchte mehr).

## 2026-09-17 — 7-Tage-Residuum: Tagesmesswert gegen Tages-Target, gerechnet im Dienst
Die Kachel mittelt `Messwert − Target` **je Tag** über die letzten sieben
Kalendertage bis zur letzten Messung. **Warum:** Felix will einen fairen
Vergleich auch für die letzten Tage. Das zentrierte 7-Tage-Mittel reicht am
aktuellen Rand in noch ungemessene Tage und hinkt deshalb nach; der Abstand
eines Tages zu seinem eigenen Target steht fest, sobald der Tag gemessen ist.
Gerechnet wird im Weight Tracker (`residual7`, `residual7Days` in der Summary), nicht
in der App — sonst rechneten Web und App dieselbe Regel zweimal, und in der
App hängt die geladene Reihe am Zeitraum-Umschalter. Fehlen Tage, steht es
unter dem Wert („5 von 7 Tagen“, neuer `note`-Text an Kacheln); gefärbt wie
„Differenz z. Target“, beim Halten mit der halben Korridorbreite als Toleranz.
**Name:** „7-Tage-Residuum" — der statistische Begriff für genau diese
Größe, Messwert minus Modell (die Zielkurve); hieß am ersten Tag
„7-Tage-Differenz". Felix wollte einen fachlichen Namen und schlug
„7-Tage-Delta" vor; verworfen, weil ein „Delta über 7 Tage" als Veränderung
seit letzter Woche gelesen wird, nicht als Abstand zur Kurve.
„Soll-Ist-Abweichung" und „Bias" standen ebenfalls zur Wahl.
**Verworfen:** (a) `avg7 − target` aus der bestehenden Summary — genau das
Nachhinken, das die Kachel vermeiden soll. (b) Im Client aus der Monatsreihe
rechnen — zwei Implementierungen, und die Reihe ist nicht immer die vom Monat.
(c) Das Fenster auf „heute“ statt auf den letzten Messtag setzen — nach zwei
Tagen ohne Waage stünde ein 5-Tage-Mittel da, obwohl sieben gemessene Tage
vorliegen.

## 2026-09-11 — Linien und Zeiträume in einer Liste, Farbe als Hex-String
Ein Typ `Highlight` mit `kind` (band | line) statt zwei Endpunkten und zwei
Listen. **Warum:** dieselbe Verwaltung für beides — wer eine Linie anlegen
kann, muss sie auch in derselben Liste wiederfinden und entfernen können; und
der Dienst sortiert einmal nach `start`, egal was es ist. Die Farbe kommt
als `#rrggbb` wie bei den Einkaufs-Kategorien, nicht als Name aus einer
festen Palette: die acht Vorgabekreise sind Bequemlichkeit, der Farbwähler
darf alles. Antwort von POST und DELETE ist die **ganze** Liste — die App
ersetzt ihre Kopie, statt einen Eintrag in eine sortierte Liste einzufädeln.
**Verworfen:** (a) ein `Vacation` mit `start == end` als Linie deuten — ein
eintägiges Band ist etwas anderes als eine Linie, und die Deutung stünde
in zwei Clients. (b) Nur Zeiträume verwaltbar, Linien nur in der Datei —
dann stünde in der Liste etwas, das man nicht loswird.

## 2026-09-05 — Einkaufsliste: eigener Dienst, eigener Token, vierte App
**Warum:** Joana soll die Liste bedienen und sonst nichts sehen.
Der Privat-Token öffnet alles — also ein eigener Dienst (`fherrmann.com/
shopping-list`) mit eigenen Token je Person (`SHOPPING_TOKENS`), außerhalb des
Privat-Gates. Die App setzt den Token als Cookie nur für diesen Pfad; Healthy
zeigt den Tab, sobald er da ist, und **Einkaufsliste** ist derselbe Tab als eigene
App (`Shopping/` in beiden Targets). Der Name „Einkaufsliste" ist meine Wahl —
kurz, deutsch, passt neben Healthy/Vault/Fokus; leicht zu ändern, solange die
App noch auf keinem zweiten Handy liegt.
**Gerichte liegen im Einkaufs-Dienst, nicht im Kalorienzähler.** Der Plan sah
Zutaten an den Gerichten des Kalorienzählers vor (mit Migration). Felix wollte
„Gerichte speichern, die man als Ganzes auf die Liste packt" — das ist eine
Zutatenliste, keine Nährwertfrage. So kann sie auch seine Freundin pflegen,
ohne Schreibrecht auf den Kalorienzähler.
**Ohne Netz sofort sichtbar.** Der Store ändert seinen Stand selbst, wenn ein
Aufruf im Postausgang liegt (siehe `ARCHITEKTUR.md`) — im Laden fehlt das Netz
am häufigsten.
**Verworfen:** TestFlight für das zweite Handy (später, siehe Plan); Bearer-
Header statt Cookie in der App (der Dienst nimmt beides, das Cookie spart
einen zweiten Auth-Pfad im `APIClient`); Abschnitte je Kategorie in der Liste
(Felix: eine Liste, nur sortiert, mit Icons).

## 2026-09-04 — „Alles“ ist zurück, mit dem 30-Tage-Mittel als Vorgabe
**Warum:** Felix will die ganze Historie wieder sehen — als ruhige Kurve.
Über acht Jahre ist das 7-Tage-Mittel fast so unruhig wie die Messwerte; das
30-Tage-Mittel zeigt den Verlauf. Darum hat „Alles“ ein eigenes Angebot an
Umschaltern (30-Tage- statt 7-Tage-Mittel, ohne kcal als Vorgabe) und eine
eigene, gemerkte Auswahl — ein Wechsel zwischen den Zeiträumen tauscht keine
Haken aus. „3 Jahre“ bleibt daneben bestehen (siehe 2026-09-02).
**Verworfen:** fünf Umschalter in einer Reihe (zu breit fürs iPhone) und
geglättete Interpolation (überschwingt in Lücken, siehe 2026-09-02).

## 2026-09-04 — Drei Apps aus einem Repo: Healthy, Vault, Fokus
**Warum:** fünf Tabs waren voll, drei Dienste kommen dazu (To-Do, Roadmap,
Einkaufsliste), und die drei Gruppen haben verschiedene Nutzungen: täglich
eintragen, geschützt nachlesen, planen. Die Logik liegt in den Backends, die
Querverbindungen laufen serverseitig - der Schnitt kostet Struktur, keine
Funktion (`PLAN-AUFTEILUNG.md`).
**Ein Repo, drei Targets**, nicht drei Repos: Zugang, Cookies, Cache,
Postausgang, Sperre, Tools und Harness würden sonst dreifach gepflegt.
**Verworfen:** `Core/` als Swift-Package. Ordner, die in mehrere Targets
eingebunden werden, tun dasselbe ohne Paketverwaltung - und `Shared/` lief
so schon seit dem Widget.
**Healthy behält die alte Bundle-ID:** HealthKit-Berechtigung, Push-Anmeldung
beim Kalorienzähler und die vorhandenen Kalorien-Kacheln bleiben damit
unangetastet. Vault und Fokus sind neue Apps mit allem, was das heißt.

## 2026-09-04 — Eine geteilte Keychain-Gruppe, die Token wandern einmal
**Warum:** die Token sollen einmal eingegeben werden, nicht dreimal. Alle
fünf Targets tragen `com.fherrmann.shared` in den Entitlements; Healthy holt
die vorhandenen Einträge beim ersten Start aus der alten Vorgabegruppe
hinüber. Die alte Gruppe wird **nicht** geleert - fällt die Wanderung aus,
liest Healthy weiter von dort, und Vault/Fokus sagen sichtbar „Kein Zugang".
**Nicht gewandert:** das Noten-Passwort. Es liegt hinter Face ID; Vault fragt
es einmal neu ab, statt dass Healthy beim Start eine Abfrage zeigt, deren
Ergebnis sie selbst nie braucht.

## 2026-09-04 — Vault sperrt die ganze App, nicht zwei Tabs
**Warum:** in Vault liegt hinter jedem Tab etwas Schützenswertes. Eine Sperre
um alles ist weniger Code und ein klareres Versprechen: beim Verlassen zu,
beim Zurückkommen gleich wieder fragen, Sichtschutz im App-Umschalter immer.
Der `LAContext` dieser einen Sperre holt auch das Noten-Passwort heraus.

## 2026-09-03 — Offline: letzter Stand plus Postausgang, aber kein Nachrechnen
**Warum:** Felix' Wunsch — ohne Netz wenigstens die aktuellen Werte sehen,
im besten Fall auch Haken und Messwerte eintragen, die später nachgehen.
**Wie:** `APIClient` legt jede erfolgreiche GET-Antwort als Datei ab und
liefert sie bei einem Transportfehler zurück (nur dann — bei 403 oder 500 hat
der Dienst geantwortet, und den alten Stand darüberzulegen hieße, ein Problem
zu verstecken). Ausgewählte Änderungen gehen mit `queueWhenOffline: true` in
den `Outbox` und werden beim nächsten Netz der Reihe nach nachgesendet; lehnt
der Dienst eine ab (4xx), fliegt sie raus und der Grund steht in der Leiste.
**Bewusst nicht:** lokal nachrechnen. Ein offline gesetzter Haken zeigt eine
Uhr, keine neue Sträh­ne; ein offline eingetragenes Gewicht ändert die Kacheln
erst nach dem Nachsenden. Sonst stünde die Rechenregel an zwei Stellen — genau
das, was „Kein Offline-Cache" vom 01.09. vermeiden wollte. Die Entscheidung
von damals bleibt im Kern: kein zweiter Datenstand, nur ein Zwischenspeicher.
**Verworfen:** Anmeldung, Habit anlegen, Ziele ändern im Postausgang — dort
braucht man die Antwort sofort (eine ID, eine Bestätigung), und ein Passwort
hat in einer Warteschlange nichts verloren.

## 2026-09-02 — Zugang wird ein Blatt, weil fünf Tabs voll sind
**Warum:** iOS zeigt höchstens fünf Tabs; der sechste wandert unter „Mehr",
und dort landete ausgerechnet der Tab, den man braucht, wenn alles andere
„Kein Zugang" sagt. Zugang ist selten nötig - ein Zahnrad reicht.
**Verworfen:** Habits unter „Mehr" (der neue Tab wäre der versteckte),
Finanzen und Noten zusammenlegen (zwei Sperren, zwei Dienste).
**Nebenwirkung:** `COCKPIT_TAB=setup` gibt es weiter, öffnet aber das Blatt.

## 2026-09-02 — Habits: kein Web-UI, die App rechnet nichts
**Warum:** Felix' Entscheidung (API + Tab). Ohne zweite Oberfläche gibt es
keine Anzeigeregeln, die an zwei Stellen stimmen müssten - genau das Problem,
das die Übersicht der doppelt gepflegten Regeln beschreibt. Deshalb liefert
der Dienst `HabitStatus` fertig gerechnet: Sträh­ne, „heute erledigt",
„gefährdet". Die App zeigt und schickt Haken, sonst nichts.
**Auch so entschieden:** „Track food" zählt automatisch - ab 80 % des
kcal-Ziels oder wenn Frühstück, Mittag und Abend je einen Eintrag haben
(Felix' Regel, ein Snack ersetzt keine Mahlzeit).

## 2026-09-02 — Die Noten melden sich selbst, nicht über den Kalorienzähler
**Warum:** Felix' Entscheidung. Der naheliegende Weg wäre gewesen, das
food-Backend zur Push-Zentrale zu machen — dort liegen Schlüssel und
Gerätekennungen schon. Dagegen sprach die Kopplung: der Notendienst wäre für
seine eigene Meldung auf einen fremden Dienst angewiesen, und ein Ausfall des
Kalorienzählers nähme ihm die Stimme.
**Preis, bewusst bezahlt:** eine zweite APNs-Umsetzung (Python statt Java),
eine zweite Geräteliste und eine **Kopie** des `.p8` als `/etc/apns-grades.p8`.
Die Kopie statt einer Gruppenmitgliedschaft: die Dienste laufen unter
verschiedenen Benutzern, und `flexii` in die Gruppe `food` zu stecken gäbe
Zugriff auf alles, was dieser Gruppe gehört.
**Nicht verhandelbar war der Wächter selbst:** der Notenchecker bemerkt neue
Noten längst, liegt aber unter `/opt/notenchecker` und ist tabu. Wir lesen
seine Datei und vergleichen selbst.

## 2026-09-02 — Face ID ersetzt das Passwort, statt es zu ersparen
**Warum:** die Weboberfläche hat zwei Schranken, Geräte-Token und Anmeldung.
Die App spielt beide nach — der Endpunkt hätte sich auch mit dem Token allein
öffnen lassen, aber dann läse jeder die Noten, der den Token hat.
Benutzername und Passwort gibt Felix einmal ein; das Passwort liegt danach
hinter `.userPresence` im Keychain.
**Der Kniff:** der `LAContext`, mit dem der Tab entsperrt wurde, ist bereits
ausgewiesen. Die Keychain gibt das Passwort damit **ohne zweite Abfrage**
heraus - eine Sperre, zwei Zwecke.
**Verworfen:** das Passwort ungeschützt neben die Token legen. Die sind
Geräte-Token, die das Widget bei gesperrtem Bildschirm braucht; ein Passwort
braucht das nie.

## 2026-09-02 — Annahmen liegen in der App, nicht in der Sitzung
**Warum:** im Web merkt sich der Server die angenommenen Noten in der Sitzung.
Für die App wäre das derselbe Zustand für zwei Oberflächen: ein Tippen auf dem
Handy schriebe den Browser-Tab um, der nebenbei offen ist. Die App schickt sie
deshalb bei jeder Anfrage mit und merkt sie sich selbst.
**Gerechnet wird trotzdem dort:** die Regel aus PO-I23 § 8 Abs. 2 steht in
`berechnung.py` und nirgends sonst. Ein Nachbau in Swift wäre eine zweite
Stelle, an der eine Prüfungsordnung richtig sein muss.

## 2026-09-02 — Der UI-Harness bekommt seine Token über TEST_RUNNER_
**Warum:** `xcodebuild` reicht **nur** so präfixierte Variablen an den
Testläufer weiter und streicht das Präfix dabei. Vorher standen sie ohne
Präfix im Skript — der Testläufer sah leere Token, und die Läufe waren
trotzdem grün, weil im Simulator noch Token vom letzten `run-simulator.sh` im
Keychain lagen. Ein Harness auf Resten sieht aus wie einer, der prüft.
**Nebenbei entstanden:** `COCKPIT_URL_<DIENST>` biegt im Debug-Build die
Adresse eines Dienstes um. Damit läuft der Noten-Tab gegen einen lokal
gestarteten Dienst - der einzige Weg, ihn mit echten Daten zu sehen, ohne ein
Passwort in den Schlüsselbund dieses Rechners zu legen.

## 2026-09-02 — Das Widget holt seine Daten selbst
**Warum:** eine Widget-Erweiterung ist ein eigener Prozess mit eigenem
Container; die Cookies der App sieht sie nicht. Sie liest das Token aus der
**Keychain-Zugriffsgruppe** — der Vorgabegruppe der App, in der es ohnehin
liegt — und ruft `/api/food/day` selbst auf. Die App stößt nach einer Änderung
nur ein Neuzeichnen an.
**Verworfen:** eine App Group, in die die App den letzten Stand schreibt. Das
wäre ein zweiter Datenstand (siehe „Kein Offline-Cache"), und das Widget zeigte
alte Zahlen weiter, wenn die App länger nicht lief. Es zeigt jetzt lieber den
letzten bekannten Stand **mit Datum**, statt ihn als heutigen auszugeben.
**Verworfen:** eine zusätzliche Keychain-Gruppe. Die Vorgabegruppe
(`$(AppIdentifierPrefix)com.fherrmann.cockpit`) reicht, solange beide Ziele
mit demselben Team signiert sind.

## 2026-09-02 — Die Finanz-Sperre prüft den Gerätebesitzer, nicht das Gesicht
**Warum:** `deviceOwnerAuthentication` fällt auf den Gerätecode zurück, wenn
Face ID fehlschlägt oder nicht eingerichtet ist. `…WithBiometrics` hätte den
Tab auf einem Gerät ohne Face ID unerreichbar gemacht — und im Simulator jeden
Test.
**Fallstrick, teuer gelernt:** `evaluatePolicy` schiebt den Systemdialog vor
die App, die damit `.inactive` wird. Wer beim Verlassen des Vordergrunds neu
sperrt, sperrt sich mitten in der eigenen Abfrage — der Dialog kommt sofort
wieder, endlos. Deshalb das `isAuthenticating`-Flag.

## 2026-09-02 — Die Schritte bekommen eine Leiste, keinen Tacho
**Warum:** der Tacho im Essen-Tab beantwortet „drüber oder drunter" und hat
dafür eine Zielkerbe. Schritte sind ein Mindestwert — es geht um „wie weit",
und dafür ist ein Balken die naheliegendere Form. Über dem Ziel bleibt er voll
statt aus dem Rahmen zu laufen; dass es mehr war, sagt die Zahl daneben.

## 2026-09-02 — Jede Kachel ist entfernbar, und die gespeicherte Liste ist vollständig
**Warum:** vier fest verdrahtete Kacheln waren eine Annahme darüber, was
jemand sehen will. „Komplett modular" heißt auch: alle weg ist ein gültiger
Zustand.
**Der Haken war die Umstellung.** Alte und neue Bedeutung sehen als JSON
gleich aus — eine Liste von Schlüsseln. Ohne Unterscheidung hätte das erste
Laden nach dem Deploy vier Kacheln stillschweigend gelöscht. Deshalb ein
`version`-Feld: fehlt es, gilt die alte Bedeutung, und der Server ergänzt.
Das schützt auch einen Browser-Tab, der die Umstellung noch nicht kennt.
**Die vier früheren Basis-Schlüssel stehen jetzt im Backend** — bewusst als
eingefrorener Schnappschuss für die Umstellung, nicht als zweite Registry:
welche Kacheln es gibt, weiß weiterhin nur die Oberfläche.

## 2026-09-02 — Gerade Linien, keine geglätteten Kurven
`.interpolationMethod(.linear)` in beiden Diagrammen.
**Warum:** Catmull-Rom überschwingt zwischen weit auseinanderliegenden Punkten
und zeichnet Werte, die nie gemessen wurden. Mit der importierten Historie —
teils Monate zwischen zwei Messungen — wäre das grob irreführend. Eine gerade
Verbindung behauptet nur, was zwischen zwei Messungen bekannt ist: nichts.
**Verworfen:** Glättung wie in der Weboberfläche (`tension: 0.2`), die dort
über dichte Tagesdaten läuft und deshalb weniger anrichtet.

## 2026-09-02 — „3 Jahre" statt „Alles", zugeschnitten im Client
**Warum:** ein rollendes Fenster ist über neun Jahre lesbarer als die gesamte
Historie, in der die letzten Monate zu einem Strich zusammenschrumpfen. Der
Zuschnitt passiert im Client, weil die Reihe klein ist und ein eigener
Endpunkt je Zeitraum Backend-Arbeit für eine reine Anzeigefrage wäre.
**Verworfen:** ein `/api/weight/three-years` (Deploy für eine Beschriftung).

## 2026-09-02 — Health-Werte füllen nur Lücken
`keepExisting` im Backend, gesetzt nur vom Abgleich.
**Warum:** es gibt genau einen Wert pro Tag, und der von Hand eingetragene ist
der verlässlichere. Ohne diese Regel hinge das Ergebnis daran, wer zuletzt
geschrieben hat — je nach Weckzeitpunkt von iOS mal so, mal so.
**Warum im Backend und nicht im Client:** dort ist die Prüfung atomar und gilt
für jeden, der schreibt; im Client wäre sie ein Wettlauf zwischen Lesen und
Schreiben. Im Browser und in der App bleibt Überschreiben ausdrücklich erlaubt
— die Schonung gilt nur für Importe.

## 2026-09-02 — Der erste Abgleich holt weiterhin alles
**Warum:** Felix' Entscheidung, nachdem der erste Lauf 265 Werte zurück bis
2018 eingespielt hat. Eine Neuinstallation spielt sie also wieder ein — was
folgenlos ist, seit vorhandene Tage geschont werden.
**Was dabei schiefging und die Entscheidung nötig machte:** ich hatte den
ersten Abgleich ohne Grenze gebaut. Dass damit acht Jahre Historie in den
Tracker laufen, hätte vorher zur Sprache gehört, nicht hinterher.

## 2026-09-02 — Die früheste Messung eines Tages gewinnt
**Warum:** Health kennt beliebig viele Messungen pro Tag, der Weight Tracker
genau eine. Morgens nüchtern ist der über Tage vergleichbare Wert; eine
Abendmessung liegt regelmäßig ein bis zwei Kilo darüber und würde die Kurve
verrauschen.
**Verworfen:** die letzte Messung (Abendwert), der Tagesdurchschnitt (mischt
zwei verschiedene Messbedingungen).

## 2026-09-02 — Push liegt im food-Backend, nicht in der App
**Warum:** die Schnellerfassung läuft dort ohnehin schon asynchron. Nur der
Server weiß, wann ein Auftrag fertig ist — und nur er läuft weiter, wenn das
Handy gesperrt ist.
**Ohne Bibliothek:** APNs ist ein HTTP/2-POST mit einem signierten Token im
Kopf, und beides kann das JDK. Eine Abhängigkeit für dreißig Zeilen wäre mehr
Pflege als Ersparnis. Der Fallstrick steckt in der Signatur (DER → JOSE), und
darauf zeigen drei Tests.
**Die App fragt trotzdem weiter selbst nach:** die Benachrichtigung ist ein
Zustellweg, keine Voraussetzung.

## 2026-09-01 — Die Schnellerfassung wartet nicht mehr im Blatt
Der Auftrag gehört dem Store, nicht der Ansicht. Abschicken schließt das Blatt
sofort; das Nachfragen läuft weiter, eine Zeile in der Tagesliste zeigt es an,
und ist der Vorschlag da, geht er von selbst auf.
**Warum:** eine Minute auf ein Blatt zu starren, das nichts tut, war der
schlechteste Teil des Ablaufs — und der Server arbeitet ohnehin schon
asynchron, nur die App stand daneben.
**Die Kennung wird gemerkt** (`UserDefaults`): wird die App weggeräumt,
rechnet der Server weiter, und ohne die Kennung wäre das Ergebnis danach
nicht mehr abholbar.
**Benachrichtigung nur, wenn die App nicht im Bild ist** — sonst sieht man das
Blatt ohnehin aufgehen, und die Meldung wäre Lärm.
**Grenze, bewusst in Kauf genommen:** liegt das Handy gesperrt, friert iOS die
App nach etwa 30 Sekunden ein; der Auftrag dauert bis zu 56. Die Meldung kommt
dann erst beim nächsten Öffnen. Für „Handy weglegen" bräuchte es echtes Push
und damit einen APNs-Dienst im food-Backend.

## 2026-09-01 — Der Zeitbereich eines Diagramms kommt vom gewählten Zeitraum
`FoodChartView` bekommt `from`/`to` von außen; die Achse steht per
`.chartXScale`, statt sich aus den Daten zu ergeben.
**Warum:** aus den Daten abgeleitet hingen daran gleich **drei** Fehler, die
wie drei verschiedene aussahen. Bei zwei erfassten Tagen war die Achse zwei
Tage breit — daher „1. Sep" doppelt (die automatischen Achsenmarken lagen
innerhalb eines Tages und formatierten sich zum selben Text). Der
Zeitraum-Umschalter änderte sichtbar nichts, weil 14, 30 und 90 Tage
dasselbe Bild ergaben. Und die Gewichtskurve war auf den ersten Tag mit
kcal-Eintrag zugeschnitten, blieb also auf zwei Punkte zusammengestrichen,
obwohl 90 Werte vorlagen.
**Die Lehre:** ein Diagramm zeigt einen *Zeitraum*, keine *Datenmenge*. Die
Datenlage bestimmt, was darin steht — nicht, wie breit es ist.
**Verworfen:** die Achse weiter aus den Daten ableiten und nur die
Beschriftung reparieren — das hätte den Umschalter wirkungslos gelassen.

## 2026-09-01 — kcal als Kurve, an jeder Lücke getrennt
Im Verlauf des Kalorienzählers standen erst Säulen; jetzt ist es eine Linie.
Dieselbe Kurve liegt zusätzlich über der Gewichtskurve im Gewicht-Tab.
**Warum getrennt:** `dailyTotals` liefert **nur Tage mit Einträgen** — fehlende
Tage sind unbekannt, nicht null. Eine durchgezogene Linie darüber hinweg würde
behaupten, dazwischen sei etwas gemessen worden. Dieselbe Entscheidung wie
`spanGaps: false` im Web. Ein einzelner Tag zwischen zwei Lücken bekommt einen
Punkt, sonst wäre er unsichtbar.
**Was die Säulenfarbe trug,** übernimmt jetzt ein roter Punkt an Tagen, die
mehr als 100 kcal über dem Ziel liegen — sonst ginge die Information mit den
Säulen verloren.

## 2026-09-01 — Diagrammfarben folgen dem Erscheinungsbild, der Rest von selbst
`Palette.adaptive(light:dark:)` statt fester Werte.
**Warum:** die Farben stammen aus den Weboberflächen, und die sind dunkel.
Dieselben hellen Pastelltöne auf weißem Grund haben zu wenig Kontrast — die
7-Tage-Kurve war kaum vom Hintergrund zu unterscheiden. Im Dunkeln bleibt es
exakt bei den Webwerten, damit dieselbe Kurve in App und Browser gleich
aussieht; im Hellen kommt die kräftigere Stufe derselben Farbe.
**Verworfen:** einen eigenen Farbsatz erfinden (dann sähen App und Browser
verschieden aus) und alles hell zu lassen (schlechter lesbar).

Alles andere — Karten, Listen, Leisten, Tacho-Spuren — folgt dem System schon,
weil durchgehend Systemfarben und `.thinMaterial` benutzt werden. Das war kein
Zufall, sondern der Grund, keine eigenen Grautöne zu setzen.

## 2026-09-01 — Der Simulator bekommt die Token über die Umgebung
`Access.seedFromEnvironment()`, nur unter `#if DEBUG`, gefüttert von
`tools/run-simulator.sh` aus dem macOS-Schlüsselbund.
**Warum:** ohne Zugang zeigen die nativen Tabs nur Fehlermeldungen, und
Layoutfehler sieht man erst mit echten Daten — die drei oben gefundenen hätte
kein Test gefunden. Von Hand eintippen wäre bei jedem Simulator-Neustart
fällig.
**Warum hinter `#if DEBUG`:** ein Token, das über eine Umgebungsvariable in
die App kommt, hat in einem Build für ein echtes Gerät nichts zu suchen.
**Verworfen:** Token in einer Datei im Repo (landet in Git), UI-Test zum
Eintippen (viel Maschinerie für ein Textfeld).

## 2026-09-01 — Die Gewichtskurve wird in die kcal-Skala hineingerechnet
Swift Charts kennt nur **eine** y-Skala. Das Gewicht wird deshalb linear in
den kcal-Bereich abgebildet und rechts mit eigenen Beschriftungen versehen.
**Warum:** die Zusammenschau „viel gegessen → Gewicht reagiert" ist der Grund,
warum die Kurve überhaupt im Kalorienzähler steht; ihr Verlauf stimmt durch die
Abbildung, und die rechte Achse sagt, welche Kilogramm dahinterstehen.
**Verworfen:** zwei getrennte Diagramme untereinander (der zeitliche Bezug geht
verloren, genau der ist aber der Punkt), und die Kurve wegzulassen.

## 2026-09-01 — Serverfehler behalten ihren Wortlaut
`APIError.http(Int, String?)` statt nur des Statuscodes.
**Warum:** die Backends begründen einen 400 im Klartext („Die Anteile müssen
zusammen 100 % ergeben, sind aber 96,0 %"). Diese Meldung wegzuwerfen und
„HTTP 400" anzuzeigen wäre die schlechtere von beiden. HTML-Antworten und alles
über 300 Zeichen werden verworfen — ein Stacktrace gehört nicht auf den
Bildschirm.

## 2026-09-01 — Die Aufteilung der Mahlzeiten wird im Client vorgeprüft
**Warum:** der Server nimmt sie nur vollständig und auf 100 % summierend an.
Das erst nach dem Sichern zu erfahren, obwohl beide Zahlen auf dem Bildschirm
stehen, wäre unnötig. Der Server prüft weiterhin selbst — die Vorprüfung ist
Bequemlichkeit, keine Absicherung.

## 2026-09-01 — Ein Diagramm mit Umschalter statt vier untereinander
Die Weboberflaeche zeigt 30 Tage, 90 Tage, 365 Tage und „all time" als vier
gestapelte Diagramme. Nativ ist es **eines** mit einem Segment-Umschalter.
**Warum:** auf einem Handy bedeuten vier Diagramme untereinander vor allem
Scrollweg; man sieht nie zwei davon gleichzeitig, der Vergleich, für den das
Stapeln gedacht ist, findet also ohnehin nicht statt.
**Verworfen:** vier Diagramme wie im Web (viel Scrollen), Wischen zwischen
Zeiträumen (kollidiert mit dem Wischen zwischen Tabs).

## 2026-09-01 — Das Linien-Zerlegen liegt neben der View, nicht darin
`WeightChartData` statt privater Methoden in `WeightChartView`.
**Warum:** das Zerlegen an der Vollständigkeitsgrenze ist die einzige Stelle
im Diagramm mit echter Logik — und ein Fehler darin sieht aus wie ein
Datenproblem, nicht wie ein Programmfehler. In einer View wäre sie nicht zu
testen; jetzt hängen fünf Tests daran. Einer davon hat prompt eine falsche
Annahme von mir aufgedeckt: das verbindende Stück gehört zum **früheren**
Punkt, genau wie im Web (`points[ctx.p1DataIndex]`).
**Verworfen:** in der View lassen und „sieht richtig aus" als Prüfung.

## 2026-09-01 — Kacheln als Enum statt als Tabelle von Closures
**Warum:** die Web-Registry ist ein Objekt aus Closures; in Swift wäre das
unter strikter Nebenläufigkeit eine nicht-`Sendable` Globale. Als Enum ist
jede Kachel an einer Stelle vollständig beschrieben, und der Compiler merkt,
wenn bei einer neuen Kachel ein Fall fehlt.

## 2026-09-01 — Das App-Icon wird erzeugt, nicht abgelegt
`tools/make-icon.swift` zeichnet die 1024er-PNG.
**Warum:** so ist nachvollziehbar, woraus das Icon besteht, und eine
Farbänderung ist eine Zeile statt einer neuen Datei aus einem
Grafikprogramm. Motiv ist ein Instrument mit dreigeteiltem Bogen — in den
Verlaufsfarben, die die Tachos des Kalorienzählers schon benutzen.
**Verworfen:** ein in einem Grafikprogramm gebautes Icon (nicht
nachvollziehbar, nicht diff-bar).

## 2026-09-01 — Hybrid statt „alles nativ"
Essen und Gewicht werden nativ, Finanzen bleibt WebView.
**Warum:** Weight und Food haben sauberes JSON-REST, da kostet nativ fast nur
UI-Arbeit. Das Finance Cockpit hat kein API und soll keins bekommen: seine
Seite wird täglich von einem Claude-Lauf neu gestaltet — eine feste
JSON-Struktur plus Rendering im Client würde genau diese Freiheit nehmen.
**Verworfen:** alles nativ (+2–3 Tage und ein Rückschritt beim Cockpit),
alles WebView (dann keine Widgets, kein HealthKit, keine Shortcuts).

## 2026-09-01 — Erst WebView, dann Tab für Tab nativ ersetzen
**Warum:** liefert ab Tag 1 eine benutzbare App und macht jeden Zwischenstand
lauffähig. Bricht die Arbeit ab, steht trotzdem etwas Fertiges da.
**Verworfen:** nativ von Anfang an — sechs Tage ohne benutzbares Ergebnis.

## 2026-09-01 — Gewicht vor Essen
**Warum:** der kleinere Tab (990 statt 1564 Zeilen Weboberfläche) und der
geradlinigere Datenfluss. Swift Charts einmal am einfachen Fall lernen, bevor
Mahlzeiten, Gerichte-CRUD und die Schnellerfassung drankommen.
**Verworfen:** Essen zuerst, weil es der meistgenutzte Tab ist — dafür wäre
der Einstieg der steilste Teil.

## 2026-09-01 — XcodeGen statt eingecheckter `.xcodeproj`
`project.yml` ist die Quelle, das Projekt wird erzeugt.
**Warum:** eine `pbxproj` ist eine mehrere tausend Zeilen lange Datei mit
generierten IDs — unlesbar im Diff, konfliktanfällig, und ein Agent, der eine
Datei hinzufügen soll, muss sie fehlerfrei patchen. Mit XcodeGen heißt „Datei
hinzufügen": Datei anlegen, `tools/bootstrap.sh`.
**Verworfen:** (a) `.xcodeproj` einchecken — siehe oben. (b) Xcode-16-
Synchronized-Groups, die dasselbe ohne Zusatzwerkzeug könnten, aber eine von
Hand geschriebene `pbxproj` als Startpunkt brauchen, die hier niemand
verifizieren kann, solange kein Xcode installiert ist. Wenn die
XcodeGen-Abhängigkeit später stört: dann ist der Umstieg ein Einzeiler-Commit.

## 2026-09-01 — Signatur bleibt bei Team `ZWFV263P59`
Kein Wechsel nötig: bei der Aufnahme als Einzelperson wird das bestehende Team
aufgewertet, die ID bleibt. `project.yml` musste dafür nicht angefasst werden.
**Erwartet hatte ich das Gegenteil** — eine zweite Team-ID — und habe deshalb
vorab vor Nebenwirkungen gewarnt, die es gar nicht gibt: Keychain-Einträge
sind an das Team-Präfix gebunden und wären bei einem Wechsel verloren gewesen,
und iOS hätte die App nicht über eine anders signierte drüberinstalliert. Beides
entfällt.
**Erkennungsmerkmal ist deshalb die Gültigkeit des Profils, nicht die ID:**
sieben Tage kostenlos, ein Jahr bezahlt.

## 2026-09-01 — Token im Keychain, Cookies beim Start gesetzt
**Warum:** die Backends kennen nur Cookie-Auth. Die App setzt die Cookies
selbst, statt den Browser-Weg `\/setup?token=…` nachzuspielen — ein Ritual
weniger pro Gerät, und das Token liegt an der einzigen Stelle, die dafür
gedacht ist.
**Verworfen:** Token im Code oder in einer `.plist` (landet im Repo bzw. im
App-Bundle und ist damit auslesbar).

## 2026-09-01 — Kein Offline-Cache
**Warum:** alle drei Dienste sind öffentlich über HTTPS erreichbar, die
Datenmengen sind winzig. Ein Cache brächte einen zweiten Datenstand samt
Konfliktauflösung für ein Problem, das es noch nicht gibt.
**Neu bewertet am 03.09.2026** (siehe oben): ein Zwischenspeicher mit Datum
und ein Postausgang — aber weiterhin kein zweiter Datenstand mit eigener Logik.

## 2026-09-01 — Bezeichner englisch, Kommentare deutsch
**Warum:** deckt sich mit den Java-Backends (englische Typen, `WeightPoint`,
`DaySummary`) und mit Felix' Doku-Sprache. Kommentare erklären das Warum.
