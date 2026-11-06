#!/bin/sh
set -u

URL="${URL:-http://localhost:3000}"
: "${GATEWAY_TOKEN:?GATEWAY_TOKEN manquant}"
errors=0

# check <code> <route> <token> [texte attendu]
check() {
    echo "GET $1 $2"
    if [ -n "$3" ]; then
        out=$(curl -s -i -m 10 -H "Authorization: Bearer $3" "$URL$2")
    else
        out=$(curl -s -i -m 10 "$URL$2")
    fi
    echo "$out"
    echo
    code=$(echo "$out" | head -n 1 | awk '{print $2}')
    if [ "$code" != "$1" ] || { [ -n "${4:-}" ] && ! echo "$out" | grep -q "$4"; }; then
        echo "FAIL ($code)"
        errors=$((errors + 1))
    fi
    echo
}

check 200 /health "" '"status":"ok"'
check 401 /users ""
check 401 /users wrong-token
check 200 /users "$GATEWAY_TOKEN" Alice
check 200 /orders "$GATEWAY_TOKEN" Keyboard
check 200 /profile/1 "$GATEWAY_TOKEN" '"id":103'
check 404 /profile/999 "$GATEWAY_TOKEN"

docker compose ps

# compose affiche ":0" quand le port n'est pas publié
for service in users orders; do
    if docker compose port "$service" 8000 | grep -q ':[1-9]'; then
        echo "FAIL: $service est exposé sur l'hôte"
        errors=$((errors + 1))
    fi
done

[ "$errors" -eq 0 ] || exit 1
echo "OK"
