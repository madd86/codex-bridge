---
description: Delegate a task to OpenAI Codex CLI via tmux
argument-hint: Task description for Codex
allowed-tools: ["Bash", "Read", "Grep", "Glob", "Agent", "Skill"]
---

# /codex — Delegate to Codex

**FIRST:** Load the `codex-bridge:codex` skill using the Skill tool to get the full workflow.

Then follow the skill workflow EXACTLY — all 9 steps, in order:
1. Pre-flight (`start` command — do NOT check for codex yourself)
2. Notify user with session name and attach command
3. Construct expert prompt with full context
4. Send prompt via the shell helper
5. Supervised poll loop (5s intervals, 5min timeout)
6. Capture and review output
7. Post-completion (code review agents for code tasks, summarize for ideation)
8. Cleanup (teardown + report log path)
9. Gitignore check

The user's task description is provided as the argument to this command. Use it as the basis for the [TASK] section of your prompt to Codex, but enrich it with [CONTEXT] and [CONSTRAINTS] gathered from the codebase.

**CRITICAL:** You MUST delegate to Codex via tmux. Do NOT do the work yourself. Do NOT skip the tmux session. Do NOT bail because you can't find codex on PATH — the shell helper handles that.
