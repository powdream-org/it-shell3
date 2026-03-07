#!/usr/bin/env bash
# Build poc-ghostty-real against pre-built libghostty.a + libhangul

set -euo pipefail

GHOSTTY_BASE="$HOME/dev/git/powdream/cjk-compatible-terminal-for-ipad/ghostty/macos/GhosttyKit.xcframework/macos-arm64_x86_64"
GHOSTTY_LIB_DIR="$GHOSTTY_BASE"
GHOSTTY_HEADER_DIR="$GHOSTTY_BASE/Headers"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIBHANGUL_DIR="$SCRIPT_DIR/../ime-key-handling/libhangul"

echo "Building poc-ghostty-real..."
echo "  ghostty lib:    $GHOSTTY_LIB_DIR/libghostty.a"
echo "  ghostty header: $GHOSTTY_HEADER_DIR/ghostty.h"
echo "  libhangul:      $LIBHANGUL_DIR"

cc -o "$SCRIPT_DIR/poc-ghostty-real" \
    "$SCRIPT_DIR/poc-ghostty-real.m" \
    "$LIBHANGUL_DIR/hangul/hangulctype.c" \
    "$LIBHANGUL_DIR/hangul/hangulinputcontext.c" \
    "$LIBHANGUL_DIR/hangul/hangulkeyboard.c" \
    "$LIBHANGUL_DIR/hangul/hanja.c" \
    -I"$GHOSTTY_HEADER_DIR" \
    -I"$LIBHANGUL_DIR" \
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

echo "Build succeeded: $SCRIPT_DIR/poc-ghostty-real"
echo ""
echo "Run: $SCRIPT_DIR/poc-ghostty-real"
