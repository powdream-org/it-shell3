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
4. **Ring buffer background (from Doc 06)**: Document that when a pane produces
   output faster than a client can consume it, the server manages delivery
   through a shared per-pane ring buffer with per-client read cursors and an
   I/P-frame model.
5. **Two-channel socket write priority**: Implement per-client two-channel
   output model — direct message queue (priority 1) and shared ring buffer
   (priority 2). When a socket becomes writable, drain the direct queue first,
   then write ring buffer frames.
6. **Ring cursor reset on ContinuePane**: On ContinuePane, advance the client's
   ring cursor to the latest I-frame. The client receives the I-frame (complete
   self-contained terminal state) and resumes normal incremental delivery. No
   `last_processed_seq` field is needed — the ring cursor position already
   tracks the client's state.
7. **Per-pane dirty tracking**: Document that the server maintains a single
   dirty bitmap per pane, that frame data is serialized once per pane per frame
   interval into the shared ring buffer, and that all clients viewing the same
   pane receive identical frame data (clients at different coalescing tiers
   receive different subsets of frames, but each frame's content is identical).
8. **I-frame scheduling algorithm**: Document the I-frame timer behavior —
   default 1-second interval (configurable 0.5–5 seconds), no frame written when
   no changes since last I-frame, I-frame containing all rows when changes
   exist, and timer independence from coalescing tiers.
9. **Preedit ring buffer interaction and direct queue ordering (from Doc 05
   §13.1)**: Document that all frames (including those containing preedit cell
   data) go through the per-pane shared ring buffer with no separate bypass path
   for preedit; that Coalescing Tier 0 ensures preedit-containing frames are
   written to the ring immediately upon keystroke; that the dedicated preedit
   protocol messages (0x0400-0x0405) are sent directly per-client via the direct
   message queue (outside the ring buffer); and that PreeditSync is enqueued in
   the direct message queue (priority 1) during resync/recovery, arriving BEFORE
   the I-frame from the ring, following the "context before content" principle.
10. **Multi-client ring read and coalescing tier linkage (from Doc 02 §8.6)**:
    Document that all clients receive `FrameUpdate` messages for all panes in
    the attached session from the shared per-pane ring buffer (not just the
    focused pane), and that each client reads from the ring at its own cursor
    position via per-(client, pane) coalescing tiers.

## Summary Table

| Target Doc            | Section/Message                         | Change Type | Source Resolution              |
| --------------------- | --------------------------------------- | ----------- | ------------------------------ |
| Internal architecture | Ring buffer design                      | Add         | Protocol v1.0-r12 Doc 01 §5.8  |
| Runtime policies      | I-frame recovery                        | Add         | Protocol v1.0-r12 Doc 01 §5.8  |
| Runtime policies      | Preedit delivery path                   | Add         | Protocol v1.0-r12 Doc 01 §5.8  |
| Internal architecture | Ring buffer background                  | Add         | Protocol v1.0-r12 Doc 06 §2.1  |
| Internal architecture | Two-channel write priority              | Add         | Protocol v1.0-r12 Doc 06 §2.3  |
| Runtime policies      | ContinuePane cursor reset               | Add         | Protocol v1.0-r12 Doc 06 §2.5  |
| Internal architecture | Per-pane dirty tracking                 | Add         | Protocol v1.0-r12 Doc 04 §3.1  |
| Internal architecture | I-frame scheduling                      | Add         | Protocol v1.0-r12 Doc 04 §7.3  |
| Runtime policies      | Preedit ring/direct queue ordering      | Add         | Protocol v1.0-r12 Doc 05 §13.1 |
| Internal architecture | Multi-client ring read / coalescing tie | Add         | Protocol v1.0-r12 Doc 02 §8.6  |

## Reference: Original Protocol Text

### From Doc 01 §5.8 — I/P-Frame Model and Shared Ring Buffer

The following is the original text as it appeared in the protocol spec before
removal. Provided as reference for the daemon team — adapt as needed.

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

### From Doc 06 — cross-reference (ring buffer architecture)

The following is the original text from Doc 06 that references daemon
implementation details. These sections remain in the protocol spec as
forward-references to daemon design docs; the text below provides context for
what the daemon must define.

#### From Doc 06 §2.1 — Background

When a pane produces output faster than a client can consume it, the server
manages delivery through a shared per-pane ring buffer with per-client read
cursors and an I/P-frame model (doc 04). Ring buffer architecture and
implementation details are defined in daemon design docs.

#### From Doc 06 §2.3 — Delivery Model Overview (Two-Channel Mechanism)

The server maintains a shared per-pane ring buffer for frame delivery. All frame
data (I-frames and P-frames) is written once to the ring. Per-client read
cursors track each client's delivery position. Ring buffer architecture, sizing,
implementation model, and concurrency details are defined in daemon design docs.

**Socket write priority model**: The server maintains two per-client output
channels: a direct message queue (priority 1) and the shared ring buffer
(priority 2). When a socket becomes writable, the server drains the direct queue
first, then writes ring buffer frames. This guarantees that context messages
(e.g., `PreeditSync`, `PreeditUpdate`, `PreeditEnd`) always arrive at the client
before the `FrameUpdate` that reflects the same state change — enabling
observers to interpret cell data with correct composition context.

#### From Doc 06 §2.5 — ContinuePane Ring Cursor Reset

The server advances the client's ring cursor to the latest I-frame. The client
receives the I-frame (a complete self-contained terminal state) and resumes
normal incremental delivery from that point. No `last_processed_seq` field is
needed — the ring cursor position already tracks the client's state.

### From Doc 04 — daemon implementation details

The following is the original text from Doc 04 that contains daemon
implementation details. Provided as reference for the daemon team — adapt as
needed.

#### From Doc 04 §3.1 — Per-Pane Dirty Tracking (I/P-Frame Model)

> **Normative note — Per-pane dirty tracking (I/P-frame model)**: The server
> maintains a single dirty bitmap per pane. Frame data (I-frames and P-frames)
> is serialized once per pane per frame interval and written to the shared
> per-pane ring buffer. All clients viewing the same pane receive identical
> frame data from the ring buffer. Clients at different coalescing tiers receive
> different subsets of frames from the same sequence, but each frame's content
> is identical regardless of which client receives it.

#### From Doc 04 §7.3 — I-Frame Scheduling Algorithm

**I-frame scheduling**: I-frames (keyframes) are produced periodically (default:
every 1 second, configurable 0.5-5 seconds via server configuration). When the
I-frame timer fires and the pane has no changes since the last I-frame, no frame
is written to the ring buffer — the most recent I-frame already in the ring
provides correct state for any seeking client. When the timer fires and changes
exist, the server sends `frame_type=1` (I-frame) containing all rows. The
I-frame timer is independent of the coalescing tiers — it fires at a fixed
interval regardless of PTY throughput.

### From Doc 05 §13.1 — Ring Buffer Interaction

The following is the original text from Doc 05 §13.1 (CJK Preedit Sync and IME
Protocol) describing ring buffer interaction with preedit. Provided as reference
for the daemon team — adapt as needed.

**Ring buffer interaction**: All frames (including those containing preedit cell
data) go through the per-pane shared ring buffer. There is no separate bypass
path for preedit. Coalescing Tier 0 (Preedit tier, immediate flush at 0ms)
ensures preedit-containing frames are written to the ring immediately upon
keystroke. The dedicated preedit protocol messages (0x0400-0x0405) remain
outside the ring buffer — they are sent directly per-client via the direct
message queue. PreeditSync is enqueued in the direct message queue (priority 1)
during resync/recovery, arriving BEFORE the I-frame from the ring. This follows
the "context before content" principle — the client processes PreeditSync first
(records composition metadata), then processes the I-frame (renders grid
including preedit cells with full context). See doc 06 for the full socket write
priority model.

### From Doc 02 §8.6 — Frame Updates (Multi-Client Session Behavior)

The following is the original text from Doc 02 §8.6 (multi-client session
behavior) describing the per-pane ring buffer and per-(client, pane) coalescing
tier linkage. Provided as reference for the daemon team — adapt as needed.

4. **Frame updates**: All clients receive `FrameUpdate` messages for all panes
   in the attached session from the shared per-pane ring buffer, not just the
   focused pane. Each client reads from the ring at its own cursor position via
   per-(client, pane) coalescing tiers.
