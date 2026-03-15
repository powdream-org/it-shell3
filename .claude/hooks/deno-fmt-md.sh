#!/usr/bin/env bash
# PostToolUse hook: run `deno fmt` on any .md file that was just edited/written.
INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Only act on markdown files
case "$FILE_PATH" in
  *.md) ;;
  *) exit 0 ;;
esac

# Resolve relative paths from the repo root (Claude passes absolute paths, but guard anyway)
if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

deno fmt "$FILE_PATH" 2>/dev/null
exit 0
