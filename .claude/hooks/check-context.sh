#!/usr/bin/env bash
THRESHOLD=${1:-30}
INPUT=$(cat)

# Skip if running in a subagent context (agent_id present)
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')
if [ -n "$AGENT_ID" ]; then
  exit 0
fi

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
USAGE_FILE="${TMPDIR}claude-token-usage/${SESSION_ID}.json"

if [ -z "$SESSION_ID" ] || [ ! -f "$USAGE_FILE" ]; then
  exit 0
fi

REMAINING=$(jq -r '.remaining_percentage // 100' "$USAGE_FILE")
REMAINING_INT=${REMAINING%.*}

if [ "$REMAINING_INT" -lt "$THRESHOLD" ]; then
  echo "⚠️ Context window ${REMAINING}% remaining. Run /compact before proceeding. Type 'yes' to continue anyway."
  exit 2
fi
