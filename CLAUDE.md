# Arbeitsregeln für `cockpit-ios`

Eine iOS-App, die Felix' drei Heimserver-Dienste unter einem Icon
zusammenführt: **Kalorienzähler** (`food.fherrmann.com`), **Weight Tracker**
(`weight.fherrmann.com`) und **Finance Cockpit** (`finanzen.fherrmann.com`).

Die drei Backends bleiben, wie sie sind. Dieses Repo enthält **nur den
Client**. Änderungen an den Diensten gehören in deren eigene Repos
(`../food`, `../weight-app`, `../finance-cockpit`) — von hier aus wird an
ihnen nichts geändert, auch nicht "mal eben".

## Vor dem ersten Handgriff

1. `docs/STAND.md` lesen. Da steht, was fertig ist und was als Nächstes
   dran ist. Das ist der Einstieg, nicht dieses Dokument.
2. `docs/BACKENDS.md` lesen, wenn du an einem der beiden nativen Tabs
   arbeitest. Da stehen Endpunkte, Datentypen und die Fallstricke.
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

⚠️ **Quelle der Wahrheit für `docs/BACKENDS.md` ist der Java-Code** in
`../food/src/main/java/…` und `../weight-app/src/main/java/…`, nicht diese
Datei. Bei Widerspruch gilt der Code — Doku korrigieren, nicht raten. Und
nicht aus dem Gedächtnis dokumentieren: die Controller und Records wirklich
aufmachen.

## Bauen und prüfen

```bash
tools/bootstrap.sh   # einmalig + nach Änderungen an project.yml
tools/verify.sh      # baut fuer den Simulator und laesst die Tests laufen
tools/run-simulator.sh weight bild.png   # mit Zugang starten und aufnehmen
```

`run-simulator.sh` startet die App im Simulator **mit echten Daten** und legt
auf Wunsch einen Screenshot ab — der einzige Weg, Layoutfehler zu sehen statt
sie sich vorzustellen. Erstes Argument ist der Tab (`food`, `weight`,
`finance`, `setup`), zweites der Pfad fürs Bild.

Die Token dafür stehen im **macOS-Schlüsselbund** unter dem Konto
`cockpit-ios` (Dienste `fh_private` und `weight_app_token`) — nicht im Repo,
nicht in einer Datei. Wie sie dort hinkommen, steht im Kopf des Skripts. Die
App liest sie nur im Debug-Build (`Access.seedFromEnvironment`).

Erscheinungsbild umschalten: `xcrun simctl ui booted appearance dark|light`.
**Beide anschauen**, bevor etwas als fertig gilt.

**Nie behaupten, etwas baue, ohne `tools/verify.sh` gelaufen zu haben.**
Swift-Code, der nur "aussieht wie er kompiliert", ist ungeprüfter Code —
sag das dann auch so.

## Konventionen

- **Xcode-Projekt niemals von Hand.** Die `.xcodeproj` ist erzeugt und steht
  in `.gitignore`; die Quelle ist `project.yml`. Neue Datei = Datei anlegen
  und `tools/bootstrap.sh`, kein Gefummel in einer `pbxproj`.
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

- **Kein Offline-Cache in Phase 0–2.** Die Dienste sind aus dem Netz
  erreichbar; ein Cache wäre ein zweiter Datenstand mit eigener
  Konfliktlogik. Erst wenn es weh tut (siehe `docs/ENTSCHEIDUNGEN.md`).
- **Kein Multi-User, keine Registrierung.** Wie in den Backends: eine Person,
  ein Gerät, ein geteiltes Geheimnis.
