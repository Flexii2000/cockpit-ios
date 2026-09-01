# Entscheidungen

Neueste zuerst. Jede mit Datum, Begründung und der verworfenen Alternative —
sonst wird sie in drei Monaten neu diskutiert.

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
