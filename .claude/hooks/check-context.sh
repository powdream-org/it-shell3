#!/usr/bin/env bash
THRESHOLD=${1:-30}
INPUT=$(cat)

# Skip if running in a subagent context (agent_id present)
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')
if [ -n "$AGENT_ID" ]; then
  exit 0
fi

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
if [ -z "$SESSION_ID" ]; then
  exit 0
fi

# Use shared script to read usage data
SCRIPT_DIR="$(dirname "$0")/../skills/check-available-context-window/scripts"
USAGE=$(bash "$SCRIPT_DIR/get-context-usage.sh" "$SESSION_ID" 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$USAGE" ]; then
  exit 0
fi

REMAINING=$(echo "$USAGE" | jq -r '.remaining_percentage // 100')
REMAINING_INT=${REMAINING%.*}

if [ "$REMAINING_INT" -lt "$THRESHOLD" ]; then
  echo "⚠️ Context window ${REMAINING}% remaining. Run /compact before proceeding. Type 'yes' to continue anyway."
  exit 2
fi
