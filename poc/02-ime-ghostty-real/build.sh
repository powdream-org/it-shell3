#!/usr/bin/env bash
# Build minimal_test against pre-built libghostty.a

set -euo pipefail

GHOSTTY_BASE="$HOME/dev/git/powdream/cjk-compatible-terminal-for-ipad/ghostty/macos/GhosttyKit.xcframework/macos-arm64_x86_64"
GHOSTTY_LIB_DIR="$GHOSTTY_BASE"
GHOSTTY_HEADER_DIR="$GHOSTTY_BASE/Headers"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Building minimal_test..."
echo "  Library: $GHOSTTY_LIB_DIR/libghostty.a"
echo "  Header:  $GHOSTTY_HEADER_DIR/ghostty.h"

cc -o "$SCRIPT_DIR/minimal_test" "$SCRIPT_DIR/minimal_test.m" \
    -I"$GHOSTTY_HEADER_DIR" \
    -L"$GHOSTTY_LIB_DIR" \
    -lghostty \
    -framework Foundation \
    -framework AppKit \
    -framework CoreText \
    -framework CoreGraphics \
    -framework Metal \
    -framework QuartzCore \
    -framework CoreFoundation \
    -framework Security \
    -framework IOKit \
    -framework GameController \
    -framework UniformTypeIdentifiers \
    -framework IOSurface \
    -framework Carbon \
    -lz \
    -lc++ \
    -fobjc-arc

echo "Build succeeded: $SCRIPT_DIR/minimal_test"
