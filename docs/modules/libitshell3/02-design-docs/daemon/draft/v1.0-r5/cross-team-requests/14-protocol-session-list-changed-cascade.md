# Session Destroy Cascade and Rename Broadcast Flow

- **Date**: 2026-03-17
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup), ADR 00039
- **Target docs**: daemon design docs
- **Status**: open

---

## Context

During owner review of the protocol spec (v1.0-r12), two server-side behaviors
were identified as daemon implementation concerns and removed from the protocol
docs:

1. **Session destroy cascade**: the sequence of messages the server sends to
   attached clients when a session is destroyed.
2. **Rename broadcast flow**: no daemon-side flow was defined for
   `RenameSessionRequest` → `SessionListChanged(renamed)`.

ADR 00039 decides that `SessionListChanged` is sent for
created/destroyed/renamed events. This CTR specifies the required daemon
implementation for both flows.

## Required Changes

### 1. Session Destroy Cascade

Add to daemon design docs the full server-side procedure when
`DestroySessionRequest` is processed and other clients are attached to the
session:

1. Send `SessionListChanged` with `event: "destroyed"` to **all connected
   clients**.
2. Send forced `DetachSessionResponse` with `reason: "session_destroyed"` to
   every client attached to the destroyed session (except the requesting client,
   which receives the `DestroySessionResponse`).
3. Those clients transition back to READY state.
4. Send `ClientDetached` notification to the requesting client for each detached
   client.

### 2. RenameSession Broadcast Flow

Add to daemon design docs the server-side procedure for `RenameSessionRequest`:

1. Validate request (session exists, new name not already in use).
2. Update session name in daemon state.
3. Send `RenameSessionResponse` with `status: 0` to the requesting client.
4. Send `SessionListChanged` with `event: "renamed"`, `session_id`, and `name`
   (new name) to **all connected clients**.

## Summary Table

| Target Doc       | Area                         | Change Type | Source Resolution |
| ---------------- | ---------------------------- | ----------- | ----------------- |
| Runtime policies | Session destroy cascade      | Add         | ADR 00039         |
| Runtime policies | RenameSession broadcast flow | Add         | ADR 00039         |

## Reference: Original Protocol Text (removed from Doc 03 §1.9)

### From Doc 03 §1.9 DestroySessionRequest

**Cascade behavior for attached clients**: When a session is destroyed while
other clients are attached, the server:

1. Sends `SessionListChanged` with `event: "destroyed"` to ALL connected
   clients.
2. Sends forced `DetachSessionResponse` with `reason: "session_destroyed"` to
   every client attached to the destroyed session (except the requesting client,
   which receives the DestroySessionResponse).
3. Those clients transition back to READY state.
4. Sends `ClientDetached` notification to the requesting client for each
   detached client.
