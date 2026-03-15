# 00013. Server-Owned IME with Per-Session Engine

- Date: 2026-03-16
- Status: Accepted

## Context

CJK input method composition state must be synchronized across multiple clients.
The composition engine could live on the client (each client runs its own IME)
or on the server (single authoritative engine).

## Decision

Two related decisions:

1. **Preedit direction S->C**: Server owns the native IME engine
   (libitshell3-ime). Clients send raw HID keycodes only. Preedit state flows
   server-to-client as cell data in I/P-frames.
2. **Per-session IME engine**: One IME engine instance per session (not
   per-pane). All panes in a session share the engine. Flush (commit) on
   intra-session pane focus change. At most one pane per session can have active
   preedit (preedit exclusivity invariant).

Two-axis input method model: separates input method (composition engine) from
keyboard layout (physical key mapping). String identifiers everywhere for
self-documentation. No numeric layout_id table needed.

See also ADR 00001 (Native IME over OS IME) for the higher-level decision to use
native Zig IME instead of OS IME frameworks.

## Consequences

- Single authoritative composition state — no multi-client sync conflicts at the
  IME level.
- Clients are thin: no IME state, no composition logic, just KeyEvent sender +
  cell renderer.
- Focus change between panes commits preedit (may surprise users
  mid-composition, but consistent with single-engine model).
- Per-session engine is simpler than per-pane (one HangulInputContext per
  session vs per pane).
