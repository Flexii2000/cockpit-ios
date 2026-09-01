# Entscheidungen

Neueste zuerst. Jede mit Datum, Begründung und der verworfenen Alternative —
sonst wird sie in drei Monaten neu diskutiert.

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
