---
name: check-available-context-window
description: Check remaining context window capacity. Use before spawning agents, starting large tasks, or whenever you need to decide whether to ask for /compact. Also use when any step file says to check context budget.
argument-hint: "<session-id>"
---

# Check Available Context Window

Reports the current session's remaining context window percentage.

## Usage

Run the shared script via Bash with the current session ID:

```bash
bash .claude/skills/check-available-context-window/scripts/get-context-usage.sh <session-id>
```

The session ID is available from the conversation context (it appears in system
messages as `sessionId`). The script reads the token usage JSON file maintained
by Claude Code at `$TMPDIR/claude-token-usage/<session-id>.json`.

If `<session-id>` is empty or the usage file does not exist, the script exits
with code 1 and prints an error to stderr.

## Output

JSON with these fields:

```json
{
  "remaining_percentage": 42,
  "used_percentage": 58,
  "context_window_size": 1000000,
  "total_input_tokens": 54748,
  "total_output_tokens": 575811
}
```

## Limitations

- Only works in the main agent process. Subagents do not have access to the
  session's token usage file.
- The usage file is updated by Claude Code after each turn, so the data is from
  the previous turn (not real-time).
