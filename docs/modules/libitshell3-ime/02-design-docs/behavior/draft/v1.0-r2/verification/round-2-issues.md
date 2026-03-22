# Verification Round 2 — Behavior v1.0-r2

- **Round**: 2
- **Date**: 2026-03-22
- **Phase 1 agents**: consistency-verifier (sonnet/Gemini), semantic-verifier
  (sonnet/Gemini)
- **Phase 2 agents**: issue-reviewer-fast (sonnet/Gemini), issue-reviewer-deep
  (opus/Gemini)

## Confirmed Issues

All issues are pre-existing from v1.0-r1. Owner decided to fix all in this
round.

### V2-01 [minor] — Wrong section reference (CONS-3)

- **Severity**: minor
- **Source**: `01-processkey-algorithm.md`, Section 2.1 Step 2 (line 77)
- **Description**: References "Section 3.1 of `02-scenario-matrix.md`" but the
  composing mode flush/undo semantics are in Section 3.2. Section 3.1 is Direct
  Mode.
- **Expected correction**: Change "Section 3.1" to "Section 3.2".
- **Consensus note**: Both Phase 2 reviewers confirmed.

### V2-02 [minor] — Wrong doc reference for ImeResult/KeyEvent (CONS-5)

- **Severity**: minor
- **Source**: `10-hangul-engine-internals.md`, introduction (lines 10-12)
- **Description**: Says "see `03-engine-interface.md`" for ImeResult and
  KeyEvent, but those types are defined in `02-types.md`.
- **Expected correction**: Split into two references: `02-types.md` for
  ImeResult/KeyEvent, `03-engine-interface.md` for ImeEngine vtable.
- **Consensus note**: Both Phase 2 reviewers confirmed.

### V2-03 [critical] — Missing release event guard (SEM-2)

- **Severity**: critical
- **Source**: `01-processkey-algorithm.md`, Sections 2 and 2.1
- **Description**: The processKey algorithm never checks `KeyEvent.action`. A
  release event for a printable key would follow the composition path, producing
  wrong output instead of the silent no-op required by the scenario matrix.
- **Expected correction**: Add early-exit guard before mode check: if action !=
  press/repeat → return empty ImeResult. Update flowchart and step-by-step
  algorithm.
- **Cascade**: `02-types.md` line 84 "typically ignores" → tighten to "ignores"
  (optional).
- **Consensus note**: Both Phase 2 reviewers confirmed. Deep reviewer noted
  pre-existing from v1.0-r1.

### V2-04 [critical] — Stale isPrintablePosition() warnings (SEM-3)

- **Severity**: critical
- **Source**: `01-processkey-algorithm.md`, Sections 2.1 (lines 65-77) and 3
  (lines 151-156)
- **Description**: Warnings claim `isPrintablePosition()` range is 0x04-0x38
  including five gap keycodes. The function already excludes 0x28-0x2C (range is
  0x04-0x27 + 0x2D-0x38). Warnings are factually incorrect.
- **Expected correction**: Replace warnings with updated guidance endorsing
  `isPrintablePosition()` as the correct printability gate.
- **Consensus note**: Both Phase 2 reviewers confirmed. Deep reviewer noted
  pre-existing from v1.0-r1.

### V2-05 [minor] — Space "Exception" framing inconsistency (SEM-4)

- **Severity**: minor
- **Source**: `01-processkey-algorithm.md`, Section 3 (lines 141-143)
- **Description**: Space listed as "Exception" to printable key branch, but
  Space (0x2C) is non-printable and never enters that branch.
- **Expected correction**: Remove the Exception clause. Space naturally falls
  into "Everything else → forward."
- **Cascade**: `02-scenario-matrix.md` Section 3.1 rules text (line 58-59) has
  matching "Exception" text that also needs removal.
- **Consensus note**: Both Phase 2 reviewers confirmed. Deep reviewer noted
  pre-existing from v1.0-r1.

## Dismissed Issues Summary

(No dismissed issues in Round 2.)
