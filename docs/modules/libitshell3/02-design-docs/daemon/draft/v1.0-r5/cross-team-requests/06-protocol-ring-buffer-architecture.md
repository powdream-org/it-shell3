# Move Ring Buffer Architecture and I-Frame Scheduling from Protocol to Daemon

- **Date**: 2026-03-16
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: daemon design docs
- **Status**: open

---

## Context

During owner review of the protocol spec (v1.0-r12), Doc 01 §5.8 (I/P-Frame
Model and Shared Ring Buffer) was identified as containing daemon implementation
details:

- Per-pane ring buffer sizing and architecture (2 MB default, shared ring with
  per-client read cursors)
- O(1) frame serialization and O(1) memory per frame regardless of client count
- Recovery via I-frame seek (all recovery scenarios collapse into cursor
  advance)
- Preedit delivery through the ring buffer (no bypass paths)

These describe how the daemon manages frame storage and delivery internally, not
wire protocol concerns. The wire-observable I/P-frame semantics (frame_type
field, keyframe interval) remain in the protocol spec.

## Required Changes

1. **Ring buffer architecture**: Add per-pane shared ring buffer design — sizing
   (default 2 MB), per-client read cursor tracking, O(1) serialization
   properties.
2. **Recovery via I-frame seek**: Document that all recovery scenarios
   (ContinuePane after PausePane, buffer overrun, stale recovery) collapse into
   advancing the client's ring cursor to the latest I-frame.
3. **Preedit delivery path**: Document that all frames including preedit cell
   data go through the ring buffer with no bypass paths, and that Tier 0
   (Preedit tier) ensures immediate flush for <33ms preedit latency.

## Summary Table

| Target Doc            | Section/Message       | Change Type | Source Resolution             |
| --------------------- | --------------------- | ----------- | ----------------------------- |
| Internal architecture | Ring buffer design    | Add         | Protocol v1.0-r12 Doc 01 §5.8 |
| Runtime policies      | I-frame recovery      | Add         | Protocol v1.0-r12 Doc 01 §5.8 |
| Runtime policies      | Preedit delivery path | Add         | Protocol v1.0-r12 Doc 01 §5.8 |

## Reference: Original Protocol Text (removed from Doc 01 §5.8)

The following is the original text as it appeared in the protocol spec before
removal. Provided as reference for the daemon team — adapt as needed.

### 5.8 I/P-Frame Model and Shared Ring Buffer

The server uses an I-frame/P-frame model with periodic keyframes for
multi-client rendering state delivery, analogous to video codec keyframes:

| Concept                | Description                                                                                                                        |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **I-frame (keyframe)** | Full terminal state — all rows, all CellData. Self-contained: a client receiving only an I-frame has complete state.               |
| **P-frame (delta)**    | Cumulative dirty rows since the most recent I-frame. Independently decodable given only the current I-frame (no sequential chain). |
| **Keyframe interval**  | Default 1 second, configurable. Every keyframe auto-heals any client-side state drift.                                             |

Frames are stored in a **shared per-pane ring buffer** (default 2 MB). The
server serializes each frame once into the ring. Per-client read cursors track
delivery position. This provides O(1) frame serialization and O(1) memory per
frame regardless of client count.

**Recovery**: All recovery scenarios (ContinuePane after PausePane, buffer
overrun, stale recovery) collapse into a single operation: advance the client's
ring cursor to the latest I-frame. The I-frame IS the full state resync — same
data, same wire format, no special codepath.

**Preedit delivery**: All frames, including those containing preedit cell data,
go through the ring buffer. There are no bypass paths. Coalescing Tier 0
(Preedit tier) ensures immediate flush on preedit state change, maintaining
<33ms preedit latency over Unix socket.

See doc 04 Section 4 for the `frame_type` wire format and I/P-frame semantics.
See doc 06 Section 2 for ring buffer sizing, socket write priority, and recovery
procedures.
