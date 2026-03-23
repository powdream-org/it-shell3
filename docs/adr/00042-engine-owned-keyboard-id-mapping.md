# 00042. Engine-Owned Keyboard ID Mapping

- Date: 2026-03-23
- Status: Accepted

## Context

The `input_method` string (e.g., `"korean_2set"`) flows unchanged from client to
server to the IME engine constructor. Inside the engine, this string must be
mapped to a libhangul keyboard ID (e.g., `"2"`) for `hangul_ic_new()` and
`hangul_ic_select_keyboard()`.

The question is where this mapping should live:

1. **In the server (daemon)** — the server decomposes `input_method` into a
   libhangul keyboard ID before passing it to the engine.
2. **In the protocol spec** — a shared mapping table that both server and engine
   reference.
3. **In the engine** — the engine owns the mapping as an internal implementation
   detail.

The protocol spec (v1.0-r4, Doc 05 Section 4.3) originally contained a shared
mapping table. This table had a bug: `"korean_3set_390"` was mapped to `"3f"`
(should be `"39"`). The bug went undetected because the table existed in a
document far from the code that consumed it, with no unit test coverage.

## Decision

The IME engine is the sole owner of the `input_method` string to libhangul
keyboard ID mapping. The mapping is a private static table inside
`HangulImeEngine`, not exposed to or shared with any other component.

- The `input_method` string flows unchanged through the entire system — client,
  server, and engine constructor all see the same string.
- Only `HangulImeEngine.init()` and `setActiveInputMethodImpl()` decompose the
  string into a libhangul keyboard ID via `libhangulKeyboardId()`.
- No code outside the engine examines or transforms the `input_method` string
  for engine routing purposes.
- The canonical registry of valid `input_method` strings lives alongside the
  mapping table in the engine implementation, unit-testable in isolation.

## Consequences

- The `"korean_3set_390" → "3f"` bug class is eliminated. The mapping is
  co-located with its only consumer and covered by unit tests.
- Adding a new keyboard layout (e.g., `"korean_3set_old"`) requires only an
  engine-side change — one new entry in the static table. No protocol or server
  changes needed.
- The server treats `input_method` as an opaque string. It does not validate
  against a registry — validation happens inside the engine constructor, which
  returns `error.UnsupportedInputMethod` for unrecognized strings.
- If a future non-libhangul engine is added (e.g., Japanese), it owns its own
  mapping table independently. There is no shared cross-engine registry.
- The interface contract cross-references the engine's registry table without
  duplicating it (see ADR-00025 for the `input_method` identifier design).
