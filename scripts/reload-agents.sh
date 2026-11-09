#!/usr/bin/env bash
# Send a slash command (/reload-plugins by default) to every Claude Code
# session Herdr knows that is waiting for input, so a plugin update made on
# this machine reaches all of them at once instead of pane by pane.
#
# Only idle and done agents get it: typing into a working session would land
# in its prompt as the next instruction, and a blocked one is waiting on a
# question. Those are listed, to be reloaded when they are free. Agents of
# other kinds (codex, gemini, ...) have no such command and are left alone.
# The pane this runs in is skipped too.
#
# Usage: reload-agents.sh [command]      exit 0 unless a send failed
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
source "$SCRIPT_DIR/lib.sh"
command_text=${1:-/reload-plugins}

if ! command -v herdr >/dev/null 2>&1; then
    echo 'Herdr is not installed here: nothing to reload.'
    exit 0
fi
listing=$(herdr agent list 2>/dev/null) || { echo 'No Herdr session answered (is one running?).'; exit 0; }

# One line per agent: pane, kind, state. The json is read and the lines are
# written as bytes: Windows Python would decode a pane title as cp1252 and
# end every line with CRLF, and "idle\r" is not idle (seen on 2026-11-09).
rows=$(printf '%s' "$listing" | python3 -c '
import json, sys
try:
    agents = json.load(sys.stdin.buffer)["result"]["agents"]
except Exception:
    sys.exit(0)
for a in agents:
    sys.stdout.buffer.write(("\t".join([a.get("pane_id", ""), a.get("agent", ""), a.get("agent_status", "unknown")]) + "\n").encode("utf-8"))
')
sent=0 failed=0 skipped=()
while IFS=$'\t' read -r pane kind state; do
    state=${state%$'\r'}
    [ -n "$pane" ] || continue
    [ "$kind" = claude ] || continue
    [ "$pane" != "${HERDR_PANE_ID:-}" ] || continue
    case "$state" in
        idle|done)
            if herdr agent prompt "$pane" "$command_text" >/dev/null 2>&1; then
                printf '  sent %-8s %s (%s)\n' "$pane" "$command_text" "$state"; sent=$((sent + 1))
            else
                printf '  FAILED %-6s %s\n' "$pane" "$command_text"; failed=$((failed + 1))
            fi ;;
        *) skipped+=("$pane ($state)") ;;
    esac
done <<< "$rows"
if [ "$sent" -eq 0 ] && [ "$failed" -eq 0 ] && [ "${#skipped[@]}" -eq 0 ]; then
    echo 'No Claude Code session is running under Herdr.'
    exit 0
fi
printf '%s sent to %d idle Claude Code session(s)' "$command_text" "$sent"
[ "$failed" -eq 0 ] || printf ', %d failed' "$failed"
echo .
if [ "${#skipped[@]}" -gt 0 ]; then
    printf 'Not sent, they are busy; run %s there when they are idle: %s\n' "$command_text" "$(IFS=,; echo "${skipped[*]}")"
fi
[ "$failed" -eq 0 ]
