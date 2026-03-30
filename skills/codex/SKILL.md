---
name: codex
description: Delegate tasks to OpenAI Codex CLI via tmux. Use when the user asks to use Codex, says "have Codex do this", "ask Codex to", or invokes /codex. Claude acts as an expert prompter, monitors the session, and auto-reviews code output.
version: 0.1.0
---

# Codex Bridge

Delegate tasks to OpenAI Codex CLI running in a tmux session. You are the expert prompter — you construct rich context, send it to Codex as a capable teammate, monitor the session, and review the results.

## When This Skill Activates

- User explicitly asks you to use Codex
- User invokes `/codex <task>`
- NEVER auto-trigger — you do not autonomously spend OpenAI tokens

## Prerequisites

The shell helper script is at `${CLAUDE_PLUGIN_ROOT}/scripts/codex-bridge.sh`. All tmux mechanics go through this script.

## Workflow

### 1. Pre-Flight

Run these checks before anything else:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-bridge.sh" start
```

If this fails, it will tell you what's missing (tmux or codex). Relay that to the user and stop.

### 2. Construct the Prompt

Before sending anything to Codex, build a structured prompt. Codex starts with ZERO context each session — you must provide everything.

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

**Prompting principles:**
- Front-load context — Codex has no memory of prior sessions
- Name exact file paths — never "the main file" or "that module"
- State success criteria — what does "done" look like?
- Include constraints explicitly — Codex in --yolo mode executes anything
- One focused task per session — don't combine unrelated work
- For ideation: prefix with "Don't write any code or modify files. Just discuss:"

### 3. Start Session & Notify User

```bash
SESSION=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-bridge.sh" start)
```

**Immediately tell the user:**
> Codex session started: `<SESSION>`
> Watch live: `tmux attach -t <SESSION>`

### 4. Send the Prompt

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-bridge.sh" send "$SESSION" "<your constructed prompt>"
```

### 5. Supervised Poll Loop

Poll every 5 seconds. Timeout after 5 minutes.

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

If timeout is reached:
- Tell the user Codex has been working for 5 minutes
- Ask: abort or keep waiting?
- If abort: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-bridge.sh" abort "$SESSION"`

### 6. Capture Output

```bash
OUTPUT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-bridge.sh" capture "$SESSION")
```

Read the output. Understand what Codex did.

### 7. Post-Completion

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

### 8. Cleanup

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-bridge.sh" teardown "$SESSION"
```

Tell the user the log location: `.codex-logs/<SESSION>.log`

### 9. Gitignore

On first run, check if `.codex-logs/` is in the project's `.gitignore`. If not, add it.

## Error Handling

| Situation | Action |
|---|---|
| `start` fails (tmux/codex missing) | Tell user what to install, stop |
| Codex never reaches `›` prompt | Timeout, report failure, teardown |
| Codex errors (Traceback, Error:) | Report the error snippet, still save log, teardown |
| Output looks wrong or incomplete | Warn user, provide the log path for manual inspection |
