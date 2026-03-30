---
name: codex
description: Delegate tasks to OpenAI Codex CLI via tmux. Use when the user asks to use Codex, says "have Codex do this", "ask Codex to", or invokes /codex. Claude acts as an expert prompter, monitors the session, and auto-reviews code output.
version: 0.2.0
---

# Codex Bridge

Delegate tasks to OpenAI Codex CLI running in a tmux session. You are the expert prompter — you construct rich context, send it to Codex as a capable teammate, monitor the session, and review the results.

## CRITICAL RULES

<EXTREMELY_IMPORTANT>
You MUST follow the tmux-based workflow below. You MUST NOT:
- Do the work yourself instead of delegating to Codex
- Skip the tmux session and try to run codex directly
- Bail out because "codex isn't installed" without trying the shell helper first (it handles npx fallback)
- Abandon the workflow partway through
- Return Codex's raw output without reviewing it

If the shell helper's `start` command fails, THAT is when you tell the user what's missing. Not before. Do not check for codex on PATH yourself — the shell helper does that.
</EXTREMELY_IMPORTANT>

## When This Skill Activates

- User explicitly asks you to use Codex
- User invokes `/codex <task>`
- NEVER auto-trigger — you do not autonomously spend OpenAI tokens

## Prerequisites

The shell helper script is at `${CLAUDE_PLUGIN_ROOT}/scripts/codex-bridge.sh`. All tmux mechanics go through this script. Do NOT run tmux commands directly — always use the script.

## Workflow

Follow these steps IN ORDER. Do not skip steps. Do not combine steps.

### Step 1: Pre-Flight

```bash
SESSION=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-bridge.sh" start)
```

If this fails, relay the error to the user and STOP. If it succeeds, it returns a session name like `codex-session-7781`.

### Step 2: Notify User

**Immediately** tell the user (before doing anything else):

> Codex session started: `codex-session-XXXX`
> Watch live: `tmux attach -t codex-session-XXXX`

### Step 3: Construct the Prompt

Before sending anything to Codex, build a structured prompt. Codex starts with ZERO context each session — you must provide everything it needs to succeed.

**Prompt template:**

```
[CONTEXT]
- Working directory: <absolute path>
- Relevant files: <list exact file paths Codex needs>
- Recent changes: <brief summary if relevant>
- Project conventions: <patterns, naming, style>

[TASK]
<Clear, specific description. State what "done" looks like.>

[CONSTRAINTS]
- <Boundaries: don't modify X, use Y pattern, etc.>
```

**Prompting principles — you are an expert prompter:**
- **Front-load context** — Codex has no memory of prior sessions. Include file contents if they're short and critical.
- **Name exact file paths** — never "the main file" or "that module"
- **State success criteria** — what does "done" look like?
- **Include constraints explicitly** — Codex in --yolo mode executes anything, so guardrails go in the prompt
- **One focused task per session** — don't combine unrelated work
- **For ideation only:** prefix with "Don't write any code or modify files. Just discuss:"

### Step 4: Send the Prompt

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-bridge.sh" send "$SESSION" "<your constructed prompt>"
```

The send command includes a built-in 5-second delay after submission. Do NOT poll immediately after calling send — the delay is handled internally.

### Step 5: Supervised Poll Loop

Poll every 5 seconds until Codex finishes. Timeout after 5 minutes.

```bash
WAITED=0
while [ "$WAITED" -lt 300 ]; do
  STATUS=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-bridge.sh" poll "$SESSION")
  if [ "$STATUS" = "ready" ]; then
    break
  fi
  sleep 5
  WAITED=$((WAITED + 5))
done
```

**IMPORTANT polling notes:**
- The poll command checks for working indicators (like "Working", "esc to interrupt"). It returns `ready` only when Codex is truly idle.
- If poll returns `ready` after just a few seconds, **verify by capturing output** — if the capture doesn't show a Codex response to your prompt, the prompt may not have been submitted. Re-send it.
- If timeout (5 min) is reached: tell the user, ask whether to abort or keep waiting.
- To abort: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-bridge.sh" abort "$SESSION"`

### Step 6: Capture Output

```bash
OUTPUT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-bridge.sh" capture "$SESSION")
```

Read the output carefully. Understand what Codex did. Look for:
- Codex's response text (after the `›` prompt line where your message was)
- Any commands it ran (lines starting with `• Ran`)
- Any files it created/modified (look for diff output)
- Any errors (Traceback, Error:, FATAL)

### Step 7: Post-Completion

**For code tasks (Codex created or modified files):**
1. Run `git status` and `git diff` to identify what changed
2. Fire two agents **in parallel**:
   - `code-simplifier` agent — to simplify Codex's output
   - `feature-dev:code-reviewer` agent — to review for bugs, logic errors, security
3. Synthesize and report to user:
   - What Codex did (brief summary)
   - What reviewers found (issues, if any)
   - What was simplified (if anything)

**For ideation/discussion tasks (no file changes):**
1. Summarize Codex's response — distill key points, don't relay verbatim

### Step 8: Cleanup

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-bridge.sh" teardown "$SESSION"
```

Tell the user: `Session log saved to .codex-logs/<SESSION>.log`

### Step 9: Gitignore

On first run, check if `.codex-logs/` is in the project's `.gitignore`. If not, add it.

## Error Handling

| Situation | Action |
|---|---|
| `start` fails (tmux/codex missing) | Tell user what to install, STOP |
| Poll returns `ready` suspiciously fast (<10s) | Capture and verify — re-send if no response visible |
| Codex never finishes (5min timeout) | Ask user: abort or wait? |
| Codex errors (Traceback, Error:) | Report error snippet, save log, teardown |
| Output looks wrong or incomplete | Warn user, provide log path for manual inspection |

## Troubleshooting

**"Codex isn't installed"** — Do NOT check for codex yourself. Run the `start` command. It handles PATH resolution and npx fallback. Only if `start` fails should you report the error.

**Poll returns ready immediately** — The send command has a built-in 5s delay, but if Codex hasn't started processing yet, poll may see the idle prompt. Capture and verify. If no response is visible, wait 10 more seconds and poll again.

**Prompt wasn't submitted** — The send command uses double-Enter. If the capture shows your prompt text sitting in the input line without a Codex response below it, send another Enter: `tmux send-keys -t "$SESSION" Enter`
