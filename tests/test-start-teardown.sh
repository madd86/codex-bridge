#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/scripts/codex-bridge.sh"

echo "=== Test: start creates a tmux session ==="
SESSION=$("$SCRIPT" start)
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "FAIL: session $SESSION does not exist"
  exit 1
fi
echo "PASS: session $SESSION exists"

echo "=== Test: teardown kills the session and creates a log ==="
LOG_DIR="$SCRIPT_DIR/tests/.codex-logs"
export CODEX_LOG_DIR="$LOG_DIR"
"$SCRIPT" teardown "$SESSION"
if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "FAIL: session $SESSION still exists after teardown"
  exit 1
fi
echo "PASS: session $SESSION killed"

LOG_FILE="$LOG_DIR/${SESSION}.log"
if [ ! -f "$LOG_FILE" ]; then
  echo "FAIL: log file $LOG_FILE not created"
  exit 1
fi
echo "PASS: log file $LOG_FILE created"

# Cleanup
rm -rf "$LOG_DIR"
echo "=== All tests passed ==="
