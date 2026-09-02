# Entscheidungen

Neueste zuerst. Jede mit Datum, Begründung und der verworfenen Alternative —
sonst wird sie in drei Monaten neu diskutiert.

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
**Neu zu bewerten,** sobald Einträge unterwegs ohne Netz erfasst werden sollen.

## 2026-09-01 — Bezeichner englisch, Kommentare deutsch
**Warum:** deckt sich mit den Java-Backends (englische Typen, `WeightPoint`,
`DaySummary`) und mit Felix' Doku-Sprache. Kommentare erklären das Warum.
