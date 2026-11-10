#!/usr/bin/env bash
# Prueft, ob ein Tipp auf eine Benachrichtigung die App ueberlebt.
#
#   tools/pushtest.sh <Healthy|Vault|coHabit> [payload.json]
#   tools/pushtest.sh Healthy --chat-open   # „Deine Antwort ist da.“ bei offenem Chat
#
# Der UI-Test kann keine Benachrichtigung erzeugen - das macht dieses Skript
# von aussen mit `simctl push`, waehrend der Test schon wartet. Ohne Nutzlast
# wird die des Kalorienzaehlers genommen (kein `kind`, so wie sie live kommt).
#
# Healthy prueft nach dem Tipp auch, wohin er fuehrt - nach `kind` der Nutzlast
# (seit 10.11.): `chat-answer` oeffnet den Chat, `friend-nudge` und
# `streak-warning` die Freunde, ohne Art der Essen-Tab. Etwa:
#   {"aps":{"alert":{"title":"Healthy","body":"Deine Antwort ist da."}},"kind":"chat-answer"}
#
# `--chat-open` (nur Healthy, mit erfundenen Werten): der Chat steht offen, dann
# kommt `chat-answer` - das darf kein Banner sein - und zehn Sekunden spaeter
# ein Stupser als Gegenprobe; dessen Tipp fuehrt zu den Freunden.
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${DEVICE:-iPhone 17}"
APP="${1:-}"
PAYLOAD="${2:-}"
case "$APP" in
    Healthy) BUNDLE="com.fherrmann.cockpit"
             DEFAULT='{"aps":{"alert":{"title":"Vorschlag ist fertig","body":"Haferbrei – antippen zum Übernehmen."},"sound":"default"}}' ;;
    Vault)   BUNDLE="com.fherrmann.vault"
             DEFAULT='{"aps":{"alert":{"title":"Neue Note 1,7","body":"Datenbanken · Abschlussnote jetzt 1,35"},"sound":"default"},"kind":"grade"}' ;;
    # coHabit: ein Stupser, wie ihn der Dienst schickt - mit Link (Vertrag §4).
    coHabit) BUNDLE="com.fherrmann.cohabit"
             DEFAULT='{"aps":{"alert":{"title":"Lena hat dich angestupst","body":"Heute noch Laufen?"},"sound":"default","thread-id":"c-1"},"kind":"nudge","title":"Lena hat dich angestupst","body":"Heute noch Laufen?","cohabitId":"c-1","link":"cohabit://today"}' ;;
    *) echo "Erste Angabe muss Healthy, Vault oder coHabit sein." >&2; exit 1 ;;
esac
if [ "$PAYLOAD" = "--chat-open" ]; then
    [ "$APP" = "Healthy" ] || { echo "--chat-open gibt es nur fuer Healthy." >&2; exit 1; }
    ANSWER="$(mktemp -t push).json"
    CONTROL="$(mktemp -t push).json"
    echo '{"aps":{"alert":{"title":"Healthy","body":"Deine Antwort ist da."},"sound":"default"},"kind":"chat-answer"}' > "$ANSWER"
    echo '{"aps":{"alert":{"title":"Person A","body":"stupst dich an"},"sound":"default"},"kind":"friend-nudge"}' > "$CONTROL"
    export TEST_RUNNER_COCKPIT_PUSH_TEST=chat-open
    export TEST_RUNNER_COCKPIT_PUSH_TITLE="Person A"
    # Der Test startet mit offenem Chat und wartet bis zu 150 s auf die
    # Gegenprobe. Die Zeit hier deckt Bauen und Start ab.
    tools/uitest.sh Healthy testChatAnswerShowsNoBannerWhileTheChatIsOpen &
    TEST_PID=$!
    sleep 45
    xcrun simctl push "$DEVICE" "$BUNDLE" "$ANSWER"
    sleep 10
    xcrun simctl push "$DEVICE" "$BUNDLE" "$CONTROL"
    wait $TEST_PID
    exit
fi
if [ -z "$PAYLOAD" ]; then
    PAYLOAD="$(mktemp -t push).json"
    echo "$DEFAULT" > "$PAYLOAD"
fi

export TEST_RUNNER_COCKPIT_PUSH_TEST=1
# Den Titel aus der Nutzlast an den Test reichen - der wartet auf genau ihn.
TEST_RUNNER_COCKPIT_PUSH_TITLE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["aps"]["alert"]["title"])' "$PAYLOAD")"
export TEST_RUNNER_COCKPIT_PUSH_TITLE
# Und die Art - nach ihr prueft Healthy, wohin der Tipp fuehrt.
TEST_RUNNER_COCKPIT_PUSH_KIND="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("kind") or "")' "$PAYLOAD")"
export TEST_RUNNER_COCKPIT_PUSH_KIND
# Der Test startet, laesst die App erscheinen, drueckt Home und wartet dann bis
# zu 90 s auf die Benachrichtigung. Die Zeit hier deckt Bauen und Start ab.
tools/uitest.sh "$APP" testTappingAPushNotificationDoesNotCrashTheApp &
TEST_PID=$!
sleep 45
xcrun simctl push "$DEVICE" "$BUNDLE" "$PAYLOAD"
wait $TEST_PID
