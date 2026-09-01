# Cockpit

Eine iOS-App für Felix' drei Heimserver-Dienste unter einem Icon:
**Essen** (Kalorienzähler), **Gewicht** (Weight Tracker) und **Finanzen**
(Finance Cockpit).

Die Backends bleiben unverändert und laufen weiter im Browser — das hier ist
nur ein zweiter Client. Bundle-ID `com.fherrmann.cockpit`.

| | |
|---|---|
| **Stand** | Phase 0, Gerüst steht, **noch nicht gebaut** — siehe [`docs/STAND.md`](docs/STAND.md) |
| **Aufbau** | [`docs/ARCHITEKTUR.md`](docs/ARCHITEKTUR.md) |
| **APIs der Backends** | [`docs/BACKENDS.md`](docs/BACKENDS.md) |
| **Warum es so ist, wie es ist** | [`docs/ENTSCHEIDUNGEN.md`](docs/ENTSCHEIDUNGEN.md) |
| **Arbeitsregeln (auch für Claude)** | [`CLAUDE.md`](CLAUDE.md) |

## Schnellstart

```bash
tools/bootstrap.sh          # prueft Xcode, holt XcodeGen, erzeugt Cockpit.xcodeproj
open Cockpit.xcodeproj
tools/verify.sh             # bauen + Tests, ohne Xcode-Fenster
```

Voraussetzungen, in dieser Reihenfolge:

1. **Xcode** aus dem App Store (~10–15 GB). Die Command Line Tools allein
   reichen nicht — ohne Xcode gibt es kein iOS-SDK und keinen Simulator.
   Danach einmal `sudo xcode-select -s /Applications/Xcode.app`.
2. **XcodeGen** (`brew install xcodegen`) — macht `tools/bootstrap.sh` bei
   Bedarf selbst.
3. **Apple Developer Program** (99 €/Jahr), sobald die App dauerhaft aufs
   Gerät soll. Mit einer freien Apple-ID lässt sie sich zwar installieren,
   läuft aber nach **7 Tagen** ab und muss neu aus Xcode geladen werden.

## Erste Einrichtung auf dem Gerät

Beim ersten Start fragt die App zwei Token ab; sie landen im Keychain und
werden von da an als Cookies gesetzt:

| Token | Wofür | Wo er steht (auf dem Server) |
|---|---|---|
| `fh_private` | Essen-Tab (und alles unter `.fherrmann.com`) | `/etc/nginx/conf.d/private-mode.conf` |
| `weight_app_token` | Gewicht-Tab | `/etc/health-viz.env` |

Der Finanzen-Tab hat kein Token: dort meldet man sich im WebView mit Passwort
und TOTP-Code an, das Session-Cookie hält 7 Tage und verlängert sich bei
Nutzung.
