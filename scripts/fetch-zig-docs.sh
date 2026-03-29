#!/usr/bin/env bash
# Fetch the Zig language reference HTML for the version specified in mise.toml.
# Saves to docs/references/<version>/zig-language-reference.html
#
# Usage:
#   ./scripts/fetch-zig-docs.sh           # uses version from mise.toml
#   ./scripts/fetch-zig-docs.sh 0.14.1    # explicit version override

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Determine Zig version
if [ $# -ge 1 ]; then
  ZIG_VERSION="$1"
else
  ZIG_VERSION=$(mise current zig)
  if [ -z "$ZIG_VERSION" ]; then
    echo "ERROR: Could not extract zig version from mise.toml" >&2
    exit 1
  fi
fi

echo "Zig version: $ZIG_VERSION"

# Target directory
TARGET_DIR="$PROJECT_ROOT/docs/references/$ZIG_VERSION"
TARGET_FILE="$TARGET_DIR/zig-language-reference.html"

# Check if already up-to-date
if [ -f "$TARGET_FILE" ]; then
  echo "Already exists: $TARGET_FILE"
  echo "To force re-fetch, delete the file first."
  exit 0
fi

mkdir -p "$TARGET_DIR"

# Fetch — try versioned URL first, fall back to master
URL="https://ziglang.org/documentation/$ZIG_VERSION/"
echo "Fetching from $URL ..."

HTTP_CODE=$(curl -sL -o "$TARGET_FILE" -w "%{http_code}" "$URL")

if [ "$HTTP_CODE" = "404" ]; then
  echo "Version $ZIG_VERSION not found, trying master..."
  URL="https://ziglang.org/documentation/master/"
  HTTP_CODE=$(curl -sL -o "$TARGET_FILE" -w "%{http_code}" "$URL")
fi

if [ "$HTTP_CODE" != "200" ]; then
  rm -f "$TARGET_FILE"
  echo "ERROR: Failed to fetch Zig docs (HTTP $HTTP_CODE)" >&2
  exit 1
fi

FILE_SIZE=$(wc -c < "$TARGET_FILE" | tr -d ' ')
echo "Saved: $TARGET_FILE ($FILE_SIZE bytes)"
