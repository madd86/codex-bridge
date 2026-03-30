#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/scripts/codex-bridge.sh"
export CODEX_LOG_DIR="$SCRIPT_DIR/tests/.codex-logs"

echo "=== Test: send delivers text and poll detects completion ==="
SESSION=$("$SCRIPT" start)
echo "Session: $SESSION"

# Wait for codex to be ready (› prompt)
echo "Waiting for Codex to be ready..."
WAITED=0
while [ "$WAITED" -lt 30 ]; do
  STATUS=$("$SCRIPT" poll "$SESSION")
  if [ "$STATUS" = "ready" ]; then
    echo "PASS: Codex is ready"
    break
  fi
  sleep 2
  WAITED=$((WAITED + 2))
done
if [ "$STATUS" != "ready" ]; then
  echo "FAIL: Codex never became ready (waited ${WAITED}s)"
  "$SCRIPT" teardown "$SESSION"
  rm -rf "$CODEX_LOG_DIR"
  exit 1
fi

# Send a simple message
"$SCRIPT" send "$SESSION" "hi"

# Wait for response — poll until ready again
echo "Waiting for Codex to respond..."
sleep 3  # Give it a moment to start processing
WAITED=0
while [ "$WAITED" -lt 60 ]; do
  STATUS=$("$SCRIPT" poll "$SESSION")
  if [ "$STATUS" = "ready" ]; then
    echo "PASS: Codex responded (poll returned ready)"
    break
  fi
  sleep 5
  WAITED=$((WAITED + 5))
done
if [ "$STATUS" != "ready" ]; then
  echo "FAIL: Codex did not return to ready state"
  "$SCRIPT" teardown "$SESSION"
  rm -rf "$CODEX_LOG_DIR"
  exit 1
fi

"$SCRIPT" teardown "$SESSION"
rm -rf "$CODEX_LOG_DIR"
echo "=== All tests passed ==="
