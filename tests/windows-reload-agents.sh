#!/usr/bin/env bash
# Run on Windows through Git Bash (tests/test-windows.ps1): with a fake herdr
# on PATH, scripts/reload-agents.sh must send the command to every idle Claude
# Code session, which failed once because Windows Python ended each listed
# agent's line with CRLF and "idle\r" was taken for a busy state.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
scratch=$(mktemp -d) || exit 1
trap 'rm -rf -- "$scratch"' EXIT
cat > "$scratch/herdr" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$scratch/calls"
case "\$1 \$2" in
    "agent list") echo '{"result":{"agents":[{"pane_id":"w1S:p1","agent":"claude","agent_status":"idle"},{"pane_id":"w1R:p1","agent":"claude","agent_status":"idle"},{"pane_id":"w2:p1","agent":"claude","agent_status":"working"}]}}' ;;
    *) echo '{"result":{}}' ;;
esac
EOF
chmod +x "$scratch/herdr"
# scripts/lib.sh runs the herdr at HERDR_BIN_PATH when it is set: point it at the fake too, never at a live session.
output=$(PATH="$scratch:$PATH" HERDR_BIN_PATH="$scratch/herdr" HERDR_PANE_ID='' bash "$root/scripts/reload-agents.sh") || { echo "reload-agents.sh failed: $output"; exit 1; }
calls=$(grep '^agent prompt' "$scratch/calls")
expected=$'agent prompt w1S:p1 /reload-plugins\nagent prompt w1R:p1 /reload-plugins'
[ "$calls" = "$expected" ] || { printf 'reload-agents.sh sent:\n%s\nexpected:\n%s\noutput:\n%s\n' "$calls" "$expected" "$output"; exit 1; }
case "$output" in *'sent to 2 idle'*'w2:p1 (working)'*) ;; *) printf 'reload-agents.sh said:\n%s\n' "$output"; exit 1 ;; esac
echo 'reload-agents reaches every idle session: passed'
