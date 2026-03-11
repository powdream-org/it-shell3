# Daemon v0.4 Verification — Round 1 Issues

**Date**: 2026-03-11
**Team**: history-guardian (opus), cross-reference-verifier (sonnet), semantic-verifier (sonnet), terminology-verifier (sonnet)
**Verdict**: 4 confirmed, 3 dismissed — fix required

---

## Confirmed Issues

### V1-1 — CRITICAL: Doc 03 version header not updated to v0.4

**File**: `v0.4/03-lifecycle-and-connections.md`, lines 3–8
**Sources**: SEM-4, CRV-1, T-2 (merged)

Version header still reads `**Version**: v0.3` with no `**v0.4 changes**` entry. The document was modified in v0.4 by:
- Resolution 1: 8 message type renames (ServerShutdown→Disconnect, SessionDetachRequest→DetachSessionRequest, ResizeRequest→WindowResize)
- Resolution 4: pty_master_fd→pty_fd (2 occurrences)
- §4.3 ClientState updated to `?*SessionEntry`

Doc 01 follows the correct pattern (`Draft v0.4` + `**v0.4 changes**` entry). Doc 03 must match.

**Fix**: Update `**Version**: v0.3` → `**Version**: v0.4` and add a `**v0.4 changes**` line summarizing the above.

---

### V1-2 — MINOR: Doc 02 pseudocode uses stale field names

**File**: `v0.4/02-integration-boundaries.md`, §4.1 (lines 261–268)
**Source**: SEM-3

Pseudocode uses `session.engine.flush()` and `session1.engine.deactivate()`. After v0.4 Resolution 2:
- The `Session` struct field is `ime_engine` (not `engine`)
- The server-side receiver is `entry.session` (a `*SessionEntry`), not bare `session`

Correct access path: `entry.session.ime_engine.flush()`. Doc 01 §4.3 already uses this correctly.

**Fix**: Replace stale references in doc 02 §4.1 pseudocode to match doc 01 §4.3 pattern.

---

### V1-3 — MINOR: `ClosePane` instead of `ClosePaneRequest` in doc 01

**File**: `v0.4/01-internal-architecture.md`, line 392
**Source**: T-1

Line 392: "same sequence as explicit `ClosePane`" — normative protocol name is `ClosePaneRequest` (0x0144).
Line 395 (same paragraph) already correctly uses `ClosePaneRequest`.

**Fix**: Replace `ClosePane` with `ClosePaneRequest` at line 392.

---

### V1-4 — MINOR: Doc 03 §1.1 Step 6 says "Allocate Session" instead of SessionEntry

**File**: `v0.4/03-lifecycle-and-connections.md`, §1.1 Step 6 (line 104)
**Source**: T-3

Pseudocode says "Allocate Session:" but after v0.4 Resolution 2 the server allocates `SessionEntry` (wrapping Session + pane_slots + free_mask + dirty_mask). §4.3 of the same document already uses `?*SessionEntry` for `ClientState.attached_session`.

Note: this is NOT a missed R2 application — Resolution 2's affected docs list did not include doc 03 §1.1. The inconsistency arose because §4.3 was correctly updated to SessionEntry while §1.1 was not.

**Fix**: Update "Allocate Session:" → "Allocate SessionEntry:" in §1.1 Step 6 pseudocode.

---

## Dismissed Issues

| ID | Source | Reason |
|----|--------|--------|
| SEM-1 | semantic-verifier | Out of scope — stale `ghostty_surface_preedit()` reference is in protocol doc v0.11, not daemon docs |
| SEM-2 | semantic-verifier | Out of scope — state machine shorthand names are in protocol doc v0.11, not daemon docs |
| SEM-5 | semantic-verifier | Documentation completeness observation (calling convention), not a structural inconsistency |

---

## Out-of-Scope Observations (recorded for future rounds)

These are real issues but outside daemon v0.4 scope:

- **Protocol v0.11 §4.2**: Still cites `ghostty_surface_preedit()` for preedit injection; daemon doc 01 correctly uses `overlayPreedit()` (headless). The stale reference lives in the protocol doc.
- **Protocol v0.11 §5.1/5.3**: State machine uses informal message name shorthand inconsistent with normative table in §4.2.
