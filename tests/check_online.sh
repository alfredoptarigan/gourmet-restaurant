#!/bin/sh
# Runs the game's Api client against a real server (tests/check_online.gd).
#
# Starts server/ on a spare port against the test database, runs the headless check, and
# stops the server again. Needs PostgreSQL with the _test database from server/.env.example.
# Passes only when the check prints "check_online: OK" (see check_game.sh for why).
#
# Override the Godot binary with GODOT and the database with TEST_DATABASE_URL.

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${CHECK_ONLINE_PORT:-3199}"
DATABASE="${TEST_DATABASE_URL:-postgres://localhost/gourmet_street_test}"
MAX_FRAMES=3000
STARTUP_ATTEMPTS=50

case "$DATABASE" in
    *_test) ;;
    *) echo "check_online: refusing to use $DATABASE: the database name must end in _test" >&2; exit 1 ;;
esac

server_log="$(mktemp)"
(cd "$PROJECT_DIR/server" && DATABASE_URL="$DATABASE" PORT="$PORT" exec node src/index.ts) > "$server_log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null; wait "$server_pid" 2>/dev/null; rm -f "$server_log"' EXIT

attempt=0
until curl -s -o /dev/null "http://localhost:$PORT/health"; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$STARTUP_ATTEMPTS" ] || ! kill -0 "$server_pid" 2>/dev/null; then
        echo "check_online: the server did not start:" >&2
        cat "$server_log" >&2
        exit 1
    fi
    sleep 0.2
done

output="$(GOURMET_SERVER_URL="http://localhost:$PORT" "$GODOT" --headless --path "$PROJECT_DIR" --quit-after "$MAX_FRAMES" res://tests/check_online.tscn 2>&1)"
printf '%s\n' "$output" | grep -E 'FAIL|ERROR|check_online:'
if printf '%s\n' "$output" | grep -q '^check_online: OK$'; then
    exit 0
fi
echo "check_online: did not report OK" >&2
exit 1
