#!/usr/bin/env bash
# Prueft, ob ein Tipp auf eine Benachrichtigung die App ueberlebt.
#
#   tools/pushtest.sh [payload.json]
#
# Der UI-Test kann keine Benachrichtigung erzeugen - das macht dieses Skript
# von aussen mit `simctl push`, waehrend der Test schon wartet. Ohne Nutzlast
# wird die des Kalorienzaehlers genommen (kein `kind`, so wie sie live kommt).
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${DEVICE:-iPhone 17}"
PAYLOAD="${1:-}"
if [ -z "$PAYLOAD" ]; then
    PAYLOAD="$(mktemp -t push).json"
    echo '{"aps":{"alert":{"title":"Vorschlag ist fertig","body":"Haferbrei – antippen zum Übernehmen."},"sound":"default"}}' > "$PAYLOAD"
fi

export TEST_RUNNER_COCKPIT_PUSH_TEST=1
# Den Titel aus der Nutzlast an den Test reichen - der wartet auf genau ihn.
TEST_RUNNER_COCKPIT_PUSH_TITLE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["aps"]["alert"]["title"])' "$PAYLOAD")"
export TEST_RUNNER_COCKPIT_PUSH_TITLE
# Der Test startet, laesst die App erscheinen, drueckt Home und wartet dann bis
# zu 90 s auf die Benachrichtigung. Die Zeit hier deckt Bauen und Start ab.
tools/uitest.sh testTappingAPushNotificationDoesNotCrashTheApp &
TEST_PID=$!
sleep 45
xcrun simctl push "$DEVICE" com.fherrmann.cockpit "$PAYLOAD"
wait $TEST_PID
