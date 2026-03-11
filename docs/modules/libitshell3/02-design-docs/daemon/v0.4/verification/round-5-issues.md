# Daemon v0.4 Verification — Round 5 Issues

**Date**: 2026-03-11
**Team**: history-guardian (sonnet), cross-reference-verifier (sonnet), semantic-verifier (sonnet), terminology-verifier (sonnet)
**Verdict**: All Round 4 fixes confirmed clean. 1 new MINOR issue found — fix required.

---

## Round 4 Fix — Confirmed Clean

CRX-R4-1: correctly applied. All 4 doc headers now say `**Version**: v0.4`.

---

## New Issue (1, MINOR)

### SEM-R5-1 — MINOR: Doc 04 §7.3 and §11 false "ONLY" claim about engine.reset()

**File**: `v0.4/04-runtime-policies.md`, lines 338 and 517
**Sources**: semantic-verifier, cross-reference-verifier, history-guardian (unanimous)

**Contradiction**: §7.3 (line 338) states:
> "This is the ONLY scenario where `engine.reset()` (discard) is used instead of `engine.flush()` (commit). All other preedit-ending scenarios use flush/commit to preserve the user's work."

However, §7.5 and the §7.7 summary table both define a second `engine.reset()` scenario: `InputMethodSwitch` with `commit_current=false`. §11 Design Decisions Log (line 517) repeats the false claim: "Pane close uses reset(), all others use flush()."

The "ONLY" claim in §7.3 and the "all others" claim in §11 are factually incorrect within the same document.

**Fix**:
- Line 338: Replace "ONLY scenario" claim — acknowledge that both pane close and input method switch (`commit_current=false`) use `engine.reset()`.
- Line 517: Update the Design Decisions Log entry to reflect both reset() scenarios.

---

## History-Guardian Assessment

Zero false alarms. SEM-R5-1 is a contradiction between four pieces of current normative body text within the same document (§7.3, §7.5, §7.7, §11). Not a historical record comparison.
