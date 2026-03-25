# Review Note: Mouse Encoding API Not Available in ghostty lib_vt

- **Date**: 2026-03-25
- **Found during**: Plan 2 implementation, ghostty v1.3.1-patch pin

## Finding

The design spec (`03-integration-boundaries.md` §4.5) lists
`mouse_encode.encode()` as a ghostty helper function the daemon wraps. However,
ghostty v1.3.1 does NOT export mouse encoding via `lib_vt.zig`.

Mouse encoding logic is embedded in `Surface.zig:mouseReport()` (lines
3598-3860), tightly coupled to Surface state (viewport, termio queue). There is
no standalone `mouse_encode.zig` equivalent to `key_encode.zig`.

## Impact

The daemon (headless, no Surface) cannot use ghostty's mouse encoding directly.
The encoding logic (X10, UTF-8, SGR, URXVT formats) must be extracted into a
daemon-side pure function.

## Action Required

For the next revision cycle (r9 or implementation plan):

1. **Write a daemon-side `mouse_encoder.zig`** — pure function taking button,
   position, modifiers, and terminal mouse format/event flags. Produce the
   escape sequence directly. The logic in `Surface.zig` lines 3670-3860 is the
   reference.
2. **Update spec §4.5** — note that mouse encoding is daemon-authored, not a
   ghostty wrapper (unlike key encoding which IS a ghostty wrapper).
3. **Consider upstreaming** — propose a standalone `mouse_encode.zig` to ghostty
   (matching `key_encode.zig` pattern) so future versions export it via
   `lib_vt.zig`.
