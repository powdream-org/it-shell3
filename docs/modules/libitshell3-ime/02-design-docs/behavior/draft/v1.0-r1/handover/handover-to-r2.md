# Handover: IME Behavior v1.0-r1 to v1.0-r2

- **Date**: 2026-03-22 (updated; originally 2026-03-14)
- **Author**: team lead

---

## Insights and New Perspectives

### The behavior doc set exists to decouple observable API from implementation mechanics

The v1.0-r1 revision cycle was the first time behavior documents were created as
a separate artifact layer. The key realization: the interface contract
(`ImeEngine` vtable, `ImeResult`, `KeyEvent`) describes _what the engine
exposes_ to callers; the behavior docs describe _how the engine should behave
internally_ — the algorithm, the state machine, the edge cases. These are two
distinct audiences. An implementor needs the behavior docs, not the interface
contract. A daemon integrator needs the interface contract, not the internals.

This separation is why CTR-02, 03, and 04 were filed: the interface contract had
accumulated implementation detail (HangulImeEngine concrete struct, scenario
matrix, flush policy, `hangul_ic_process()` algorithm) that belongs in behavior
docs, not in an API contract.

### `processKey()` has three non-printable paths, not two

The composing-mode decision tree is commonly described as two branches:
"printable → compose, non-printable → flush/forward." This is wrong for
Backspace. The correct model is:

1. Modifier keys (Ctrl/Alt/Cmd) → flush + forward
2. Flush-trigger special keys (Enter, Escape, Tab, Space, Arrow keys) → flush +
   forward
3. **Backspace** → IME undo handler (`hangul_ic_backspace()`); forward only if
   composition empty

This three-path model should be the mental model for anyone reading the
algorithm. The Round 3 fix (R3-sem-1) correctly stated the printable range but
then incorrectly grouped Backspace with flush-trigger keys — a cascade that
became R4-sem-1, deferred to v1.0-r2.

### Explanatory notes that enumerate items introduce cascade risk

When a fix adds a note that lists multiple items under a single behavioral claim
("all of these → path X"), each item must be individually verified against all
other documents. The note's blanket claim may be true for the majority but wrong
for one exception. This pattern is now documented in
`docs/work-styles/03-design-workflow.md` Section 3.6 cascade monitoring.

---

## Design Philosophy

**Interface contract = observable API only.** Implementation detail belongs in
behavior docs. The interface contract should be readable by a daemon integrator
who does not need to know how Korean jamo composition works internally. If a
section requires knowledge of libhangul internals to understand, it does not
belong in the interface contract.

**Behavior docs = implementor's spec.** Each behavior doc should be
self-contained enough that an implementor can write the corresponding code
without consulting the interface contract. Cross-references between the two
layers are allowed but the behavior doc should not depend on
implementation-detail sections of the interface contract (which CTR-02 removes).

---

## Owner Priorities

- **Backspace correctness is first-priority for v1.0-r2.** R4-sem-1 (deferred)
  is a doc inconsistency, not a runtime bug — the correct behavior is specified
  in `03-modifier-flush-policy.md`. But the fix in `01-processkey-algorithm.md`
  must land in r2 before implementors read both documents and encounter the
  contradiction.

- **CTRs targeting interface-contract are not blocking for r2.** The cross-team
  requests (CTR-02, 03, 04) target the interface-contract team's documents. The
  behavior docs are complete and correct regardless of whether those CTRs have
  been applied.

- **Incoming CTR from protocol team must be applied in r2.** The protocol team
  filed `cross-team-requests/01-protocol-jamo-decomposition.md` (from protocol
  v1.0-r12) requesting that Backspace's role in Jamo decomposition be explicitly
  documented in the behavior docs. This aligns with and extends the R4-sem-1 fix
  — both target Backspace handling. The CTR asks for additions to
  `01-processkey-algorithm.md` (Backspace as decomposition trigger) and
  `10-hangul-engine-internals.md` (jamo stack pop behavior on Backspace).

---

## New Conventions and Procedures

- **TODO.md must be updated after each verification round** — not just at cycle
  end. After sessions with multiple verification rounds (Phase 1 → Phase 2 → fix
  → repeat), a stale TODO fails as a resumption point on session loss. See
  `docs/conventions/artifacts/documents/09-todo.md` Anti-Patterns.

- **Explanatory note cascade prevention** — added to
  `docs/work-styles/03-design-workflow.md` Section 3.6 cascade monitoring
  item 3.

---

## Pre-Discussion Research Tasks

v1.0-r2 has two inputs: one deferred fix and one incoming CTR. Both target
Backspace handling and should be addressed together.

1. **R4-sem-1 fix**: In `01-processkey-algorithm.md` Section 2.1 Step 2 note,
   separate Backspace (0x2A) from the flush/forward group. Enter (0x28), Escape
   (0x29), Tab (0x2B), Space (0x2C) go to flush/forward. Backspace goes to the
   IME undo path. Cross-reference `03-modifier-flush-policy.md` Section 2.3. See
   `review-notes/01-backspace-flush-path-grouping.md` for full problem statement
   and proposed change.

2. **CTR-01 (protocol team)**: Apply
   `cross-team-requests/01-protocol-jamo-decomposition.md`. Two additions:
   - `01-processkey-algorithm.md`: Add section or callout documenting Backspace
     (HID `0x2A`) as the Jamo decomposition trigger during active composition
     (decompose last jamo rather than delete preceding character).
   - `10-hangul-engine-internals.md`: Document jamo stack pop behavior on
     Backspace — how the engine distinguishes "Backspace during composition"
     (jamo decomposition) from "Backspace with empty composition" (forward to
     PTY).
