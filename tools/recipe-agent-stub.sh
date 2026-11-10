#!/usr/bin/env bash
# Der Rezept-Agent im Kleinen - fuer den Rezept-Chat im Simulator und in UI-Tests.
#
# Beim echten Dienst ist jede Antwort im Rezept-Chat eine Claude-Session auf dem
# Server. Lokal antwortet stattdessen dieses Skript: es liest den Auftrag von der
# Standardeingabe (wie run-agent.sh des Dienstes), wartet zwei Sekunden - damit
# die Blase "Antwort entsteht" zu sehen ist - und gibt immer denselben Vorschlag
# im Umschlag der CLI zurueck.
#
# Den Dienst ../shopping damit lokal starten (eigener Port, eigener Datenordner):
#
#   cd ../shopping && ./gradlew bootJar
#   mkdir -p /tmp/shopping-local && cd /tmp/shopping-local
#   SHOPPING_TOKENS=felix:<ausgedachter Token>,joana:<ausgedachter Token> \
#   SHOPPING_RECIPE_CHAT=felix,joana \
#   SHOPPING_RECIPE_AGENT_COMMAND="<Pfad zu diesem Skript>" \
#   java -jar <../shopping>/build/libs/Shopping-0.0.1-SNAPSHOT.jar --server.port=48941
#
# Und die App dagegen:
#
#   COCKPIT_URL_SHOPPING=http://127.0.0.1:48941/shopping-list \
#   COCKPIT_SHOPPING_TOKEN=<der ausgedachte Token von felix> \
#   COCKPIT_FH_PRIVATE_TOKEN=local-private COCKPIT_WEIGHT_TOKEN=local-weight \
#   COCKPIT_RECIPE="Ofenpasta mit Feta und Tomaten" \
#   tools/uitest.sh Einkaufsliste testRecipeFromChatToCooking
#
# Fuer die Marken in der Kochansicht ("✓ Felix") braucht der lokale Dienst dazu
# einen lokalen Kalorienzaehler (FOOD_URL, SHOPPING_HEALTHY_TOKEN - siehe
# ../shopping/README.md, "Kochen und Healthy"); ohne ihn steht dort, dass Healthy
# das Gericht nicht hat.
set -uo pipefail

# Die Probe des Dienstes beim Start: beweist nur, dass sich das Skript rufen laesst.
if [[ "${1:-}" == "--version" ]]; then
    echo "0.0.0 (Attrappe)"
    exit 0
fi

cat > /dev/null
sleep 2
cat <<'JSON'
{"type": "result", "subtype": "success", "is_error": false, "duration_ms": 2000, "total_cost_usd": 0.0, "result": "{\"reply\": \"Wie wäre es mit einer Ofenpasta? Der Feta schmilzt mit den Tomaten zu einer cremigen Sauce.\", \"recipe\": {\"name\": \"Ofenpasta mit Feta und Tomaten\", \"portions\": 2, \"minutes\": 35, \"ingredients\": [{\"name\": \"Penne\", \"amount\": 250, \"unit\": \"g\", \"pantry\": false}, {\"name\": \"Feta\", \"amount\": 200, \"unit\": \"g\", \"pantry\": false}, {\"name\": \"Cherrytomaten\", \"amount\": 400, \"unit\": \"g\", \"pantry\": false}, {\"name\": \"Knoblauchzehen\", \"amount\": 2, \"unit\": \"Stk\", \"pantry\": false}, {\"name\": \"Olivenöl\", \"amount\": 3, \"unit\": \"EL\", \"pantry\": true}, {\"name\": \"Basilikum\", \"amount\": 1, \"unit\": \"Handvoll\", \"pantry\": false}, {\"name\": \"Salz\", \"amount\": null, \"unit\": null, \"pantry\": true}], \"steps\": [\"Den Ofen auf 200 °C vorheizen.\", \"Tomaten, Knoblauch und Öl in einer Form mischen, den Feta in die Mitte setzen und 25 Minuten backen.\", \"Die Penne kochen und abgießen.\", \"Feta und Tomaten zerdrücken und die Penne unterheben.\"], \"nutrition\": {\"kcal\": 860, \"proteinG\": 33, \"carbsG\": 98, \"fatG\": 36}, \"gramsPerPortion\": 480}}"}
JSON
