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

_get_pane_hash() {
  # Returns a hash of the visible pane content for stability comparison
  tmux capture-pane -t "$1" -p 2>/dev/null | md5 -q 2>/dev/null || tmux capture-pane -t "$1" -p 2>/dev/null | md5sum 2>/dev/null | cut -d' ' -f1
}

_has_working_indicators() {
  # Check for ANY sign of active work in the pane content.
  # These indicators appear during different Codex work phases.
  local pane_content="$1"
  echo "$pane_content" | grep -qE "(Working \(|esc to interrupt|Exploring|Explored|• Ran |• Read |Wrote |Patched |Created )"
}

cmd_poll() {
  local session="$1"
  local pane_content
  pane_content=$(tmux capture-pane -t "$session" -p 2>/dev/null || true)

  if _has_working_indicators "$pane_content"; then
    echo "working"
  elif echo "$pane_content" | grep -q "›"; then
    echo "ready"
  else
    echo "working"
  fi
}

cmd_wait() {
  # Robust wait: polls until Codex is TRULY done.
  # Requires TWO consecutive "ready" polls with STABLE content between them.
  # This prevents false positives during brief gaps between Codex work phases.
  local session="$1"
  local timeout="${2:-300}"  # default 5 minutes
  local waited=0
  local ready_count=0
  local prev_hash=""

  while [ "$waited" -lt "$timeout" ]; do
    local status
    status=$(cmd_poll "$session")

    if [ "$status" = "ready" ]; then
      # Check content stability: is the pane the same as last poll?
      local curr_hash
      curr_hash=$(_get_pane_hash "$session")

      if [ "$ready_count" -gt 0 ] && [ "$curr_hash" = "$prev_hash" ]; then
        # Two consecutive "ready" polls with identical content = truly done
        echo "ready"
        return 0
      fi

      ready_count=$((ready_count + 1))
      prev_hash="$curr_hash"
    else
      # Reset if we see working indicators
      ready_count=0
      prev_hash=""
    fi

    sleep 5
    waited=$((waited + 5))
  done

  echo "timeout"
  return 1
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
  wait)     cmd_wait "${2:?Usage: codex-bridge.sh wait <session> [timeout_seconds]}" "${3:-300}" ;;
  capture)  cmd_capture "${2:?Usage: codex-bridge.sh capture <session>}" ;;
  abort)    cmd_abort "${2:?Usage: codex-bridge.sh abort <session>}" ;;
  save-log) cmd_save_log "${2:?Usage: codex-bridge.sh save-log <session>}" ;;
  teardown) cmd_teardown "${2:?Usage: codex-bridge.sh teardown <session>}" ;;
  *)        echo "Usage: codex-bridge.sh {start|send|poll|wait|capture|abort|save-log|teardown} [args...]" >&2; exit 1 ;;
esac
