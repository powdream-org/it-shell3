# 00012. Latest Resize Policy and Two-State Health Model

- Date: 2026-03-16
- Status: Accepted

## Context

When multiple clients with different terminal sizes are attached to the same
session, the server must decide the effective PTY dimensions. Additionally, the
protocol needs a health model to handle unresponsive clients without
over-complicating the state machine.

## Decision

Two related decisions:

1. **`latest` resize policy as default**: PTY dimensions set to the most
   recently active client's reported size. Matches tmux 3.1+ default. `smallest`
   available as opt-in server config. Stale clients excluded from resize
   calculation.
2. **Two-state client health model**: `healthy` and `stale` only. `paused` is
   orthogonal flow-control state (not a health state). Smooth degradation is
   server-internal (not protocol-visible).

## Consequences

- Active device always gets full screen real estate under `latest` policy.
- Idle device's dimensions do not constrain the active device.
- Minimal protocol surface for health: two states, one notification message
  (ClientHealthChanged).
- Server-internal complexity (smooth degradation, escalation timeline) does not
  leak into the protocol.
