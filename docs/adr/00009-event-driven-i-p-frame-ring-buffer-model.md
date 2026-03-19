# 00009. Event-Driven I/P-Frame Ring Buffer Model

- Date: 2026-03-16
- Status: Accepted

## Context

The protocol needs to deliver terminal state updates to multiple clients
efficiently. Key tensions: per-client dirty tracking cost, frame skipping for
slow clients, bandwidth for idle panes, and memory for per-client buffers.

A session contains multiple panes, all potentially visible simultaneously. The
server must deliver frame updates for every dirty pane — not just the focused
one — because the client renders the full session layout. This means a single
connection carries interleaved frames from multiple panes, requiring each
FrameUpdate to identify which pane it belongs to.

## Decision

Four related decisions form the frame delivery model:

1. **Event-driven delivery** (not fixed fps): 4-tier adaptive coalescing. Real
   terminal workloads are 0-30 updates/s. No fixed frame rate target.
2. **I/P-frame model**: Two frame types — P-frame (partial, dirty rows only) and
   I-frame (full keyframe, all rows). Periodic I-frames (default 1s) provide
   auto-healing for state drift.
3. **Shared per-pane ring buffer**: Server serializes each frame once into a
   per-pane ring. Per-client read cursors (12 bytes each) replace per-client
   buffers (512KB each). The server delivers FrameUpdates for all dirty panes in
   the session, not just the focused pane. Each FrameUpdate carries a `pane_id`
   precisely because frames from multiple panes are multiplexed over the same
   connection.
4. **Cumulative P-frame diff base**: P-frames reference the most recent I-frame
   (not previous P-frame). Any P-frame is independently decodable with just the
   current I-frame. Clients may skip intermediate P-frames freely.

## Consequences

- Eliminates per-client dirty bitmaps: O(N) to O(1).
- Memory: O(panes x ring_size) + O(clients) for cursors, not O(clients x
  buffer_size).
- No sequential P-frame chain — clients at different coalescing tiers skip
  different subsets without per-client diff computation.
- Idle panes produce no frames (no byte-identical I-frame duplicates).
