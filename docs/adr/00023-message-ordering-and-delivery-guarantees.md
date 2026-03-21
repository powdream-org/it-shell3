# 00023. Message Ordering and Delivery Guarantees

- Date: 2026-03-16
- Status: Accepted

## Context

The protocol delivers two categories of messages to clients: context messages
(e.g., `PreeditSync`, `PreeditUpdate`, `PreeditEnd`) that describe IME
composition state, and content messages (`FrameUpdate`) that carry terminal cell
data reflecting that state. If a frame arrives before its corresponding preedit
context, the client cannot correctly interpret cells in the composition region
-- it would briefly render committed text without knowing the composition just
ended, or render composed cells without the preedit overlay.

The challenge is that frame data flows through a shared per-pane ring buffer
(one write, multiple readers), while context messages are per-client direct
sends. These two channels must be ordered relative to each other.

## Decision

**"Context before content" socket write priority model.** The server maintains
two per-client output channels:

1. **Direct message queue** (priority 1) -- per-client, carries context messages
   such as preedit sync, session management responses, and other targeted
   messages.
2. **Shared ring buffer** (priority 2) -- per-pane, carries frame data (I-frames
   and P-frames) with per-client read cursors.

When a socket becomes writable, the server drains the direct queue first, then
writes ring buffer frames. This guarantees that context messages always arrive
at the client before the `FrameUpdate` that reflects the same state change,
enabling observers to interpret cell data with correct composition context.

## Consequences

- Preedit state and frame data are always consistent from the client's
  perspective -- no transient mismatches where cells show committed text but the
  client still thinks composition is active.
- The two-channel model is simple to implement: one priority check in the socket
  write loop, no cross-message dependency tracking.
- Direct queue messages are small and infrequent relative to frame data, so the
  priority drain does not starve frame delivery in practice.
- The "context before content" guarantee holds across the full session
  lifecycle, not just during live keystroke sequences. At session attach time,
  preedit context (if any pane has active composition) is guaranteed to arrive
  at the client before the I-frames that reflect it, because PreeditSync travels
  through the direct message queue which is always drained first.
- Because preedit rendering is through cell data (not PreeditUpdate), the
  ordering guarantee is a convenience for observers, not a correctness
  requirement. The protocol is resilient to PreeditUpdate being delayed or
  dropped — the FrameUpdate cell data alone is sufficient to render the correct
  preedit state. (See ADR 00021 — Preedit Single-Path Rendering Model.)
