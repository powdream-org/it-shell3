# Backspace Incorrectly Grouped with Flush/Forward-Path Keys

**Date**: 2026-03-14
**Raised by**: verification team (Round 4, R4-sem-1)
**Severity**: CRITICAL
**Affected docs**: `behavior/draft/v1.0-r1/01-processkey-algorithm.md` Section 2.1 Step 2
**Status**: deferred to draft/v1.0-r2

---

## Problem

The note added in Round 3 (to explain why `isPrintablePosition()` must not be used as the
printability gate) lists HID 0x2A (Backspace) alongside 0x28 (Enter), 0x29 (Escape), 0x2B
(Tab), and 0x2C (Space), then states:

> "All of these are non-printable for composition purposes and **must be routed to the
> flush/forward path**, not the composition path."

This is incorrect for Backspace. The policy table in `03-modifier-flush-policy.md` Section 2
specifies Backspace as **IME handles** — meaning the composition engine processes it via
language-specific undo (e.g., `hangul_ic_backspace()`) rather than flushing. The scenario
matrix in `02-scenario-matrix.md` Section 3.2 confirms: Backspace during composition produces
a modified preedit (undo), not a flush + forward.

The note's blanket grouping of Backspace with the four flush/forward-path keys is a cascade
introduced by the Round 3 fix for R3-sem-1 (isPrintablePosition() range correction).

## Analysis

The composing-mode decision tree has three non-printable paths, not two:

1. **Modifier keys** (Ctrl/Alt/Cmd) → flush + forward
2. **Flush-trigger special keys** (Enter, Escape, Tab, Space, Arrow keys) → flush + forward
3. **Backspace** → IME undo handler (hangul_ic_backspace()); forward only if composition empty

The note conflates paths 2 and 3 by grouping all five HID codes under a single "flush/forward"
label. An implementor reading only `01-processkey-algorithm.md` would route Backspace to the
flush path, discarding the in-progress syllable rather than undoing the last jamo — a
user-visible composition error (e.g., typing "가" then Backspace should revert to "ㄱ", not
commit "가" and forward Backspace to the terminal).

The Backspace path is already fully specified and correct in `03-modifier-flush-policy.md`
Section 2 and Section 2.3 — the problem is solely the incorrect grouping in the Step 2 note
of `01-processkey-algorithm.md`.

## Proposed Change

In `01-processkey-algorithm.md` Section 2.1 Step 2, revise the note so that:

1. Enter (0x28), Escape (0x29), Tab (0x2B), and Space (0x2C) are identified as flush/forward-path
   keys — matching the policy table in `03-modifier-flush-policy.md`.
2. Backspace (0x2A) is listed separately and explicitly routed to the IME undo handler, not
   the flush/forward path. Cross-reference `03-modifier-flush-policy.md` Section 2.3.

The flowchart in Section 2 ("print_check — No → flush composition + forward key") does not
need to change — Backspace already bypasses that branch, handled upstream by the modifier/special
key logic. Only the note's prose needs correction.

## Owner Decision

Deferred to v1.0-r2. The current v1.0-r1 spec is shipped as-is; the fix is a first-priority
item for the next revision cycle. The correct behavior is documented in `03-modifier-flush-policy.md`
— implementors should treat that document as authoritative for Backspace handling.

## Resolution

_(To be filled when resolved in draft/v1.0-r2.)_
