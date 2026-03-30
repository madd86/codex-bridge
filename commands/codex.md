---
description: Delegate a task to OpenAI Codex CLI via tmux
argument-hint: Task description for Codex
allowed-tools: ["Bash", "Read", "Grep", "Glob", "Agent", "Skill"]
---

# /codex — Delegate to Codex

**FIRST:** Load the `codex-bridge:codex` skill using the Skill tool to get the full workflow.

Then follow the skill workflow exactly:
1. Pre-flight check
2. Construct expert prompt with full context
3. Start session and notify user
4. Send prompt
5. Supervised poll loop
6. Capture and review output
7. Cleanup

The user's task description is provided as the argument to this command. Use it as the basis for the [TASK] section of your prompt to Codex, but enrich it with [CONTEXT] and [CONSTRAINTS] gathered from the codebase.
