# Review Notes 01: Protocol v0.6

> **Status**: Open — apply in next revision
> **Date**: 2026-03-05
> **Raised by**: cross-doc verification (IME v0.5 protocol-changes-for-v06.md audit)
> **Target version**: v0.7

---

## Issue 01: Residual `empty` State References in Doc 05

### Summary

Two prose notes in doc 05 (`05-cjk-preedit-protocol.md`) still use `empty` as a
composition state label instead of `null`. The transition table and state diagram
themselves are correct — only the explanatory notes below them are inconsistent.

### Locations

1. **Line 349** (note below Section 3.2 state diagram): Says `empty + vowel` — should
   be `null + vowel`.
2. **Line 381** (note below Section 3.3 transition table): Says `empty + vowel` — should
   be `null + vowel`.

### Origin

These were missed when applying Change 2 from
`docs/modules/libitshell3-ime/02-design-docs/interface-contract/draft/v1.0-r5/protocol-changes-for-v06.md`,
which specified removing all `"empty"` state labels. The table rows were updated but the
prose notes were overlooked.

### Fix

Replace `empty + vowel` with `null + vowel` at both locations.

### Severity

Low — cosmetic inconsistency in explanatory notes. Tables and diagrams are correct.

---

_No other open issues at this time._
