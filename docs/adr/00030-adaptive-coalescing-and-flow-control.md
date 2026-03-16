# 00030. Adaptive Coalescing and Flow Control

- Date: 2026-03-16
- Status: Accepted

## Context

When a client falls behind on frame consumption, the server needs a flow control
mechanism. Two approaches were considered: (1) back-pressure that stops frame
production when a client is slow, or (2) advisory signaling that warns the
client but never blocks the producer. Additionally, health monitoring must
detect frozen clients -- but if the PTY is idle (no output), the ring cursor
does not advance, creating a blind spot where a frozen client cannot be
distinguished from a healthy idle one.

## Decision

**PausePane is advisory, ring writes are unconditional.** PausePane is a
server-to-client signal sent when a client is falling behind on frame delivery.
It does NOT stop frame production -- the ring writes unconditionally regardless
of any client's consumption rate. PausePane trigger conditions and health
escalation behavior are defined in daemon design docs.

**Idle-PTY blind spot accepted for v1.** When the PTY produces no output, the
ring cursor does not move, so ring cursor stagnation cannot detect a frozen
client. This is mitigated by the `latest` resize policy (the default): an idle
client's dimensions are irrelevant when another client is actively producing
output. For `smallest` policy edge cases where an idle frozen client's
dimensions would matter, `echo_nonce` (application-level heartbeat verification)
is a candidate — its necessity should be revisited post-v1 based on real-world
`smallest` policy adoption. Message range `0x0900` is reserved.

## Consequences

- Frame production is never blocked by a slow client -- other clients and the
  PTY process are unaffected by one client's performance.
- A slow client that cannot keep up will have its ring cursor overwritten; it
  recovers via I-frame (full state resync) rather than stalling the pipeline.
- The idle-PTY blind spot is a known limitation in v1, acceptable because the
  `latest` policy (default) makes idle client dimensions irrelevant. The
  `echo_nonce` necessity should be revisited post-v1 if `smallest` policy
  adoption reveals practical issues.
