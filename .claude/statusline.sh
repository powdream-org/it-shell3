#!/usr/bin/env bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
if [ -n "$SESSION_ID" ]; then
  mkdir -p "${TMPDIR}claude-token-usage"
  echo "$INPUT" | jq '{
    remaining_percentage: .context_window.remaining_percentage,
    used_percentage: .context_window.used_percentage,
    context_window_size: .context_window.context_window_size,
    total_input_tokens: .context_window.total_input_tokens,
    total_output_tokens: .context_window.total_output_tokens
  }' > "${TMPDIR}claude-token-usage/${SESSION_ID}.json"
fi
echo "$INPUT" | npx -y ccstatusline@latest
