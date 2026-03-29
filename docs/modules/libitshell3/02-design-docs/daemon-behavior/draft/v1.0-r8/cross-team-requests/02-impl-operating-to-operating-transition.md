# Remove OPERATING→OPERATING State Transition Row

- **Date**: 2026-03-29
- **Source team**: impl (Plan 7 — Session & Pane Operations)
- **Source version**: daemon-behavior draft/v1.0-r8
- **Source resolution**: ADR 00020 (Session Attachment Model)
- **Target docs**: daemon-behavior draft/v1.0-r8/03-policies-and-procedures.md
- **Status**: open

---

## Context

ADR 00020 establishes the session attachment model: "Each client connection is
attached to at most one session at a time. To switch sessions, the client must
first detach (`DetachSessionRequest`) then attach to the new session. Sending
`AttachSessionRequest` while already attached returns
`ERR_SESSION_ALREADY_ATTACHED`."

The client state transitions table in `03-policies-and-procedures.md` (line 804)
contains a row that contradicts this ADR:

```
| OPERATING | AttachSessionRequest (different session) | OPERATING | Detach current, attach new, reinitialize ring cursors |
```

This row implies implicit detach-then-attach behavior, which ADR 00020
explicitly rejected in favor of explicit detach/attach round-trips.

ADRs take precedence over spec documents per
`docs/conventions/spec-document-sources.md`.

## Required Changes

1. **Remove or replace the contradicting row** in
   `03-policies-and-procedures.md` client state transitions table (line 804):

   **Current:**

   ```
   | OPERATING | AttachSessionRequest (different session) | OPERATING | Detach current, attach new, reinitialize ring cursors |
   ```

   **Should be:**

   ```
   | OPERATING | AttachSessionRequest | OPERATING | ERR_SESSION_ALREADY_ATTACHED — client must DetachSessionRequest first (ADR 00020) |
   ```

   Alternatively, the row can be removed entirely since the error response does
   not change state.

2. **Verify consistency** with daemon-architecture
   `03-integration-boundaries.md` Section 6.1 state diagram, which shows
   `OPERATING --> OPERATING : AttachSessionRequest (different session)`. This
   transition arrow should also be removed or changed to show the error path.

## Summary Table

| Target Doc                 | Section/Message           | Change Type | Source Resolution |
| -------------------------- | ------------------------- | ----------- | ----------------- |
| 03-policies-and-procedures | Client state transitions  | Remove row  | ADR 00020         |
| 03-integration-boundaries  | Section 6.1 state diagram | Remove edge | ADR 00020         |
