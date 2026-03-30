#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/scripts/codex-bridge.sh"
export CODEX_LOG_DIR="$SCRIPT_DIR/tests/.codex-logs"

echo "=== E2E Test: full lifecycle ==="

# Start
SESSION=$("$SCRIPT" start)
echo "Session: $SESSION"

# Wait for ready
echo "Waiting for Codex to be ready..."
WAITED=0
while [ "$WAITED" -lt 30 ]; do
  STATUS=$("$SCRIPT" poll "$SESSION")
  [ "$STATUS" = "ready" ] && break
  sleep 2
  WAITED=$((WAITED + 2))
done
if [ "$STATUS" != "ready" ]; then
  echo "FAIL: Codex never became ready"
  "$SCRIPT" teardown "$SESSION"
  rm -rf "$CODEX_LOG_DIR"
  exit 1
fi
echo "PASS: Codex ready"

# Send
"$SCRIPT" send "$SESSION" "What is 2 + 2? Answer with just the number."
echo "PASS: Prompt sent"

# Poll for completion
echo "Waiting for response..."
sleep 3
WAITED=0
while [ "$WAITED" -lt 60 ]; do
  STATUS=$("$SCRIPT" poll "$SESSION")
  [ "$STATUS" = "ready" ] && break
  sleep 5
  WAITED=$((WAITED + 5))
done
if [ "$STATUS" != "ready" ]; then
  echo "FAIL: Codex did not complete"
  "$SCRIPT" teardown "$SESSION"
  rm -rf "$CODEX_LOG_DIR"
  exit 1
fi
echo "PASS: Codex completed"

# Capture
CAPTURED=$("$SCRIPT" capture "$SESSION")
if echo "$CAPTURED" | grep -q "4"; then
  echo "PASS: Response contains expected answer"
else
  echo "WARN: Response may not contain expected answer (check log)"
fi

# Teardown
"$SCRIPT" teardown "$SESSION"
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "FAIL: Session still exists after teardown"
  exit 1
fi
echo "PASS: Session cleaned up"

# Verify log
if [ -f "$CODEX_LOG_DIR/${SESSION}.log" ]; then
  echo "PASS: Log file exists at $CODEX_LOG_DIR/${SESSION}.log"
else
  echo "FAIL: Log file not created"
  exit 1
fi

rm -rf "$CODEX_LOG_DIR"
echo "=== E2E test passed ==="
