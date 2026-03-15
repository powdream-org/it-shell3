# Round 2 Verification Issues

**Date**: 2026-03-15 **Round**: 2 **Verification target**: `draft/v1.0-r5` (all
4 spec docs)

---

## Dismissed Issues Summary

| ID    | Verdict   | Reason                                                                                                                                          |
| ----- | --------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| SEM-A | DEFERRED  | Phase 2 contested. Owner decision: deferred to v1.0-r6. Review note written at `review-notes/01-preedit-ownership-scope.md`.                    |
| SEM-C | DISMISSED | Phase 2 contested. Owner decision: "for each session" over empty collection is trivially no-op — overly strict interpretation, no fix required. |

---

## Confirmed Issues (carry to Round 3)

### SEM-B — Last-Pane Close: engine.reset() vs. deactivate()+deinit() sequence gap

- **Severity**: critical
- **Phase 1 source**: semantic-verifier
- **Phase 2 verdict**: both agents confirm
- **Locations**:
  - `04-runtime-policies.md` §7.3 — pane close uses `engine.reset()`
  - `02-integration-boundaries.md` §4.1 lifecycle table — session close uses
    `deactivate()` then `deinit()` (qualified as "non-last pane" for reset)
  - `03-lifecycle-and-connections.md` §3.2 — auto-destroy-from-last-pane calls
    `deinit()` with no preceding `deactivate()`
- **Problem**: When the last pane closes, the ordering of `reset()` →
  `deactivate()` → `deinit()` is unspecified. Doc02 §4.1 qualifies `reset()` as
  "non-last pane" but doc04 §7.3 says "pane close" without qualification. Doc03
  §3.2's auto-destroy path calls `deinit()` directly, skipping `deactivate()` —
  inconsistent with doc02 §4.1's "deactivate() then deinit()" contract for
  session close.
- **Fix required**: Align doc04 §7.3, doc02 §4.1, and doc03 §3.2 to specify the
  normative sequence for last-pane close: clarify whether `reset()` is called
  before the session-destroy path, and whether `deactivate()` must precede
  `deinit()` in the auto-destroy path.

---

### CRX-A — `active_keyboard_layout` vs. `keyboard_layout` identifier mismatch

- **Severity**: minor
- **Phase 1 source**: consistency-verifier
- **Phase 2 verdict**: both agents confirm
- **Locations**:
  - `03-lifecycle-and-connections.md` §4.6 Mermaid sequence diagram:
    `AttachSessionResponse` lists `active_keyboard_layout`
  - `01-internal-architecture.md` §3.2 class diagram and §3.3 Zig struct: field
    is `keyboard_layout` (no `active_` prefix)
- **Problem**: The sequence diagram uses `active_keyboard_layout` while the
  struct definition and all other references (4 documents) use
  `keyboard_layout`. Only this one location has the `active_` prefix —
  inconsistent with the normative struct field name.
- **Fix required**: Change `active_keyboard_layout` → `keyboard_layout` in doc03
  §4.6 sequence diagram annotation.

---

### CRX-B — Stray colon typo in doc02 §4.2 Mermaid flowchart label

- **Severity**: minor
- **Phase 1 source**: consistency-verifier
- **Phase 2 verdict**: both agents confirm
- **Location**: `02-integration-boundaries.md` §4.2 Mermaid flowchart LR diagram
- **Problem**: Phase 1 node label reads
  `"Phase 1(libitshell3-ime:)<br/>processKey"` — stray colon inside parentheses
  and missing space before parenthesis. Sibling labels follow
  `Phase N (module/)` pattern: `"Phase 0 (input/)"` and `"Phase 2 (server/)"`.
- **Fix required**: Change label to `"Phase 1 (libitshell3-ime)<br/>processKey"`
  — remove stray colon and add missing space, consistent with sibling labels.
