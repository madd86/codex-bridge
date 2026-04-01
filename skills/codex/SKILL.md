---
name: codex
description: Delegate tasks to OpenAI Codex CLI via tmux. Use when the user asks to use Codex, says "have Codex do this", "ask Codex to", or invokes /codex. Claude acts as an expert prompter, monitors the session, and auto-reviews code output.
version: 0.4.0
---

# Codex Bridge

Delegate tasks to OpenAI Codex CLI running in a **tmux session**. Codex ALWAYS runs inside tmux — never directly. You are the expert prompter — you construct rich context, send it to Codex as a capable teammate, monitor the tmux session, and review the results.

## CRITICAL RULES

<EXTREMELY_IMPORTANT>

**Codex runs inside tmux. Always. No exceptions.**

You MUST:
- Use the shell helper script for ALL Codex interactions (start, send, poll, capture, teardown)
- Follow every step of the workflow below, in order, completely
- Let the shell helper handle codex binary resolution — it launches codex inside tmux where the user's shell PATH is available

You MUST NOT:
- Do the work yourself instead of delegating to Codex
- Try to run codex directly (not via tmux)
- Check if codex is on PATH yourself — the tmux session inherits the user's login shell where codex is installed
- Search for codex binaries, run `which codex`, `command -v codex`, `npm list`, or any other binary detection
- Bail out and do the work yourself if something goes wrong — report the error to the user instead
- Abandon the workflow partway through
- Return Codex's raw output without reviewing it

**If you are about to do the work yourself instead of delegating to Codex: STOP. That defeats the entire purpose of this skill.**

</EXTREMELY_IMPORTANT>

## When This Skill Activates

- User explicitly asks you to use Codex
- User invokes `/codex <task>`
- NEVER auto-trigger — you do not autonomously spend OpenAI tokens

## Finding the Shell Helper

The shell helper script is at `${CLAUDE_PLUGIN_ROOT}/scripts/codex-bridge.sh`.

If `${CLAUDE_PLUGIN_ROOT}` is not set, find the script:
```bash
find ~/.claude/plugins/cache -name "codex-bridge.sh" -path "*/scripts/*" 2>/dev/null | head -1
```

Store the result and use it for all subsequent commands. Do NOT run tmux commands directly — always go through the script.

## Workflow

Follow these steps IN ORDER. Do not skip steps. Do not combine steps.

### Step 1: Pre-Flight — Start the tmux session

```bash
SCRIPT="${CLAUDE_PLUGIN_ROOT}/scripts/codex-bridge.sh"
SESSION=$(bash "$SCRIPT" start)
```

This creates a tmux session, launches `codex --yolo` inside it, and handles startup prompts (trust, updates). It returns a session name like `codex-session-7781`.

If this fails, relay the error to the user and STOP. Do NOT fall back to doing the work yourself.

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
bash "$SCRIPT" send "$SESSION" "<your constructed prompt>"
```

The send command includes a built-in 5-second delay after submission. Do NOT poll immediately after calling send — the delay is handled internally.

### Step 5: Wait for Completion

Use the `wait` command — it handles all polling robustly. It requires **two consecutive stable "ready" polls** to prevent false positives during brief gaps between Codex work phases.

```bash
RESULT=$(bash "$SCRIPT" wait "$SESSION" 300)
```

- Returns `ready` when Codex is truly done (two consecutive stable polls).
- Returns `timeout` after 300 seconds (5 minutes). You can pass a different timeout as the third argument.
- If timeout: tell the user, ask whether to abort or keep waiting.
- To abort: `bash "$SCRIPT" abort "$SESSION"`
- To keep waiting: run `wait` again with a new timeout.

**This is a blocking call.** It will take at least 10 seconds to return "ready" (two polls at 5s intervals). This is by design — it prevents false positives.

### Step 6: Capture Output

```bash
OUTPUT=$(bash "$SCRIPT" capture "$SESSION")
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
bash "$SCRIPT" teardown "$SESSION"
```

Tell the user: `Session log saved to .codex-logs/<SESSION>.log`

### Step 9: Gitignore

On first run, check if `.codex-logs/` is in the project's `.gitignore`. If not, add it.

## Error Handling

| Situation | Action |
|---|---|
| `start` fails | Tell user the error, STOP. Do NOT do the work yourself. |
| `wait` returns `timeout` | Ask user: abort or keep waiting? |
| Codex errors (Traceback, Error:) in captured output | Report error snippet, save log, teardown |
| Captured output shows no response to your prompt | The prompt may not have submitted. Send another Enter and wait again. |
| Output looks wrong or incomplete | Warn user, provide log path for manual inspection |

**NEVER bail and do the work yourself.** If Codex fails, report the failure to the user and let them decide next steps.

## Troubleshooting

**Script not found at `${CLAUDE_PLUGIN_ROOT}`** — Use the find command: `find ~/.claude/plugins/cache -name "codex-bridge.sh" -path "*/scripts/*" 2>/dev/null | head -1`

**`start` fails** — Codex runs inside tmux which inherits the user's login shell. Ask the user to verify `codex --version` works in their terminal.

**`wait` returns `timeout`** — Codex may still be working on a long task. Ask the user if they want to abort or extend the timeout. Do NOT tear down the session without asking.

**Prompt wasn't submitted** — If captured output shows your prompt text in the input line without a Codex response below it, submit it: `tmux send-keys -t "$SESSION" Enter`
