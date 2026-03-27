#!/usr/bin/env bash
# Reads token usage for a Claude Code session and outputs JSON.
# Usage: get-context-usage.sh <session_id>
# Output: JSON with remaining_percentage, used_percentage, context_window_size
# Exit 0 on success, exit 1 if usage file not found.

SESSION_ID="$1"
if [ -z "$SESSION_ID" ]; then
  echo '{"error": "no session_id provided"}' >&2
  exit 1
fi

USAGE_FILE="${TMPDIR}claude-token-usage/${SESSION_ID}.json"
if [ ! -f "$USAGE_FILE" ]; then
  echo '{"error": "usage file not found"}' >&2
  exit 1
fi

cat "$USAGE_FILE"
