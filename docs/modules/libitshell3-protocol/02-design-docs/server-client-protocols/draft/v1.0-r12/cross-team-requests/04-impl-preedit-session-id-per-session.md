# Correct preedit_session_id Scope from "per pane" to "per session"

- **Date**: 2026-03-27
- **Source team**: impl (Plan 5.5 Spec Alignment Audit)
- **Source version**: libitshell3 implementation Plans 1-5
- **Source resolution**: Preedit exclusivity invariant (doc 05 §1.1),
  daemon-behavior v1.0-r8 `02-event-handling.md` §8.1
- **Target docs**: `05-cjk-preedit-protocol.md` §2.1
- **Status**: open

---

## Context

The protocol spec describes `preedit_session_id` as "a monotonically increasing
counter per pane." This is stale text from before `PreeditState` was
consolidated at the Session level.

The preedit exclusivity invariant (doc 05 §1.1) guarantees that at most one pane
in a session can have active preedit at any time. Combined with the fact that
focus change always commits preedit before switching panes, a single counter per
Session is sufficient to disambiguate all composition sessions across all panes
within that session.

The daemon implementation stores `PreeditState` (containing `session_id: u32`)
on the `Session` struct, not on `Pane`. The daemon-behavior spec (§8.1) confirms
this with its ordering constraints:
`preedit.session_id increments between End
and Start` — referencing a single
session-level counter.

## Required Changes

1. **`05-cjk-preedit-protocol.md` §2.1 — Fix preedit_session_id scope.**
   - **Current**: "The `preedit_session_id` is a monotonically increasing
     counter per pane. It disambiguates overlapping composition sessions (e.g.,
     one ends and another starts quickly)."
   - **After**: "The `preedit_session_id` is a monotonically increasing counter
     per session. It disambiguates sequential composition sessions across all
     panes within the session. The preedit exclusivity invariant (§1.1)
     guarantees at most one active composition per session, so a single
     session-level counter suffices."
   - **Rationale**: The "per pane" language is a remnant from an earlier design
     where `PreeditState` lived on `Pane`. The preedit exclusivity invariant
     makes per-pane counters redundant.

## Summary Table

| Target Doc                   | Section/Message              | Change Type | Source Resolution          |
| ---------------------------- | ---------------------------- | ----------- | -------------------------- |
| `05-cjk-preedit-protocol.md` | §2.1 preedit_session_id desc | Fix scope   | Preedit exclusivity (§1.1) |
