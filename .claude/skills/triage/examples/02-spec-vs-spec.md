## Example 2: Spec ↔ Spec Conflict

### What

ADR-00038 defines that a client sending a `SessionAttach` message while already
attached to another session MUST be rejected with `ERR_ALREADY_ATTACHED`, but
the protocol spec's state table shows `Attached + SessionAttach → Attached` as a
valid implicit transition (detach-from-old, attach-to-new).

### Why

The implementer has to pick one. If they follow the ADR, the state table row is
dead — it describes a transition that will never happen, and every future reader
will wonder why the row exists. If they follow the state table, the ADR is
violated with no superseding record, making the decision log unreliable — future
reviewers will flag the implementation as a bug against ADR-00038 and file
issues that waste time.

### Who

ADR-00038 ("Explicit session detach requirement") vs. the protocol spec's client
state machine (`server-client-protocols.md`, Section 4.2, Table 4-1).

### When

Pre-existing since Plan 3. The state table was added in `v1.0-r5` of the
protocol spec. ADR-00038 was written during Plan 2 and has never been superseded
or amended.

### Where

**The conflict as a decision tree:**

```
Client in OPERATING state sends AttachSessionRequest for a different session:

  ADR-00038 path:    → reject with ERR_ALREADY_ATTACHED
                       (client must explicitly detach first)

  State table path:  → implicit detach old, attach new → stay ATTACHED
                       (seamless session switch)

  These are mutually exclusive outcomes for the same input.
```

**ADR-00038** key sentence
(`docs/decisions/adr-00038-explicit-session-detach.md`):

> A client that is currently attached to a session and sends a SessionAttach
> message for a different session MUST receive an error response with code
> ERR_ALREADY_ATTACHED. The client must explicitly send SessionDetach before
> attaching to a new session.

**State table** key row (`server-client-protocols.md`, Table 4-1):

| Current State | Message Received | Next State | Action                 |
| ------------- | ---------------- | ---------- | ---------------------- |
| Attached      | SessionAttach    | Attached   | Detach old, attach new |

**ADR precedence rule** (`docs/conventions/artifacts/documents/10-adr.md`):

> An ADR is authoritative until explicitly superseded by a later ADR. Spec
> documents must not contradict active ADRs without an accompanying superseding
> ADR.

### How

The owner needs to decide which behavior is correct for the product. This may
involve: updating the ADR to supersede itself (if implicit switching is now
desired), removing the state table row (if explicit detach is correct), or
writing a new ADR that refines the policy (e.g., allow implicit switching only
with a specific flag in the SessionAttach message).
