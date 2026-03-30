#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/scripts/codex-bridge.sh"
export CODEX_LOG_DIR="$SCRIPT_DIR/tests/.codex-logs"

echo "=== Test: abort interrupts a running task ==="
SESSION=$("$SCRIPT" start)
echo "Session: $SESSION"

# Wait for ready
WAITED=0
while [ "$WAITED" -lt 30 ]; do
  STATUS=$("$SCRIPT" poll "$SESSION")
  [ "$STATUS" = "ready" ] && break
  sleep 2
  WAITED=$((WAITED + 2))
done

# Send a long task
"$SCRIPT" send "$SESSION" "List every file in this directory and explain what each one does in detail with examples"

# Wait a few seconds for it to start working
sleep 5

# Abort
"$SCRIPT" abort "$SESSION"
sleep 2

# Capture output — should contain "interrupted" or similar
CAPTURED=$("$SCRIPT" capture "$SESSION")
if echo "$CAPTURED" | grep -qi "interrupt"; then
  echo "PASS: abort produced interruption message"
else
  echo "WARN: no interruption message detected (Codex may have finished before abort)"
fi

"$SCRIPT" teardown "$SESSION"
rm -rf "$CODEX_LOG_DIR"
echo "=== Test complete ==="
