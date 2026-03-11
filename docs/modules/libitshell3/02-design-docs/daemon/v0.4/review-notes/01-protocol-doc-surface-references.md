# Review Note: Protocol Doc v0.11 Stale Surface References

**Source**: Rounds 1–6 verification (SEM-1, out-of-scope observation)
**Severity**: LOW
**Target**: `docs/modules/libitshell3-protocol/02-design-docs/server-client-protocols/v0.11/`

## Description

Protocol doc v0.11 contains stale references to `ghostty_surface_preedit()` for preedit injection:
- §4.2 line ~361: "the server calls `ghostty_surface_preedit()`"
- §4.2 line ~383: similar reference
- §4.2 line ~396: similar reference

The daemon architecture (doc 01 §4.6) uses the headless API: `overlayPreedit()` at export time. There is no Surface in the daemon. These stale references in the protocol doc are inconsistent with the canonical daemon behavior established in daemon v0.3.

## Scope

Out of scope for daemon v0.4 — the protocol doc is a separate module. This note is forwarded to the next protocol revision cycle.

## Recommended Fix

Update protocol doc v0.11 §4.2 to describe the headless `overlayPreedit()` mechanism, or remove the implementation-detail references entirely (the protocol doc should describe wire semantics, not daemon internals).
