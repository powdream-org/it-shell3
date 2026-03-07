#!/usr/bin/env bash
# Build the macOS IME Suppression PoC
#
# Produces: poc-ime-suppression (single-file macOS app)
# Dependencies: Foundation, AppKit, Carbon (for keycode constants)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Building macOS IME Suppression PoC..."

cc -fobjc-arc \
    "$SCRIPT_DIR/PoC.m" \
    -framework Foundation \
    -framework AppKit \
    -framework Carbon \
    -o "$SCRIPT_DIR/poc-ime-suppression"

echo "Build succeeded: $SCRIPT_DIR/poc-ime-suppression"
echo ""
echo "Run with:  $SCRIPT_DIR/poc-ime-suppression"
echo ""
echo "Test plan:"
echo "  1. Type regular letters (a-z) in the window"
echo "  2. Type with Shift held (A-Z)"
echo "  3. Switch macOS input source to Korean, type same keys"
echo "  4. Press Cmd+Q, Cmd+C, Cmd+V to test system shortcuts"
echo "  5. Press Ctrl+C, Alt+key to test modifier combos"
echo "  6. Verify NSTextInputClient call counts remain 0"
