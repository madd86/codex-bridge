#!/usr/bin/env bash
set -euo pipefail

CODEX_LOG_DIR="${CODEX_LOG_DIR:-.codex-logs}"

cmd_start() {
  # Pre-flight checks
  if ! command -v tmux &>/dev/null; then
    echo "ERROR: tmux is not installed" >&2
    exit 1
  fi

  # Resolve codex binary: prefer PATH, fall back to npx
  local codex_cmd
  if command -v codex &>/dev/null; then
    codex_cmd="codex"
  elif command -v npx &>/dev/null && npx --no-install @openai/codex --version &>/dev/null 2>&1; then
    codex_cmd="npx @openai/codex"
  else
    echo "ERROR: codex is not installed (npm install -g @openai/codex)" >&2
    exit 1
  fi

  # Generate unique session name
  local session
  while true; do
    session="codex-session-$(printf '%04d' $((RANDOM % 10000)))"
    if ! tmux has-session -t "$session" 2>/dev/null; then
      break
    fi
  done

  # Create tmux session with large viewport
  tmux new-session -d -s "$session" -x 200 -y 50

  # Launch codex in yolo mode
  tmux send-keys -t "$session" "$codex_cmd --yolo" Enter

  # Wait for trust prompt or input prompt (up to 15s)
  local waited=0
  while [ "$waited" -lt 15 ]; do
    sleep 1
    waited=$((waited + 1))
    local pane_content
    pane_content=$(tmux capture-pane -t "$session" -p 2>/dev/null || true)
    # Trust prompt detected — accept it
    if echo "$pane_content" | grep -q "Do you trust"; then
      tmux send-keys -t "$session" Enter
      sleep 2
      break
    fi
    # Already at input prompt — no trust prompt needed
    if echo "$pane_content" | grep -q "›"; then
      break
    fi
  done

  echo "$session"
}

cmd_teardown() {
  local session="$1"
  mkdir -p "$CODEX_LOG_DIR"
  tmux capture-pane -t "$session" -p -S -5000 > "$CODEX_LOG_DIR/${session}.log" 2>/dev/null || true
  tmux kill-session -t "$session" 2>/dev/null || true
}

# --- Dispatcher ---
case "${1:-}" in
  start)    cmd_start ;;
  teardown) cmd_teardown "${2:?Usage: codex-bridge.sh teardown <session>}" ;;
  *)        echo "Usage: codex-bridge.sh {start|teardown} [args...]" >&2; exit 1 ;;
esac
