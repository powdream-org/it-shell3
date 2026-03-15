# Preedit Ownership Scope: Per-Pane vs. Session-Level

**Date**: 2026-03-15
**Raised by**: verification team (Round 2, Phase 1 semantic-verifier)
**Severity**: HIGH
**Affected docs**: `01-internal-architecture.md` §3.8, `02-integration-boundaries.md` §4.1, `04-runtime-policies.md` §6.1 §6.2 §11
**Status**: deferred to draft/v1.0-r6

---

## Problem

Two normative claims in the current documents are in tension:

1. **doc04 §11** states: "Per-session IME engine makes simultaneous compositions
   physically impossible." The per-session engine is the architectural mechanism
   that enforces preedit exclusivity.

2. **doc04 §6.1** defines `PanePreeditState` (a per-pane struct with `owner: ?u32`,
   `preedit_text: []const u8`) and **§6.2** specifies an elaborate multi-client
   concurrent-attempt handling protocol (Rule 2: "commit first client's preedit,
   transfer ownership to the new client").

The Phase 2 reviewers disagreed on whether this is a genuine contradiction:
- **fast (sonnet)**: the "concurrent attempt" protocol in §6.2 contradicts §11's
  "physically impossible" claim — if the engine structurally prevents it, why is a
  detailed protocol specified for handling it?
- **deep (opus)**: the two structures serve different purposes — `PanePreeditState`
  handles multi-CLIENT contention on a single focused pane (two clients sending keys
  simultaneously), while the per-session engine prevents multi-PANE simultaneous
  composition. These are orthogonal concerns.

The deep reviewer's interpretation is plausible but the documents do not explicitly
state this distinction. An implementer reading §6.1, §6.2, and §11 together would
need to infer the multi-client vs. multi-pane distinction without normative guidance.

Additionally, `PanePreeditState.preedit_text` (doc04 §6.1) and `Session.current_preedit`
(doc01 §3.8) both hold preedit text — the relationship between them (which is
authoritative, how they are kept in sync) is not specified.

## Analysis

This issue requires the daemon team to deliberate:

- Is the "concurrent attempt" scenario in §6.2 about two clients contending on the
  **same pane**, or about two clients contending on **different panes**?
- If multi-client/single-pane: this is a valid use case the per-session engine does
  not prevent (two clients can both send keys to the focused pane). §11 is correct
  and §6.2 is complementary.
- If multi-pane: §6.2 handles a scenario the engine physically prevents, which would
  make §6.2 defensive dead code — and §11 would be overstated or §6.2 over-specified.

The relationship between `PanePreeditState.preedit_text` and `Session.current_preedit`
also needs explicit documentation: one should be authoritative (the engine's live
composition state) and the other a derived/cached copy, with clear sync semantics.

## Proposed Change

The daemon team should discuss and resolve the following questions in v1.0-r6:

**Option A — Clarify as multi-client/single-pane (complementary design)**
- Add a normative note to §6.1 and §11 explicitly stating: `PanePreeditState` tracks
  multi-CLIENT ownership on the active pane; the per-session engine prevents
  multi-PANE simultaneous composition. These are orthogonal invariants.
- Document the sync relationship between `PanePreeditState.preedit_text` and
  `Session.current_preedit`.

**Option B — Simplify the ownership model**
- If simultaneous compositions are truly physically impossible (single engine), the
  per-pane ownership struct may be over-specified. Evaluate whether §6.2's
  concurrent-attempt protocol is exercisable in practice, and simplify if not.

## Owner Decision

Deferred to the daemon team for deliberation in draft/v1.0-r6. The team should
research whether multi-client contention on a single pane is a real scenario
(e.g., in tmux control-mode where two clients share a session) and choose the
appropriate option above.

## Resolution

_(deferred)_
