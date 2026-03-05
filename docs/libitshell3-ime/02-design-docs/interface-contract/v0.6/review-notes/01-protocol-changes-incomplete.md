# Protocol Changes for v0.7 Missing Three Items

**Date**: 2026-03-05
**Raised by**: verification team (verifier-protocol)
**Severity**: MEDIUM
**Affected docs**: `docs/libitshell3-ime/02-design-docs/interface-contract/v0.6/protocol-changes-for-v07.md`
**Status**: open

---

## Problem

`protocol-changes-for-v07.md` captures Changes 1-7 covering Resolutions 7, 9-13. However, three additional per-pane references in protocol doc 05 v0.6 are NOT listed in the change notes:

1. **Section 4.1 (InputMethodSwitch), "per-pane lock"**: The `commit_current=false` implementation note says "The server MUST hold the per-pane lock across both calls to ensure atomicity." With the per-session engine, this should be "per-session lock." Change 7 covers Section 4.3 but does not mention the lock reference in Section 4.1.

2. **Section 9.2 (Restore Behavior)**: "Per-pane input method identifiers are restored. When a client reconnects, it receives the pane's saved input method via LayoutChanged leaf nodes." With per-session engine, input method is restored at session level (one engine per session), not per-pane. This section is not mentioned in any of the seven changes.

3. **Section 15 Open Question #5**: "Multiple simultaneous compositions: Should the protocol support preedit on multiple panes simultaneously (one per pane, same client)? Current design: Yes -- each pane has independent preedit state." This directly contradicts Resolution 13 (preedit exclusivity: at most one pane per session). This open question should be resolved as part of v0.7 updates.

## Analysis

Items 1 and 2 are straightforward text substitutions (per-pane -> per-session). The risk of omission is that v0.7 writers could miss these references and leave stale per-pane language in the protocol doc.

Item 3 is more significant: Open Question #5's "Current design: Yes" answer is invalidated by the preedit exclusivity rule. Leaving it unresolved in v0.7 would create a normative contradiction -- the preedit exclusivity section (Change 6) would coexist with an open question that assumes per-pane independence.

## Proposed Change

Add three items to `protocol-changes-for-v07.md`:

**Change 8: Section 4.1 -- Update lock scope (Resolution 11)**

Replace "per-pane lock" with "per-session lock" in the `commit_current=false` implementation note.

**Change 9: Section 9.2 -- Update restore behavior to per-session (Resolution 8)**

Replace "Per-pane input method identifiers are restored" with "The session's input method identifier is restored." Update the subsequent sentence to reference session-level initialization.

**Change 10: Section 15 -- Resolve Open Question #5 (Resolution 13)**

Resolve Open Question #5: with per-session engine and preedit exclusivity (Resolution 13), simultaneous compositions on multiple panes within the same session are not possible. The question should either be removed or rewritten to state: "Simultaneous compositions across different sessions are supported. Within a single session, at most one pane can have active preedit at any time (enforced by the single-engine architecture)."

## Owner Decision

Left to designers for resolution.

## Resolution

