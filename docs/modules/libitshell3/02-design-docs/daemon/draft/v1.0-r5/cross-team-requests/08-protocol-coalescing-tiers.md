# Move Coalescing Tier Internals and Client Power Adaptation from Protocol to Daemon

- **Date**: 2026-03-16
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: daemon design docs
- **Status**: open

---

## Context

During owner review of the protocol spec (v1.0-r12), Doc 01 §10 (FrameUpdate
Delivery Model) was identified as containing references to daemon implementation
details:

- Coalescing tier definitions and timing values
- Tier transition rules
- WAN adaptation rules
- Power state throttling

The protocol spec defines the wire-observable properties (per-(client, pane)
delivery, preedit prioritization, client hints via `ClientDisplayInfo`).
However, the coalescing tier definitions, tier transitions, WAN adaptation, and
power state throttling are server-internal policies that belong in daemon design
docs. Doc 01 §10 already defers these to daemon design docs — this CTR ensures
they are actually defined there.

## Required Changes

1. **Coalescing tier definitions**: Define tiers (e.g., Tier 0 Preedit, Tier 1
   Interactive, Tier 2 Bulk) with their timing values and flush policies.
2. **Tier transition rules**: Define when and how the server transitions between
   coalescing tiers based on output patterns.
3. **WAN adaptation**: Define how the server adapts coalescing behavior for SSH
   tunnel connections using `ClientDisplayInfo` hints (`transport_type`,
   `estimated_rtt_ms`, `bandwidth_hint`).
4. **Power state throttling**: Define how the server reduces frame delivery rate
   when the client reports low-power state via `ClientDisplayInfo.power_state`.
5. **Coalescing background (from Doc 06)**: Document that the server uses
   adaptive coalescing to send FrameUpdates in response to terminal state
   changes. Coalescing is per-(client, pane). Preedit state changes are always
   delivered with minimal latency. Define coalescing tier definitions,
   transition thresholds, timing values, WAN adaptation rules, power throttling
   caps, and idle suppression during resize.

## Summary Table

| Target Doc       | Section/Message             | Change Type | Source Resolution             |
| ---------------- | --------------------------- | ----------- | ----------------------------- |
| Runtime policies | Coalescing tier definitions | Add         | Protocol v1.0-r12 Doc 01 §10  |
| Runtime policies | Tier transition rules       | Add         | Protocol v1.0-r12 Doc 01 §10  |
| Runtime policies | WAN adaptation              | Add         | Protocol v1.0-r12 Doc 01 §10  |
| Runtime policies | Power state throttling      | Add         | Protocol v1.0-r12 Doc 01 §10  |
| Runtime policies | Coalescing background       | Add         | Protocol v1.0-r12 Doc 06 §1.1 |

## Reference: Original Protocol Text (removed from Doc 01 §10)

The following is the original text as it appeared in the protocol spec. The
wire-observable delivery properties remain in the protocol spec; the
daemon-internal coalescing details referenced below are what this CTR asks the
daemon team to define.

### 10. FrameUpdate Delivery Model

FrameUpdates are not sent at a fixed rate. The server sends them in response to
terminal state changes (PTY output, preedit state changes, resize events). The
server uses adaptive coalescing to batch rapid state changes into fewer
FrameUpdates, balancing latency and throughput.

**Wire-observable properties:**

- **Per-(client, pane) delivery**: Each pane's FrameUpdate stream is
  independent.
- **Preedit state changes are delivered with minimal latency.** The server
  prioritizes preedit FrameUpdates over bulk output.
- **Client hints**: `ClientDisplayInfo` provides `display_refresh_hz`,
  `power_state`, `preferred_max_fps`, `transport_type`, `estimated_rtt_ms`,
  `bandwidth_hint` for server-side adaptation.

Coalescing tier definitions, timing values, tier transitions, WAN adaptation
rules, and power state throttling are defined in daemon design docs.

## Reference: Original Protocol Text (removed from Doc 06)

The following is the original text from Doc 06 that references daemon
implementation details for coalescing. This section remains in the protocol spec
as a forward-reference to daemon design docs; the text below provides context
for what the daemon must define.

### From Doc 06 §1.1 — Background

libitshell3 does not use a fixed frame rate. The server uses adaptive coalescing
to send FrameUpdates in response to terminal state changes. Coalescing is
per-(client, pane) — each client receives FrameUpdates at a rate adapted to its
display, power state, and transport conditions. Preedit state changes are always
delivered with minimal latency.

Coalescing tier definitions, transition thresholds, timing values, WAN
adaptation rules, power throttling caps, and idle suppression during resize are
defined in daemon design docs.
