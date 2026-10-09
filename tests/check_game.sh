#!/bin/sh
# Runs the headless game check (tests/check_game.gd).
#
# Passes only when the check prints "check_game: OK". Godot's exit code cannot be trusted
# for this: a script that fails to compile never runs, and a script error aborts a check
# without failing it. In both cases Godot would otherwise sit idle, so --quit-after ends
# the run and the missing OK line fails it.
#
# Override the Godot binary with the GODOT environment variable.

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MAX_FRAMES=900

output="$("$GODOT" --headless --path "$PROJECT_DIR" --quit-after "$MAX_FRAMES" res://tests/check_game.tscn 2>&1)"
printf '%s\n' "$output" | grep -E 'FAIL|ERROR|check_game:'
if printf '%s\n' "$output" | grep -q '^check_game: OK$'; then
    exit 0
fi
echo "check_game: did not report OK" >&2
exit 1
