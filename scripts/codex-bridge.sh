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

  # Wait for trust prompt, update prompt, or input prompt (up to 30s)
  local waited=0
  while [ "$waited" -lt 30 ]; do
    sleep 1
    waited=$((waited + 1))
    local pane_content
    pane_content=$(tmux capture-pane -t "$session" -p 2>/dev/null || true)
    # Trust prompt detected — accept it
    if echo "$pane_content" | grep -q "Do you trust"; then
      tmux send-keys -t "$session" Enter
      sleep 2
      continue
    fi
    # Update available prompt — skip the update (choose option 2)
    if echo "$pane_content" | grep -q "Update available"; then
      tmux send-keys -t "$session" "2" Enter
      sleep 2
      continue
    fi
    # "Press enter to continue" post-update notice — dismiss it
    if echo "$pane_content" | grep -q "Press enter to continue"; then
      tmux send-keys -t "$session" Enter
      sleep 2
      continue
    fi
    # At the real input prompt (› on its own line, not inside a menu)
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

cmd_send() {
  local session="$1"
  local prompt="$2"

  # Use tmux load-buffer for safe prompt injection (handles special characters)
  local tmpfile
  tmpfile=$(mktemp)
  printf '%s' "$prompt" > "$tmpfile"
  tmux load-buffer "$tmpfile"
  tmux paste-buffer -t "$session"
  rm -f "$tmpfile"

  # Double-Enter to submit (Codex TUI requires this)
  sleep 0.5
  tmux send-keys -t "$session" Enter
  sleep 0.5
  tmux send-keys -t "$session" Enter
}

cmd_poll() {
  local session="$1"
  local pane_content
  pane_content=$(tmux capture-pane -t "$session" -p 2>/dev/null || true)

  # Check for the › prompt marker anywhere in the pane (idle state)
  # The Codex TUI renders › at the input line, with status info below it
  if echo "$pane_content" | grep -q "›"; then
    echo "ready"
  else
    echo "working"
  fi
}

cmd_capture() {
  local session="$1"
  tmux capture-pane -t "$session" -p -S -5000
}

cmd_abort() {
  local session="$1"
  tmux send-keys -t "$session" Escape
}

cmd_save_log() {
  local session="$1"
  mkdir -p "$CODEX_LOG_DIR"
  tmux capture-pane -t "$session" -p -S -5000 > "$CODEX_LOG_DIR/${session}.log"
}

# --- Dispatcher ---
case "${1:-}" in
  start)    cmd_start ;;
  send)     cmd_send "${2:?Usage: codex-bridge.sh send <session> <prompt>}" "${3:?}" ;;
  poll)     cmd_poll "${2:?Usage: codex-bridge.sh poll <session>}" ;;
  capture)  cmd_capture "${2:?Usage: codex-bridge.sh capture <session>}" ;;
  abort)    cmd_abort "${2:?Usage: codex-bridge.sh abort <session>}" ;;
  save-log) cmd_save_log "${2:?Usage: codex-bridge.sh save-log <session>}" ;;
  teardown) cmd_teardown "${2:?Usage: codex-bridge.sh teardown <session>}" ;;
  *)        echo "Usage: codex-bridge.sh {start|send|poll|capture|abort|save-log|teardown} [args...]" >&2; exit 1 ;;
esac
