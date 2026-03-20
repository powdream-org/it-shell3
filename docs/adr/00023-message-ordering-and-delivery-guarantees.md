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
- For a single composition keystroke, the server sends messages in this order:
  PreeditUpdate (0x0401) first, then FrameUpdate (0x0300). For composition end:
  PreeditEnd (0x0402) first, then FrameUpdate. PreeditUpdate/PreeditEnd are sent
  "first for observers" — they travel through the direct message queue, which is
  drained before ring buffer frames on each socket-writable event.
- Because preedit rendering is through cell data (not PreeditUpdate), the
  ordering guarantee is a convenience for observers, not a correctness
  requirement. The protocol is resilient to PreeditUpdate being delayed or
  dropped — the FrameUpdate cell data alone is sufficient to render the correct
  preedit state. (See ADR 00021 — Preedit Single-Path Rendering Model.)
