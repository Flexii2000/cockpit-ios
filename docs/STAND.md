# Stand

> **Nächster Schritt:** warten, bis die iOS-Simulator-Runtime geladen ist
> (`xcodebuild -downloadPlatform iOS`, 8,52 GB), dann `tools/verify.sh`.
> Ohne installierte Plattform findet `xcodebuild` **gar keine Destination** —
> weder Simulator noch Gerät, auch nicht mit `-sdk iphoneos`.

## Phase 0 — Gerüst · in Arbeit

- [x] Repo, Doku, `.gitignore`
- [x] `project.yml` (XcodeGen), `tools/bootstrap.sh`, `tools/verify.sh`
- [x] Tab-Gerüst mit drei WebView-Tabs
- [x] Keychain + Cookie-Injektion (WebView **und** URLSession)
- [x] Einrichtungs-Bildschirm für die beiden Token
- [x] `APIClient` inkl. Datums-Dekodierung für Spring (`LocalDate` + `Instant`)
- [x] Xcode 26.6 eingerichtet, XcodeGen 2.46, `Cockpit.xcodeproj` erzeugt
- [x] **Typprüfung sauber**: der gesamte App-Code gegen das
      iOS-26.5-Simulator-SDK, Swift 6 mit `-strict-concurrency=complete`,
      keine Fehler und keine Warnungen:
      ```
      xcrun --sdk iphonesimulator swiftc -typecheck \
        -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
        -target arm64-apple-ios18.0-simulator \
        -swift-version 6 -strict-concurrency=complete Cockpit/**/*.swift
      ```
      Das ist der Ersatzbeleg, solange die Runtime fehlt — es ersetzt
      `tools/verify.sh` **nicht**: gelinkt wurde nichts, und die Tests in
      `Tests/` sind damit nicht abgedeckt (`@testable import` braucht das
      gebaute Modul).
- [ ] `tools/verify.sh` grün (Build + Tests im Simulator)
      ← blockiert durch die laufende Runtime-Installation
- [ ] Läuft auf dem Gerät (braucht Apple-Developer-Account)

## Phase 1 — Gewicht nativ · offen

- [ ] Modelle `WeightPoint`, `WeightSummary`, `Vacation`
- [ ] `WeightAPI` (6 GET, 1 PUT, 1 POST — siehe `docs/BACKENDS.md`)
- [ ] Verlaufsdiagramm mit Swift Charts: Messpunkte, Schnitte 7/14/30,
      Zielkurve, Korridor, Urlaubs-Bänder
- [ ] Unvollständige Schnitte gestrichelt (`avg7Complete` etc.)
- [ ] Gewicht eintragen, Ziel ändern
- [ ] Kacheln aus `/api/dashboard`

## Phase 2 — Essen nativ · offen

- [ ] Modelle `Nutrients`, `Dish`, `FoodEntry`, `DaySummary`, `DayTotal`
- [ ] Tagesansicht nach Mahlzeiten, Tacho-Anzeigen
- [ ] Gerichte-Merkliste (CRUD)
- [ ] Schnellerfassung: Auftrag abschicken, pollen, Vorschau bestätigen
      (`/features` vorher abfragen)
- [ ] Verlaufsdiagramm `\/daily` + Gewichtskurve darüber

## Phase 3 — was nativ erst möglich macht · offen

- [ ] HealthKit: Gewicht aus Apple Health lesen/schreiben
- [ ] Widget: Restkalorien heute
- [ ] App Intent / Shortcut für die Schnellerfassung („Hey Siri, …")
- [ ] Face-ID-Sperre vor dem Finanzen-Tab

## Offene Fragen

- Apple Developer Program (99 €/Jahr) — ohne läuft die App nach 7 Tagen ab.
- Bundle-ID ist `com.fherrmann.cockpit`. Ändern heißt: neues Profil, App neu
  installieren.
