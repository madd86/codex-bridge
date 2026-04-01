#!/usr/bin/env bash
set -euo pipefail

CODEX_LOG_DIR="${CODEX_LOG_DIR:-.codex-logs}"

cmd_start() {
  # Pre-flight: tmux is required
  if ! command -v tmux &>/dev/null; then
    echo "ERROR: tmux is not installed. Install with: brew install tmux" >&2
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

  # Create tmux session with large viewport.
  # Codex MUST run inside tmux — never run it directly.
  # The tmux session inherits the user's login shell environment where codex is on PATH.
  tmux new-session -d -s "$session" -x 200 -y 50

  # Launch codex in yolo mode inside the tmux session
  tmux send-keys -t "$session" 'codex --yolo' Enter

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

  # Mandatory delay: give Codex time to start processing before poll begins.
  # Without this, poll sees the › placeholder and returns "ready" immediately.
  sleep 5
}

cmd_poll() {
  local session="$1"
  local pane_content
  pane_content=$(tmux capture-pane -t "$session" -p 2>/dev/null || true)

  # IMPORTANT: The › character appears in Codex's TUI in BOTH idle and working states
  # (it's the suggestion placeholder line). We must check for WORKING indicators instead.
  #
  # Working indicators:
  #   "Working ("          — e.g. "Working (13s • esc to interrupt)"
  #   "esc to interrupt"   — appears during active processing
  #   "Exploring"          — appears when Codex is exploring files
  #   "Explored"           — appears right after exploration
  #   "• Ran "             — appears when Codex ran a command
  #
  # The session is "ready" only when:
  #   1. The › prompt IS present (Codex is loaded), AND
  #   2. No working indicators are present

  if echo "$pane_content" | grep -qE "(Working \(|esc to interrupt|Exploring|• Ran )"; then
    echo "working"
  elif echo "$pane_content" | grep -q "›"; then
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
