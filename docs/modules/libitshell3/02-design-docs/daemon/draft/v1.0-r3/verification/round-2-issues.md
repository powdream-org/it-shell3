# Verification Round 2 Issues

**Date**: 2026-03-10
**Team**: history-guardian (opus), cross-reference-verifier (sonnet), semantic-verifier (sonnet), terminology-verifier (sonnet)
**Scope**: Post-fix verification of 9 Round 1 issues + full re-read
**Result**: All 9 Round 1 fixes confirmed. 3 new issues to fix, 3 pre-existing deferred, 1 dismissed.

## Round 1 Fix Status

All 9 issues (V1-01 through V1-09) confirmed as FIXED by all 4 verifiers.

## New Issues — Fix Now

### R2-03 [MINOR] Residual ghostty_surface_preedit() in daemon doc 04 §6.1

**Location**: daemon/draft/v1.0-r3/04-runtime-policies.md §6.1, line 286
**Confirmed by**: All 4 verifiers
**Description**: PanePreeditState description says "determined by `ghostty_surface_preedit()`". Should reference `overlayPreedit()` — the headless mechanism. Missed by V1-02 fix which only addressed §5.3.
**Fix**: Replace with `overlayPreedit()` reference.

### R2-06 [MINOR] Stale cross-ref in daemon doc 01 line 476

**Location**: daemon/draft/v1.0-r3/01-internal-architecture.md line 476
**Confirmed by**: All 4 verifiers
**Description**: "The IME contract v0.8 Section 5 requires press+release pairs for `ghostty_surface_key()`" — Section 5 is now a stub after V1-08 fix. Citation points to empty content.
**Fix**: Update to reference daemon doc 01's own §4.6 explanation, or remove the citation.

### R2-07 [MINOR] Stale cross-ref in daemon doc 02 line 362

**Location**: daemon/draft/v1.0-r3/02-integration-boundaries.md line 362
**Confirmed by**: All 4 verifiers
**Description**: "Source: IME contract v0.8 Section 5" — now points to a stub.
**Fix**: Remove "IME contract v0.8 Section 5" from the source citation.

## Pre-Existing Issues — Deferred as Review Notes

### R2-01 [MINOR] AGENTS.md line 18 "session/tab/pane state"

**Pre-existing**: The "tab" reference in line 18 predates v0.3.
**Disposition**: Review note for next AGENTS.md revision.

### R2-02 [CRITICAL] SessionDetachRequest vs DetachSessionRequest

**Pre-existing**: daemon docs have used "SessionDetachRequest" since v0.1. Protocol docs define "DetachSessionRequest (0x0106)".
**Disposition**: Review note for daemon v0.4.

### R2-05 [MINOR] IME v0.8 docs 02/03 Surface API references

**Pre-existing**: `02-types.md` line 118 and `03-engine-interface.md` line 289 reference Surface APIs. Out of scope for the v0.8 extraction (targeted different sections).
**Disposition**: Review note for IME v0.9.

## Dismissed

### R2-04 — Protocol doc 03 "65,536 panes" vs daemon MAX_PANES=16

**Dismissed by**: semantic-verifier (withdrew — deliberate design decision), terminology-verifier (out of scope), cross-reference-verifier (pre-existing)
**Reason**: Explicitly resolved in protocol v0.10 design-resolutions `01-top-severity-fixes.md` line 104. Tree depth limit (16 levels) and pane count limit (16 panes) are orthogonal constraints by design.
