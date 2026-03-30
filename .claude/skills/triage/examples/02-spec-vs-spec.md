## Example 2: Spec ↔ Spec Conflict

### What

ADR-00038 defines that a client sending a `SessionAttach` message while already
attached to another session MUST be rejected with `ERR_ALREADY_ATTACHED`, but
the protocol spec's state table shows `Attached + SessionAttach → Attached` as a
valid implicit transition (detach-from-old, attach-to-new).

### Why

This conflict represents a fundamental design disagreement about session
switching. The ADR was written during Plan 2 to prevent accidental session
switches — the concern was that a buggy client could silently hop between
sessions, causing confusion. The state table was written during Plan 3 when the
UX team requested seamless session switching without requiring an explicit
detach step. Neither document references the other, so the conflict was never
surfaced.

### Who

ADR-00038 ("Explicit session detach requirement") vs. the protocol spec's client
state machine (`server-client-protocols.md`, Section 4.2, Table 4-1).

### When

Pre-existing since Plan 3. The state table was added in `v1.0-r5` of the
protocol spec. ADR-00038 was written during Plan 2 and has never been superseded
or amended.

### Where

**ADR-00038** (`docs/decisions/adr-00038-explicit-session-detach.md`, lines
18-29):

```
## Decision

A client that is currently attached to a session (state: Attached) and
sends a SessionAttach message for a different session MUST receive an
error response with code ERR_ALREADY_ATTACHED. The client must
explicitly send SessionDetach before attaching to a new session.

## Rationale

Implicit session switching creates a class of bugs where a client
silently moves between sessions without the user's knowledge. Requiring
explicit detach ensures the user confirms the session change.
```

**Protocol spec state table**
(`docs/modules/libitshell3-protocol/server-client-protocols.md`, lines 312-330):

```
### Table 4-1: Client State Machine

| Current State  | Message Received | Next State  | Action                        |
|----------------|------------------|-------------|-------------------------------|
| Connected      | SessionAttach    | Attached    | Attach to requested session   |
| Attached       | SessionDetach    | Connected   | Detach from current session   |
| Attached       | SessionAttach    | Attached    | Detach old, attach new        |
| Attached       | Disconnect       | Terminated  | Clean up resources            |
| Connected      | Disconnect       | Terminated  | Clean up resources            |
```

The third row (`Attached + SessionAttach → Attached`) directly contradicts the
ADR. The "Action" column says "Detach old, attach new" — an implicit transition
that the ADR explicitly prohibits.

**ADR precedence rules** (`docs/conventions/artifacts/documents/10-adr.md`, line
14): "An ADR is authoritative until explicitly superseded by a later ADR. Spec
documents must not contradict active ADRs without an accompanying superseding
ADR."

**Concrete impact:** If the implementation follows the state table, the code
violates an active ADR with no superseding record, making the design history
unreliable. If the implementation follows the ADR, the state table row
(`Attached + SessionAttach → Attached`) is dead code that will confuse every
future reader and reviewer. Either way, one document is wrong and must be
updated.

### How

The owner needs to decide which behavior is correct for the product. This may
involve: updating the ADR to supersede itself (if implicit switching is now
desired), removing the state table row (if explicit detach is correct), or
writing a new ADR that refines the policy (e.g., allow implicit switching only
with a specific flag in the SessionAttach message).

---
