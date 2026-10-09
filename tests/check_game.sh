#!/bin/sh
# Runs the headless game check (tests/check_game.gd).
#
# Passes only when the check prints "check_game: OK" and no script error. Godot's exit code
# cannot be trusted for this: a script that fails to compile never runs, and a script error
# aborts a function without failing the check, which may still go on to print OK. So any
# SCRIPT ERROR line fails the run, and --quit-after ends a run that never reports.
#
# Override the Godot binary with the GODOT environment variable.

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MAX_FRAMES=900

output="$("$GODOT" --headless --path "$PROJECT_DIR" --quit-after "$MAX_FRAMES" res://tests/check_game.tscn 2>&1)"
printf '%s\n' "$output" | grep -E 'FAIL|ERROR|check_game:'
if printf '%s\n' "$output" | grep -q 'SCRIPT ERROR'; then
    echo "check_game: a script error happened" >&2
    exit 1
fi
if printf '%s\n' "$output" | grep -q '^check_game: OK$'; then
    exit 0
fi
echo "check_game: did not report OK" >&2
exit 1
