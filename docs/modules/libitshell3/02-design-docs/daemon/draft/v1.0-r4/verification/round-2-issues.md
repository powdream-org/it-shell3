# Daemon v0.4 Verification — Round 2 Issues

**Date**: 2026-03-11
**Team**: history-guardian (opus), cross-reference-verifier (sonnet), semantic-verifier (sonnet), terminology-verifier (sonnet)
**Verdict**: All Round 1 fixes confirmed clean. 3 new MINOR issues found — fix required.

---

## Round 1 Fixes — All Confirmed Clean

V1-1, V1-2, V1-3, V1-4: all correctly applied.

---

## New Issues (3, all MINOR)

### R2-1 — MINOR: Doc 02 version header not updated to v0.4

**File**: `draft/v1.0-r4/02-integration-boundaries.md`, line 3
**Sources**: cross-reference-verifier, terminology-verifier

Header reads `**Version**: v0.3` with no `**v0.4 changes**` entry. Doc 02 was modified by the V1-2 fix (§4.1 pseudocode) and by R2-3 below (§4.3 pseudocode). Same pattern as Round 1's V1-1 (which correctly fixed doc 03's header).

**Fix**: Update `**Version**: v0.3` → `**Version**: v0.4` and add a `**v0.4 changes**` line summarizing the pseudocode field name corrections applied in this round.

---

### R2-2 — MINOR: Doc 03 §2.1 stale field name

**File**: `draft/v1.0-r4/03-lifecycle-and-connections.md`, line 234
**Sources**: all four verifiers

Current: `session.engine.deactivate()`
Expected: `entry.session.ime_engine.deactivate()`

After Resolution 2, the field is `ime_engine` (not `engine`), and server-side code accesses it via `entry.session` (a `*SessionEntry`), not a bare `session` variable. Missed occurrence in the graceful shutdown sequence (same class as V1-2).

**Fix**: Replace `session.engine.deactivate()` → `entry.session.ime_engine.deactivate()` at line 234.

---

### R2-3 — MINOR: Doc 02 §4.3 stale access paths (3 occurrences)

**File**: `draft/v1.0-r4/02-integration-boundaries.md`, lines 333, 335, 336
**Sources**: all four verifiers

| Line | Current | Expected |
|------|---------|----------|
| 333 | `session_a.engine.deactivate()` | `entry_a.session.ime_engine.deactivate()` |
| 335 | `session_a.current_preedit = null` | `entry_a.session.current_preedit = null` |
| 336 | `session_b.engine.activate()` | `entry_b.session.ime_engine.activate()` |

V1-2 fixed the §4.1 pseudocode block but missed these three occurrences in the §4.3 prose. All three use `session_a`/`session_b` bare receivers — after v0.4 Resolution 2, server-side code holds `*SessionEntry` references and accesses `Session` fields via `entry.session.*`.

**Fix**: Update all three lines to use `entry_a.session.*` / `entry_b.session.*` access paths.

---

## Dismissed

| Item | Reason |
|------|--------|
| `last_preedit_row: ?u16` in doc 01 Session struct but absent from design-resolutions-v04.md §2.1 | Pre-existing difference, not introduced by v0.4 fixes. Recorded for future rounds. |

---

## History-Guardian Assessment

Zero false alarms. All three issues are current normative body text inconsistencies, not historical record comparisons.
