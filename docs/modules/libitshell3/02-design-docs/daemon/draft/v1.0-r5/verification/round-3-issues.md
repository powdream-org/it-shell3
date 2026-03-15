# Round 3 Verification Issues

**Date**: 2026-03-15 **Round**: 3 **Verification target**: `draft/v1.0-r5` (all
4 spec docs)

**Agents**: `consistency-verifier` (Phase 1), `semantic-verifier` (Phase 1),
`issue-reviewer-fast` (Phase 2), `issue-reviewer-deep` (Phase 2)

---

## Dismissed Issues Summary

| ID     | Verdict   | Reason                                                                                                                                                                   |
| ------ | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| CRX-02 | DISMISSED | Phase 2: both agents split; owner decision: false alarm — `doc02 §4.4` is "Intra-Session Pane Focus Change," the correct cross-ref target. Category 4 — misread context. |
| SEM-04 | DISMISSED | Both agents: substantially the same as deferred Round 2 SEM-A (preedit ownership scope). Category 2 — verification record / open work item.                              |

---

## Confirmed Issues (carry to Round 4)

### CRX-01 — doc04 §3.5 wrong intra-doc section reference

- **Severity**: minor
- **Phase 1 source**: consistency-verifier
- **Phase 2 verdict**: both agents confirm
- **Location**: `04-runtime-policies.md` §3.5 stale-recovery table
- **Problem**: The table entry for "Stale recovery" references "Section 4.1" for
  socket write priority, but the socket write priority section is §4.5, not
  §4.1.
- **Fix required**: Change "Section 4.1" → "Section 4.5" in the stale-recovery
  table row.

---

### CRX-03/SEM-01 — doc03 §4.1 state diagram contradicts §3.3 prose and §4.2 table on unexpected disconnect routing

- **Severity**: critical
- **Phase 1 source**: consistency-verifier, semantic-verifier
- **Phase 2 verdict**: both agents confirm
- **Locations**:
  - `03-lifecycle-and-connections.md` §4.1 state diagram — labels transition
    `"peer closed (unexpected disconnect)"` as going to DISCONNECTING
  - `03-lifecycle-and-connections.md` §3.3 prose — states unexpected disconnects
    go directly to `[closed]`, bypassing DISCONNECTING
  - `03-lifecycle-and-connections.md` §4.2 transition table — "Client
    disconnect" from OPERATING goes to `[closed]`
- **Problem**: The state diagram presents
  `"peer closed (unexpected disconnect)"` as routing through DISCONNECTING. The
  prose and table both say unexpected disconnects bypass DISCONNECTING and go
  directly to `[closed]`. The diagram is a normative state machine spec (not
  illustrative), so this is a genuine normative contradiction within the same
  document.
- **Fix required**: Correct the state diagram to show unexpected disconnects
  (peer closed, socket error) as a direct `OPERATING → [closed]` transition,
  distinct from the graceful DISCONNECTING path.

---

### TERM-01 — doc02 §4.1 inter-session pseudocode uses undefined `pane_a`

- **Severity**: minor
- **Phase 1 source**: consistency-verifier
- **Phase 2 verdict**: both agents confirm
- **Location**: `02-integration-boundaries.md` §4.1 inter-session tab switch
  pseudocode
- **Problem**: The inter-session snippet uses `consume(pane_a.pty, result)` but
  `pane_a` is not defined in the inter-session context — it is defined only in
  the preceding intra-session snippet. The inter-session snippet should
  reference the focused pane of the departing session (e.g.,
  `entry1.session.focused_pane`).
- **Fix required**: Replace `pane_a.pty` with the appropriate session-qualified
  reference (e.g., `entry1.session.focused_pane.pty`) in the inter-session
  pseudocode block.

---

### SEM-02 — `latest_client_id` referenced but missing from all struct definitions

- **Severity**: minor
- **Phase 1 source**: semantic-verifier
- **Phase 2 verdict**: both agents confirm
- **Locations**:
  - `04-runtime-policies.md` §2.2 — references `latest_client_id` as a tracked
    field per session
  - `01-internal-architecture.md` §3.3 — `Session`, `SessionEntry`,
    `ClientState` struct definitions do not include `latest_client_id`
- **Problem**: `latest_client_id` is used in normative policy text but has no
  struct definition. An implementer cannot determine which struct owns this
  field.
- **Fix required**: Add `latest_client_id` to the appropriate struct in doc01
  §3.3 (most likely `Session`), or if the field was removed, update doc04 §2.2
  to remove the reference.

---

### SEM-03 — `PaneMetadataChanged` always-sent contradicts `ProcessExited` opt-in for exit status

- **Severity**: critical
- **Phase 1 source**: semantic-verifier
- **Phase 2 verdict**: both agents confirm
- **Locations**:
  - `01-internal-architecture.md` §3.6 — `PaneMetadataChanged` delivers
    `is_running: false` and `exit_status` unconditionally to all attached
    clients
  - `04-runtime-policies.md` §9.1 — `PaneMetadataChanged` listed as always-sent
    (no subscription required)
  - `04-runtime-policies.md` §9.2 — `ProcessExited` listed as opt-in
    subscription
- **Problem**: `exit_status` is delivered unconditionally via always-sent
  `PaneMetadataChanged`, but `ProcessExited` (which presumably also carries exit
  status) is opt-in. The documents do not clarify the relationship between these
  two overlapping delivery channels. An implementer cannot determine whether
  `ProcessExited` is redundant, complementary, or the canonical channel for
  exit-related events.
- **Fix required**: Clarify the distinction between `PaneMetadataChanged`
  (metadata field update) and `ProcessExited` (event notification) for process
  exit. Either separate their `exit_status` semantics explicitly or consolidate
  into a single delivery channel.

---

### SEM-05 — `deactivate()` on session focus change breaks multi-client model

- **Severity**: critical
- **Phase 1 source**: semantic-verifier
- **Phase 2 verdict**: both agents confirm
- **Locations**:
  - `02-integration-boundaries.md` §4.3 — specifies eager `deactivate()` on
    session focus change (per-client, when a client switches away from a
    session)
  - `03-lifecycle-and-connections.md` §4.5 — describes multi-client model where
    multiple clients can be attached to the same session simultaneously
- **Problem**: If Client 1 switches away from Session A, §4.3 calls
  `deactivate()` on Session A's shared IME engine. This flushes and clears
  Session A's active preedit composition, disrupting Client 2 (still attached to
  Session A and actively composing). The per-client eager deactivate design
  conflicts with the shared per-session engine model.
- **Fix required**: The daemon team must deliberate whether `deactivate()` scope
  should be per-client or per-session. Options include: (A) scope `deactivate()`
  to per-session (only when all clients leave the session), (B) add a
  reference-count guard before calling `deactivate()`, or (C) document that
  multi-client simultaneous input is not a supported use case.
