# Stand

> **Nächster Schritt:** M2 — der Essen-Tab wird nativ. Tagesansicht,
> Gerichte-Merkliste, Schnellerfassung. Endpunkte in `docs/BACKENDS.md`.
>
> ⚠️ **Terminsache:** das Provisioning-Profil läuft am **8. September 2026,
> 18:41 Uhr** ab (Personal Team). Bis dahin sollte die bezahlte Mitgliedschaft
> stehen — dann `DEVELOPMENT_TEAM` in `project.yml` tauschen und neu
> installieren, sonst startet die App nicht mehr.

## Phase 0 — Gerüst · **fertig** (2026-09-01)

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
- [x] **`tools/verify.sh` grün**: Build plus 6 Tests im Simulator
      (iPhone 17, iOS 26.5), `** TEST SUCCEEDED **`
- [x] **Startet auch wirklich**: im Simulator installiert und gestartet, die
      App zeigt die vier Tabs und springt ohne hinterlegte Token von selbst
      in den Zugang-Bildschirm
- [x] **Auf dem iPhone installiert** (iPhone 16 Pro, per `devicectl`).
      Signiert mit dem **Personal Team** `ZWFV263P59` — die Aufnahme ins
      Apple Developer Program lief zu dem Zeitpunkt noch (Apple zeigt bis
      zur Freigabe nur eine Enrollment-ID, noch keine Team-ID).
      ⚠️ **Damit laufen App und Zertifikat nach sieben Tagen ab.** Sobald die
      Mitgliedschaft steht: `DEVELOPMENT_TEAM` in `project.yml` auf die
      Team-ID der bezahlten Mitgliedschaft umstellen, dann gilt ein Jahr.
- [ ] Erststart auf dem Gerät: das Entwicklerprofil muss am iPhone unter
      *Einstellungen → Allgemein → VPN & Geräteverwaltung* einmal als
      vertrauenswürdig bestätigt werden. Ohne das verweigert iOS den Start
      (`FBSOpenApplicationServiceErrorDomain error 1`) — nicht
      automatisierbar, das ist so gewollt

Zwei Fallen dabei, beide behoben:

* `GENERATE_INFOPLIST_FILE` gehört auf **Projektebene**. Stand es nur beim
  App-Target, scheiterte das Test-Bundle am Signieren — mit einer Meldung,
  die nach einem Fehler im App-Target aussah.
* `tools/verify.sh` erzeugte das Projekt nur, **wenn es fehlte**. Eine
  Änderung an `project.yml` kam so nie an, und man sucht den Fehler im Code
  statt im Projektstand. Es erzeugt jetzt immer neu.

## M1 — Gewicht nativ · **fertig** (2026-09-01)

- [x] Modelle `WeightPoint`, `WeightSummary`, `Vacation`, `DashboardConfig`
- [x] `WeightAPI` — alle Endpunkte des Weight Trackers
- [x] Verlaufsdiagramm mit Swift Charts: Messwerte, 7-Tage-Mittel, Zielkurve,
      Zielkorridor als Band, Urlaube als Hintergrundfläche
- [x] Unvollständige Mittel gepunktet — Logik in `WeightChartData`, damit sie
      testbar ist, mit fünf Tests
- [x] Gewicht eintragen (Blatt mit Datum + Dezimalfeld), Ziel ändern
- [x] Alle 18 Kacheln der Web-Registry, Zusätze über `/api/dashboard`
      hinzufügbar und per Kontextmenü entfernbar
- [x] **App-Icon** — erzeugt von `tools/make-icon.swift`
- [x] Fehlerbanner, das ein Zugangsproblem von einem sonstigen Fehler
      unterscheidet
- [x] 21 Tests grün

## M2 — Essen nativ · offen

- [ ] Modelle `Nutrients`, `Dish`, `FoodEntry`, `DaySummary`, `DayTotal`
- [ ] Tagesansicht nach Mahlzeiten, Tacho-Anzeigen
- [ ] Gerichte-Merkliste (CRUD)
- [ ] Schnellerfassung: Auftrag abschicken, pollen, Vorschau bestätigen
      (`/features` vorher abfragen)
- [ ] Verlaufsdiagramm `\/daily` + Gewichtskurve darüber

## M3 — was nativ erst möglich macht · offen

- [ ] HealthKit: Gewicht aus Apple Health lesen/schreiben
- [ ] Widget: Restkalorien heute
- [ ] App Intent / Shortcut für die Schnellerfassung („Hey Siri, …")
- [ ] Face-ID-Sperre vor dem Finanzen-Tab

## Offene Fragen

- Apple Developer Program (99 €/Jahr) — ohne läuft die App nach 7 Tagen ab.
- Bundle-ID ist `com.fherrmann.cockpit`. Ändern heißt: neues Profil, App neu
  installieren.
