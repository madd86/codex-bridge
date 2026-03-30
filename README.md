# codex-bridge

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin that delegates tasks to [OpenAI Codex CLI](https://github.com/openai/codex) via tmux sessions.

Claude acts as an expert prompter — constructing rich, context-aware prompts and sending them to Codex as a capable teammate. After Codex completes, Claude reviews the output and optionally runs code-review and code-simplifier agents on any generated code.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed
- [OpenAI Codex CLI](https://github.com/openai/codex) installed (`npm install -g @openai/codex`)
- [tmux](https://github.com/tmux/tmux) installed

## Installation

```bash
claude plugins add /path/to/codex-bridge
```

Or install directly from GitHub:

```bash
claude plugins add gh:yourusername/codex-bridge
```

## Usage

### Slash command

```
/codex create a python script that renders .scad files to .stl
```

### Natural language

Just ask Claude to use Codex:

```
Have Codex refactor the auth module to use JWT tokens
Ask Codex to write unit tests for the parser
Use Codex to brainstorm caching strategies for the API
```

## How It Works

1. **Prompt construction** — Claude gathers codebase context (files, git state, conventions) and builds a structured prompt with `[CONTEXT]`, `[TASK]`, and `[CONSTRAINTS]` sections.

2. **Session creation** — A fresh tmux session (`codex-session-XXXX`) launches Codex in `--yolo` mode. You're given the session name and an attach command to watch live.

3. **Supervised polling** — Claude polls every 5 seconds for the `>` prompt marker indicating Codex is idle. Timeout after 5 minutes with option to abort or continue.

4. **Post-completion review** — For code tasks, Claude fires `code-simplifier` and `code-reviewer` agents in parallel. For ideation tasks, Claude summarizes the response.

5. **Cleanup** — Session scrollback is saved to `.codex-logs/codex-session-XXXX.log`, then the tmux session is killed.

## Architecture

```
codex-bridge/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── commands/
│   └── codex.md                 # /codex slash command
├── scripts/
│   └── codex-bridge.sh          # Shell helper (tmux lifecycle)
├── skills/
│   └── codex/
│       └── SKILL.md             # Workflow & prompting strategy
└── tests/
    ├── test-start-teardown.sh   # Session lifecycle tests
    ├── test-send-poll.sh        # Send/poll integration test
    ├── test-abort.sh            # Abort integration test
    └── test-e2e.sh              # Full lifecycle test
```

### Shell helper commands

The `codex-bridge.sh` script handles all tmux mechanics:

| Command | Description |
|---|---|
| `start` | Create tmux session, launch Codex, handle startup prompts |
| `send <session> <prompt>` | Inject prompt text and submit |
| `poll <session>` | Check if Codex is idle (`ready`) or working (`working`) |
| `capture <session>` | Capture full scrollback |
| `abort <session>` | Send ESC to interrupt |
| `save-log <session>` | Save scrollback to `.codex-logs/` |
| `teardown <session>` | Save log and kill session |

## Running Tests

Tests run against a **live Codex session** and require both `tmux` and `codex` to be available:

```bash
bash tests/test-start-teardown.sh
bash tests/test-send-poll.sh
bash tests/test-abort.sh
bash tests/test-e2e.sh
```

## Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Delegation mode | Supervised loop | Claude always monitors and reports back |
| Completion detection | `>` prompt marker | Most reliable idle signal |
| Session lifecycle | Fresh per task | No cross-task context pollution |
| Code review | Auto via agents | code-simplifier + code-reviewer in parallel |
| Prompt injection | `tmux load-buffer` | Avoids quoting issues with `send-keys` |
| Cleanup | Kill + save log | Audit trail without dangling sessions |

## License

MIT
