# Handover: Daemon Design v0.4 to v0.5

**Date**: 2026-03-11
**Author**: team leader

---

## Summary of v0.4

v0.4 resolved 4 carry-over review notes from v0.3:

1. **RN-05 (CRITICAL)**: Message type naming alignment — 9 occurrences renamed in doc03: `SessionDetachRequest`→`DetachSessionRequest`, `ResizeRequest`→`WindowResize`, `ServerShutdown`→`Disconnect(reason:server_shutdown)`. 2 occurrences in v0.1 historical doc were cancelled (historical doc must not be modified).

2. **RN-03 (HIGH)**: `SessionEntry` introduced in `server/session_entry.zig` — `pane_slots`, `free_mask`, `dirty_mask` moved from `Session(core/)` to `SessionEntry(server/)`, resolving the `core/→server/` reverse dependency. `SessionManager` updated to `HashMap(u32, *SessionEntry)`. `focused_pane` stays in `Session`.

3. **RN-02 (LOW)**: `pty_master_fd`→`pty_fd` in doc03 §1.1 Step 6 pseudocode.

4. **RN-01 (LOW)**: CANCELLED — v0.1 resolution doc is a historical artifact; must not be modified.

Verification took 6 rounds (10 issues total). Notable findings:
- 7 issues were writing/missed-update errors caught in Rounds 1–2
- 3 issues were pre-existing problems in doc04 (originally "unchanged" in v0.4 but reviewed for the first time): Surface API reference (SEM-R3-1), false version header (CRX-R4-1), false "ONLY reset()" claim (SEM-R5-1)

## Insights

**Version header hygiene**: Every round found at least one doc with a stale version header. Consider making version header updates a mandatory checklist item in the writing phase (before verification begins) for future revisions.

**Doc04 pre-existing issues**: Doc04 was supposed to be "unchanged" in v0.4 but accumulated 3 issues in verification. This is because verification reads all docs, not just changed ones. This is the correct behavior — but it means "unchanged" docs may still generate fixes. Future revision cycles should note which docs are truly unchanged vs. which are being touched for the first time by a thorough verification pass.

**Historical documents**: The rule "v0.1 design resolution docs must not be modified" was established in v0.4. Future cycles must remember this. Resolution 3 (RN-01) was formally CANCELLED with rationale in the design resolutions doc.

## Owner Priorities for v0.5

No carry-over review notes at this time. The only open item is:

- **Review note 01** (LOW): Protocol doc v0.11 stale Surface references (`ghostty_surface_preedit()` in §4.2). Scope: protocol module, not daemon. Forwarded to next protocol revision cycle.

## Pre-Discussion Research Tasks

None required. v0.5 should be driven by new review notes from the owner review of v0.4.
