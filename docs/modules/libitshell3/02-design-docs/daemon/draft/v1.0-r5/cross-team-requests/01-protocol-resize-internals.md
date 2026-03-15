# Move Resize Algorithm Internals from Protocol to Daemon

- **Date**: 2026-03-16
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: daemon design docs (runtime policies or integration
  boundaries)
- **Status**: open

---

## Context

During owner review of the protocol spec (v1.0-r12), the following subsections
in Doc 03 (Session and Pane Management) §5 were identified as daemon
implementation details, not wire protocol concerns:

- §5.3 `latest_client_id` Tracking — which events update the latest client,
  fallback logic when latest client detaches/becomes stale
- §5.4 Resize Wire Behavior — the sequence of LayoutChanged + I-frame + Ack
  (partially wire, partially daemon orchestration)
- §5.5 Stale Client Exclusion — stale exclusion policy, re-inclusion hysteresis
- §5.6 Client Detach Resize — recompute on detach

These will be removed from the protocol spec. The daemon design docs should
absorb this content.

## Required Changes

1. **`latest_client_id` tracking**: Add a section describing how the server
   tracks the most recently active client per session. Activity triggers:
   KeyEvent, WindowResize (NOT HeartbeatAck). Fallback: next
   most-recently-active healthy client, then largest dimensions.

2. **Resize orchestration**: When effective size changes, the server sends
   LayoutChanged to all clients, writes I-frame(s) for affected panes, sends
   WindowResizeAck to the requesting client. Include debounce, PTY ioctl, and
   coalescing tier suppression details.

3. **Stale client exclusion**: Stale clients excluded from resize calculation.
   Re-inclusion hysteresis policy.

4. **Client detach resize**: Server recomputes effective size on detach, sends
   LayoutChanged if size changes.

## Summary Table

| Target Doc       | Section/Message        | Change Type | Source Resolution    |
| ---------------- | ---------------------- | ----------- | -------------------- |
| Runtime policies | Resize algorithm       | Add         | Protocol v1.0-r12 §5 |
| Runtime policies | latest_client_id       | Add         | Protocol v1.0-r12 §5 |
| Runtime policies | Stale client exclusion | Add         | Protocol v1.0-r12 §5 |
| Runtime policies | Client detach resize   | Add         | Protocol v1.0-r12 §5 |

## Reference: Original Protocol Text (removed from Doc 03 §5)

The following is the original text as it appeared in the protocol spec before
removal. Provided as reference for the daemon team — adapt as needed.

### `latest_client_id` Tracking

The server tracks `latest_client_id` per session, updated on:

- KeyEvent received from a client
- WindowResize received from a client
- NOT on HeartbeatAck (passive liveness does not indicate active use)

When the latest client detaches or becomes stale, the server falls back to the
next most-recently-active healthy client. If no client has any recorded
activity, fall back to the client with the largest terminal dimensions.

### Resize Wire Behavior

When the server determines the effective terminal size has changed, it:

1. Sends `LayoutChanged` to ALL attached clients with updated pane dimensions.
2. Writes I-frame(s) for affected panes to the ring buffer.
3. Sends `WindowResizeAck` to the sending client.

The resize algorithm internals (policy computation, debounce, PTY ioctl,
coalescing tier suppression during resize) are defined in daemon design docs.

### Stale Client Exclusion

Clients in the `stale` health state are excluded from the resize calculation.
Stale exclusion policy, re-inclusion hysteresis, and client detach resize
behavior are defined in daemon design docs.

### Client Detach Resize

When a client detaches, the server recomputes the effective size and sends
`LayoutChanged` if the size changes.
