# Move Health Escalation and Recovery Procedures from Protocol to Daemon

- **Date**: 2026-03-16
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: daemon design docs
- **Status**: open

---

## Context

During owner review of the protocol spec (v1.0-r12), Doc 01 §5.7 (Client Health
Model) was identified as containing references to daemon implementation details:

- Health escalation timeline and timeout values
- Stale recovery procedure
- Stale client eviction policy

The protocol spec defines the two health states (`healthy` and `stale`) and
their wire-observable properties (resize participation, frame delivery).
However, the escalation timeline, timeout values, and the stale recovery
procedure are server-internal policies that belong in daemon design docs. Doc 01
§5.7 already defers these to daemon design docs — this CTR ensures they are
actually defined there.

## Required Changes

1. **Health escalation timeline**: Define timeout values for transitioning from
   `healthy` to `stale` (e.g., heartbeat miss count, output queue stagnation
   threshold).
2. **Stale recovery procedure**: Define the recovery sequence when a stale
   client resumes — LayoutChanged + PreeditSync via direct queue before the
   I-frame.
3. **Stale client eviction**: Define when and how the server sends `Disconnect`
   with reason `stale_client` to evict unresponsive clients.
4. **Health escalation details (from Doc 06)**: Define escalation timeline,
   stale triggers, timeout values, smooth degradation, and recovery procedures
   as referenced by the protocol's Client Health Model section.
5. **Recovery wire behavior (from Doc 06)**: Document that all recovery
   scenarios (ContinuePane, ring overwrite, stale recovery) result in the server
   advancing the client's ring cursor to the latest I-frame. On stale recovery,
   the server additionally sends LayoutChanged and PreeditSync (if applicable)
   before the I-frame.
6. **Heartbeat RTT heuristic (from Doc 06)**: Server-side heartbeat RTT
   measurement (time between sending Heartbeat and receiving HeartbeatAck) MAY
   be used as an implementation-level heuristic (e.g., RTT >60s for 2
   consecutive heartbeats suggests event loop stall). This is non-normative
   implementation guidance, not a protocol state trigger.

## Summary Table

| Target Doc       | Section/Message            | Change Type | Source Resolution             |
| ---------------- | -------------------------- | ----------- | ----------------------------- |
| Runtime policies | Health escalation timeline | Add         | Protocol v1.0-r12 Doc 01 §5.7 |
| Runtime policies | Stale recovery procedure   | Add         | Protocol v1.0-r12 Doc 01 §5.7 |
| Runtime policies | Stale client eviction      | Add         | Protocol v1.0-r12 Doc 01 §5.7 |
| Runtime policies | Health escalation details  | Add         | Protocol v1.0-r12 Doc 06 §2.8 |
| Runtime policies | Recovery wire behavior     | Add         | Protocol v1.0-r12 Doc 06 §2.9 |
| Runtime policies | Heartbeat RTT heuristic    | Add         | Protocol v1.0-r12 Doc 06 §7.3 |

## Reference: Original Protocol Text (removed from Doc 01 §5.7)

The following is the original text as it appeared in the protocol spec. The
wire-observable health states remain in the protocol spec; the daemon-internal
escalation, timeout, and recovery details referenced below are what this CTR
asks the daemon team to define.

### 5.7 Client Health Model

The protocol defines two health states orthogonal to connection lifecycle:

| State     | Definition                               | Resize participation      | Frame delivery                                                                                               |
| --------- | ---------------------------------------- | ------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `healthy` | Normal operation                         | Yes                       | Full (per coalescing tier)                                                                                   |
| `stale`   | Paused too long or output queue stagnant | No (excluded from resize) | None (ring cursor stagnant). Recovery sends LayoutChanged + PreeditSync via direct queue before the I-frame. |

`paused` (PausePane active) is an orthogonal flow-control state, not a health
state. A paused client remains `healthy` until the stale timeout fires.

Server MAY send `Disconnect` with reason `stale_client` to evict unresponsive
clients. Health state transitions are communicated via `ClientHealthChanged`
(0x0185) notifications, sent to all peer clients attached to the same session.
Health escalation timeline, timeout values, and the stale recovery procedure are
defined in daemon design docs. See doc 06 Section 2 for wire message
definitions.

## Reference: Original Protocol Text (removed from Doc 06)

The following is the original text from Doc 06 that references daemon
implementation details for health escalation and recovery. These sections remain
in the protocol spec as forward-references to daemon design docs; the text below
provides context for what the daemon must define.

### From Doc 06 §2.8 — Client Health Model

The protocol defines two health states orthogonal to connection lifecycle:

| State     | Definition                              | Resize participation | Frame delivery                      |
| --------- | --------------------------------------- | -------------------- | ----------------------------------- |
| `healthy` | Normal operation                        | Yes                  | Full (per coalescing tier) via ring |
| `stale`   | Paused too long or ring cursor stagnant | No                   | None (ring cursor stagnant)         |

`paused` (PausePane active) is an orthogonal flow-control state, not a health
state. Health state transitions are communicated via `ClientHealthChanged`
(0x0185) notifications. Server MAY send `Disconnect` with reason `stale_client`
to evict unresponsive clients.

Health escalation timeline, stale triggers, timeout values, smooth degradation,
and recovery procedures are defined in daemon design docs.

### From Doc 06 §2.9 — Recovery Wire Behavior

All recovery scenarios (ContinuePane, ring overwrite, stale recovery) result in
the server advancing the client's ring cursor to the latest I-frame. On stale
recovery, the server additionally sends `LayoutChanged` and `PreeditSync` (if
applicable) before the I-frame.

### From Doc 06 §7.3 — Server-Side Heartbeat RTT Heuristic

Server-side heartbeat RTT measurement (time between sending Heartbeat and
receiving HeartbeatAck) MAY be used as an implementation-level heuristic (e.g.,
RTT >60s for 2 consecutive heartbeats suggests event loop stall). This is
non-normative implementation guidance, not a protocol state trigger.
