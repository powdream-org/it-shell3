# Design Resolutions: I/P-frame Output Delivery Model

**Version**: v0.7
**Date**: 2026-03-05
**Status**: Resolved (full consensus)
**Participants**: protocol-architect, systems-engineer, cjk-specialist
**Discussion rounds**: 3 (initial positions, wire format refinement, final convergence)
**Source issues**: Review Notes v0.6 -- Issue 22 (Shared Ring Buffer), Issue 23 (Periodic Keyframes), Issue 24 (P-frame Diff Base)

---

## Table of Contents

1. [Issue 24: P-frame Diff Base](#issue-24-p-frame-diff-base)
   - [Resolution 17: Cumulative P-frames from most recent I-frame (Option B)](#resolution-17-cumulative-p-frames-from-most-recent-i-frame-option-b)
2. [Issue 23: Periodic Keyframes](#issue-23-periodic-keyframes)
   - [Resolution 18: Adopt I-frame/P-frame model with 1-second keyframe interval](#resolution-18-adopt-iframe-p-frame-model-with-1-second-keyframe-interval)
   - [Resolution 19: KEYFRAME and UNCHANGED_HINT bits in section_flags](#resolution-19-keyframe-and-unchanged_hint-bits-in-section_flags)
   - [Resolution 20: Per-pane dirty tracking replaces per-client dirty tracking](#resolution-20-per-pane-dirty-tracking-replaces-per-client-dirty-tracking)
   - [Resolution 21: Preedit/keyframe scheduling independence](#resolution-21-preedit-keyframe-scheduling-independence)
   - [Resolution 22: I-frame metadata completeness](#resolution-22-i-frame-metadata-completeness)
   - [Resolution 23: I/P-frame model mandatory in v1](#resolution-23-ip-frame-model-mandatory-in-v1)
3. [Issue 22: Shared Ring Buffer](#issue-22-shared-ring-buffer)
   - [Resolution 24: Shared per-pane ring buffer with per-client read cursors](#resolution-24-shared-per-pane-ring-buffer-with-per-client-read-cursors)
   - [Resolution 25: Ring buffer invariant](#resolution-25-ring-buffer-invariant)
   - [Resolution 26: 512KB delivery lag cap (redefining Resolution 13)](#resolution-26-512kb-delivery-lag-cap-redefining-resolution-13)
   - [Resolution 27: PausePane selective advancement for preedit](#resolution-27-pausepane-selective-advancement-for-preedit)
   - [Resolution 28: Catch-up algorithm](#resolution-28-catch-up-algorithm)
   - [Resolution 29: Coalescing tier interaction with shared ring](#resolution-29-coalescing-tier-interaction-with-shared-ring)
4. [CJK-Specific Validations](#cjk-specific-validations)
5. [Wire Protocol Changes Summary](#wire-protocol-changes-summary)
6. [Prior Art References](#prior-art-references)
7. [Research Inputs](#research-inputs)

---

## Issue 24: P-frame Diff Base

### Resolution 17: Cumulative P-frames from most recent I-frame (Option B)

**Consensus (3/3).** Each P-frame carries the cumulative set of rows changed since the most recent I-frame (KEYFRAME=1). Every P-frame is independently decodable given only the current I-frame. There is no sequential dependency chain between P-frames.

**Rationale**:

1. **Eliminates per-client state tracking.** Under Option A (diff from previous frame), clients at different coalescing tiers would need custom diffs recomputed per client -- reintroducing the O(N) per-client work that Issues 22-23 aim to eliminate. Under Option B, the server generates one P-frame and every client applies it to the same I-frame reference regardless of how many intermediate P-frames were skipped.

2. **CJK wide character integrity.** CJK characters occupy two cells (wide + spacer_tail, as documented in the ghostty research report). Under Option A, a client that skips a P-frame introducing a wide character could receive a subsequent P-frame referencing a spacer_tail cell that was never delivered -- structurally breaking the two-cell invariant. Under Option B, if any wide character changed since the I-frame, BOTH cells are in the cumulative dirty set. Frame skipping cannot break wide character integrity.

3. **Preedit bypass compatibility.** Preedit frames bypass coalescing and PausePane with a <33ms latency target. Under Option A, preedit-carrying P-frames would depend on all prior P-frames in the chain. Under Option B, any P-frame is independently decodable -- a client that skipped P-frames can still correctly render the preedit overlay from the latest P-frame alone.

4. **Error auto-recovery.** Under Option B, each P-frame independently corrects any prior client-side corruption when applied to the I-frame. Under Option A, corruption propagates through the entire chain until the next I-frame.

5. **Prior art confirmation.** All three reference codebases validate cumulative dirty tracking:
   - tmux: re-renders from authoritative state on every redraw -- no sequential chains
   - zellij: OutputBuffer accumulates changed_lines destructively -- no chains
   - ghostty: RenderState.update() tracks dirty rows independently; evolved from full-clone to incremental update with no chain dependency

**Bounded cost**: P-frames grow within a keyframe interval as the cumulative dirty set expands, bounded by terminal row count. Worst case: P-frame equals I-frame size (all rows dirty) -- which means the data legitimately needs to be sent. In practice, typical interactive use changes 5-15 rows per second, keeping P-frames well under I-frame size.

**Cross-issue dependency**: Option B is prerequisite for Issue 22 (shared ring buffer). Option A would reintroduce per-client diff computation, defeating the ring buffer model.

---

## Issue 23: Periodic Keyframes

### Resolution 18: Adopt I-frame/P-frame model with 1-second keyframe interval

**Consensus (3/3).** The server generates periodic keyframes (I-frames) at a default interval of 1 second. Between keyframes, the server generates P-frames carrying cumulative dirty rows (per Resolution 17).

**Keyframe interval**: 1 second default, server-scheduled on a wall-clock timer.

**Bandwidth cost**: ~116KB per I-frame (CJK worst case, 120x40 terminal) = ~116KB/s per pane. 4 panes = ~464KB/s total. This is <0.05% of Unix socket bandwidth (>1GB/s) and <5% of typical SSH bandwidth (~10MB/s).

**The keyframe interval is a server-internal scheduling decision.** It is NOT exposed to the client via FlowControlConfig and NOT negotiated during handshake. The client's contract is: "when you see a frame with KEYFRAME=1, treat it as a new reference point." The server MAY adjust the interval dynamically based on conditions (implementation detail).

**Keyframe triggers**: Scheduled I-frames are emitted on the wall-clock timer. Additionally, forced I-frames are emitted on:

- Client attach
- Terminal resize
- PausePane recovery (ContinuePane)
- Screen switch (primary/alternate)
- Stale recovery resync
- Ring buffer pressure (about to overwrite the most recent I-frame; see Resolution 25)

### Resolution 19: KEYFRAME and UNCHANGED_HINT bits in section_flags

**Consensus (3/3).** Two new bits in the existing `section_flags` (u16 LE) field of the FrameUpdate binary frame header:

```
section_flags (u16 LE):
  Bit 0-3:  reserved (formerly section indicators, now in JSON)
  Bit 4:    DirtyRows section present
  Bit 5-6:  reserved
  Bit 7:    JSONMetadata section present
  Bit 8:    KEYFRAME -- server-scheduled I-frame (reference point, bitmap reset)
  Bit 9:    UNCHANGED_HINT -- advisory: I-frame CellData identical to previous I-frame
  Bit 10-15: reserved
```

No changes to the binary frame header layout. No new fields. No alignment disruption.

#### Truth table (normative)

| KEYFRAME | UNCHANGED | dirty | Meaning |
|----------|-----------|-------|---------|
| 1 | 0 | 2 | I-frame. New reference point. Server resets dirty bitmap. |
| 1 | 1 | 2 | I-frame. New reference. CellData identical to previous I-frame (advisory). |
| 0 | 0 | 0 | P-frame. No grid changes. Metadata only (preedit, cursor). |
| 0 | 0 | 1 | P-frame. Partial dirty set, cumulative since reference I-frame. |
| 0 | 0 | 2 | P-frame. All rows dirty since reference I-frame. NOT a bitmap reset. |

All other combinations are **protocol errors**:

- KEYFRAME=1 requires dirty=2 (I-frames are self-contained by definition).
- UNCHANGED=1 requires KEYFRAME=1 (advisory hint only meaningful on I-frames).
- Invariant chain: UNCHANGED => KEYFRAME => dirty=2.

A receiver that encounters an invalid combination MUST treat it as a protocol error.

#### Rationale for separate KEYFRAME bit (not dirty=2 alone)

The team initially debated whether `dirty=2` alone could serve as the I-frame indicator. Analysis revealed a correctness issue with the server's dirty bitmap reset:

The server resets its per-pane dirty bitmap when emitting an I-frame. Without the KEYFRAME bit, two scenarios arise for P-frames where all rows happen to be dirty (dirty=2):

- **Reset on any dirty=2**: A client that skips a dirty=2 P-frame receives subsequent P-frames with dirty sets relative to the wrong reference -- **corruption**.
- **Never reset on dirty=2 P-frames**: Every P-frame after a dirty=2 P-frame is also dirty=2 until the next scheduled I-frame -- **correct but wastes bandwidth** (potentially 0.9 seconds of I-frame-sized P-frames at Active tier).

The KEYFRAME bit enables a third option: the server can **promote** a dirty=2 P-frame to an I-frame (set KEYFRAME=1, reset bitmap, restart timer). This avoids both corruption and wasted bandwidth. All clients -- including those that skipped ahead -- can safely use KEYFRAME=1 frames as reference points because:

1. The KEYFRAME=1 frame is self-contained (all rows present).
2. The server resets the dirty bitmap, so subsequent P-frames accumulate from this frame.
3. The client's skip-to-keyframe algorithm scans for KEYFRAME=1, not merely dirty=2.

**Implementation note**: When the server promotes a dirty=2 P-frame to an I-frame (sets KEYFRAME=1), it SHOULD reset the dirty bitmap and restart the keyframe interval timer from that point. This is a server-internal optimization (not wire-visible) that produces smaller subsequent P-frames.

#### UNCHANGED_HINT semantics

- Covers **CellData only** (binary DirtyRows/CellData section). JSON metadata (preedit, cursor, colors) MAY differ from previous I-frame.
- A caught-up client receiving UNCHANGED=1 MAY skip grid re-rendering but MUST process JSON metadata.
- A client that jumped to this I-frame from a distant cursor MUST ignore UNCHANGED and render from full CellData.
- **CJK optimization**: During Korean composition on an idle terminal, the grid does not change between keyframes -- only preedit metadata changes. UNCHANGED=1 lets the client avoid rebuilding the cell buffer, updating only the preedit overlay.

### Resolution 20: Per-pane dirty tracking replaces per-client dirty tracking

**Consensus (3/3).** The per-client dirty bitmap model is replaced with a per-pane dirty bitmap model.

**Old (v0.6)**: "The server maintains independent dirty bitmaps per (client, pane) pair. A row's dirty flag for a specific client is cleared only when a FrameUpdate containing that row's data has been sent to that client."

**New (v0.7)**: "The server maintains a single dirty bitmap per pane, tracking rows changed since the most recent I-frame (KEYFRAME=1) emitted for that pane. This bitmap is shared across all clients -- the server does not maintain per-client dirty state. Each P-frame carries the cumulative dirty set from this bitmap. When the server emits an I-frame (KEYFRAME=1), the dirty bitmap is cleared."

**State reduction**: From O(clients x panes x rows) dirty bits to O(panes x rows) dirty bits + O(clients x panes) cursor integers. For 100 clients, 4 panes, 120 rows: old = 48,000 dirty bits maintained per frame event; new = 480 dirty bits + 400 cursors.

### Resolution 21: Preedit/keyframe scheduling independence

**Consensus (3/3).** Preedit state changes MUST NOT trigger keyframe generation. Keyframes are produced on a wall-clock schedule independent of preedit activity. Preedit updates produce P-frames (dirty=0 or dirty=1) with preedit JSON metadata, and flow through the ring buffer like any other frame.

**Rationale**: If preedit updates could trigger keyframe generation (because they happen to land at the keyframe interval boundary), the keyframe scheduler would couple to the preedit bypass path. This coupling would add latency to the <33ms preedit delivery target. The keyframe timer and the preedit bypass path are independent systems.

### Resolution 22: I-frame metadata completeness

**Consensus (3/3).** I-frames (KEYFRAME=1) MUST include full JSON metadata: dimensions, colors, cursor, terminal modes, mouse state, and preedit (if active). This guarantees that an I-frame alone produces a fully renderable state without requiring any subsequent frames.

**Rationale**: A client that skips to an I-frame during catch-up must not need to scan for earlier metadata-carrying frames. The I-frame is self-contained by definition -- this applies to metadata as well as CellData.

### Resolution 23: I/P-frame model mandatory in v1

**Consensus (3/3).** The I/P-frame delivery model is mandatory in v1. No `KEYFRAME_DELIVERY` capability flag is defined.

**Rationale**: There are no deployed v0.x clients requiring backward compatibility. Adding a capability flag would create two codepaths (legacy per-client dirty bitmaps + keyframe ring) that must both be maintained and tested. The whole point of this design is to simplify the server. If v2 changes the keyframe model, protocol version negotiation (version field in the 16-byte header) handles it.

---

## Issue 22: Shared Ring Buffer

### Resolution 24: Shared per-pane ring buffer with per-client read cursors

**Consensus (3/3).** Each pane has a shared ring buffer. The server serializes each frame (I or P) once into the ring. Each client has a read cursor (`frame_sequence` position) per pane. Socket writes read directly from the ring at the cursor position.

**Architecture**:

1. Server generates a frame (I or P) based on the global pane activity tier.
2. Server serializes the FrameUpdate payload once and writes it to the per-pane ring buffer.
3. Each client's I/O loop reads from the ring at its cursor position and sends to the client's socket.
4. The client's cursor advances after each send.
5. If a cursor falls too far behind (>512KB, see Resolution 26), PausePane is triggered.
6. If a cursor points to overwritten data, the server advances it to the latest KEYFRAME=1 frame.

**Memory comparison**:

| Model | 100 clients, 4 panes |
|-------|---------------------|
| Current (per-client buffers) | 100 x 4 x 512KB = **200MB** |
| Ring buffer | 4 x 2MB + 400 cursors = **~8MB** |

**Client cursor semantics**:

- `client_cursor`: The `frame_sequence` of the next frame to deliver.
- **Normal delivery**: Read frame at cursor, send to socket, advance cursor.
- **Skip delivery**: If cursor points to overwritten data, advance to latest KEYFRAME=1 frame.
- The server never tracks which rows a client has received -- only which `frame_sequence` it is at. O(1) per client.

**Protocol-visible behavior**: Unchanged. The `frame_sequence` field already exists in FrameUpdate. Clients already expect gaps in `frame_sequence` due to coalescing. The ring buffer is a server-side implementation detail -- the wire format is identical.

### Resolution 25: Ring buffer invariant

**Consensus (3/3).** The server's per-pane frame ring MUST retain at least the most recent I-frame (KEYFRAME=1) and all P-frames following it. If the ring is about to overwrite the most recent I-frame due to space pressure, the server MUST generate a new I-frame (advancing the keyframe schedule) before allowing the overwrite.

This guarantees that a behind client can always find a valid I-frame to jump to. Catch-up is always a cursor assignment, never synchronous frame generation.

**Ring sizing (non-normative, implementation recommendation)**: The server SHOULD size the ring buffer to hold at least two keyframe intervals of frame data at the expected peak generation rate. For CJK worst case at Active tier with a 1-second keyframe interval, this is approximately 2MB per pane. Implementations targeting ASCII-only workloads can use smaller rings, provided the invariant above is maintained.

### Resolution 26: 512KB delivery lag cap (redefining Resolution 13)

**Consensus (3/3).** Resolution 13's "512KB per (client, pane)" buffer limit is redefined as a **delivery lag cap**: when a client's cursor falls more than 512KB behind the ring write cursor, the server triggers PausePane.

The delivery lag cap and ring size are independent -- the ring can be (and typically is) larger than the lag cap. A 2MB ring with a 512KB PausePane threshold means:

- Clients within 512KB of the write cursor: normal delivery.
- Clients 512KB-2MB behind: PausePane triggered, but their cursor can still skip to the latest I-frame in the ring.
- Clients >2MB behind: impossible, the ring has wrapped and the cursor was already advanced.

### Resolution 27: PausePane selective advancement for preedit

**Consensus (3/3).** During PausePane, the client's ring cursor uses selective advancement:

- **dirty=0 frames** (preedit-only, metadata-only): delivered to the paused client. Cursor advances past them.
- **dirty=1 and dirty=2 frames** (grid data): held. Cursor stops at the first grid frame.

This preserves the settled decision (Resolution 16) that preedit bypasses PausePane, using a single ring and single cursor with no out-of-band delivery channel. Socket load during pause: ~3KB/s from preedit-only frames at typing speed -- negligible.

**Rationale**: The dirty field is load-bearing for flow control under this model. `dirty == 0` is the discriminator for PausePane cursor advancement. Grid frames (dirty > 0) are held; metadata-only frames (dirty == 0) pass through. This is simpler than maintaining a separate preedit delivery channel and ensures preedit state is always current when the client resumes.

### Resolution 28: Catch-up algorithm

**Consensus (3/3).** The following algorithm applies when a client's cursor needs to skip forward (due to ring wrap, ContinuePane, or stale recovery):

```
Client Catch-up Algorithm (on cursor skip or ContinuePane):

1. Find latest KEYFRAME=1 frame in ring. Apply:
   - Full CellData (all rows)
   - Full JSON metadata (dimensions, colors, cursor, preedit, modes)
   This produces a fully renderable state.

2. If newer frames exist after step 1's I-frame (ring head is ahead):
   a. KEYFRAME=1 -> newer I-frame exists, restart from step 1 with this frame
   b. dirty=1 or dirty=2 with KEYFRAME=0 -> apply DirtyRows CellData, apply metadata
   c. dirty=0 -> apply metadata only (preedit/cursor updates)

Maximum 2 ring reads. Deterministic. No intermediate frame replay.
```

**Rationale**: Under Option B (cumulative P-frames), the latest P-frame already contains the full dirty set from the I-frame. There is no need to replay intermediate P-frames. The client needs at most the latest I-frame + the latest subsequent frame (P or metadata-only). JSON metadata is always complete (not delta), so the most recent frame's metadata is authoritative.

**CJK catch-up scenario**: A terminal sitting idle while the user types Korean produces: I-frame (grid state) followed by a series of dirty=0 frames (preedit updates only). A catching-up client applies the I-frame for the grid, then the latest dirty=0 frame for the current preedit state. Two reads, correct result.

### Resolution 29: Coalescing tier interaction with shared ring

**Consensus (3/3).** Under the shared ring model, coalescing tiers change meaning:

**Old model (per-client dirty bitmaps)**: Each client gets a custom frame at its tier rate. The server generates N different frames.

**New model (shared ring + cumulative P-frames)**:

1. The server generates frames at the **fastest coalescing tier** needed by any connected client for that pane.
2. All frames go into the ring.
3. Each client's I/O loop checks its own coalescing timer. When it fires, the client reads the **latest** P-frame from the ring (not the next sequential one).
4. Under Option B (cumulative P-frames), skipping intermediate P-frames is always safe -- the latest P-frame is independently decodable from the reference I-frame.

**Frame generation rate cap**: Grid frames are capped at Active tier (16ms / ~62fps) even if a Preedit-tier client is connected. Preedit-only frames (dirty=0) bypass this cap -- they are generated and delivered immediately on preedit events, written to the ring but orthogonal to the grid frame generation cycle.

**Per-tier frame counts between I-frames** (at 1-second keyframe interval):

| Tier | Interval | Frames per keyframe interval |
|------|----------|------------------------------|
| Active | 16ms | ~62 |
| Bulk | 33ms | ~30 |
| Interactive | 8ms | ~125 |

---

## CJK-Specific Validations

### 1. Wide character integrity across frame skips

**Validated by Option B.** CJK characters occupy two cells (wide + spacer_tail). Under cumulative P-frames, if any wide character changed since the I-frame, both cells are in the dirty set. A client that skips intermediate P-frames and applies only the latest P-frame receives both cells together. The two-cell invariant is preserved regardless of how many frames were skipped.

### 2. Preedit latency preservation

**Validated by Resolution 21 and Resolution 27.** Preedit events bypass both the keyframe scheduler (Resolution 21) and PausePane grid hold (Resolution 27). The preedit delivery path is:

1. Preedit event occurs.
2. Server generates dirty=0 FrameUpdate with preedit JSON metadata.
3. Frame is written to ring buffer.
4. Frame is delivered to client immediately (bypasses coalescing tier timer).
5. During PausePane: dirty=0 frames advance cursor selectively (Resolution 27).

End-to-end preedit latency is unchanged from the pre-I/P-frame model. The <33ms target is preserved.

### 3. UNCHANGED_HINT as CJK composition optimization

**Validated.** During Korean composition on an idle terminal, the grid does not change between keyframes -- only preedit metadata changes. The UNCHANGED_HINT allows caught-up clients to skip cell buffer reconstruction on each keyframe, updating only the preedit overlay from JSON metadata. This is a measurable rendering optimization for the common CJK typing scenario.

### 4. Preedit state after catch-up

**Validated by Resolution 22 and Resolution 28.** I-frames carry full JSON metadata including preedit state (Resolution 22). During catch-up, the client applies the I-frame first (getting current preedit state), then optionally applies the latest subsequent frame's metadata (which may have newer preedit state). Preedit state is never lost during catch-up.

---

## Wire Protocol Changes Summary

### Modified fields

| Field | Location | Change | Doc |
|-------|----------|--------|-----|
| `section_flags` bit 8 | FrameUpdate binary frame header | New: KEYFRAME flag | Doc 04 |
| `section_flags` bit 9 | FrameUpdate binary frame header | New: UNCHANGED_HINT flag | Doc 04 |
| `dirty` field semantics | FrameUpdate binary frame header | Redefined: 0=metadata-only P-frame, 1=partial P-frame (cumulative), 2=full (I-frame when KEYFRAME=1, or all-rows-dirty P-frame when KEYFRAME=0) | Doc 04 |

### Removed concepts

| Concept | Was in | Replaced by |
|---------|--------|-------------|
| Per-client dirty bitmaps | Doc 04 Section 4.1 normative note | Per-pane dirty bitmap (Resolution 20) |
| Per-client output buffers (512KB each) | Doc 06 Section 2 | Shared per-pane ring buffer + delivery lag cap (Resolutions 24, 26) |

### Doc changes needed

| Doc | Section | Change |
|-----|---------|--------|
| Doc 01 | Protocol overview | Add I/P-frame delivery model to architecture overview. Document KEYFRAME and UNCHANGED_HINT bits in section_flags reference. |
| Doc 02 | Handshake | No changes. I/P-frame model is mandatory in v1 (no capability flag). |
| Doc 04 | Section 4.1 (FrameUpdate) | Add KEYFRAME (bit 8) and UNCHANGED_HINT (bit 9) to section_flags. Add truth table. Add I-frame metadata completeness requirement. |
| Doc 04 | Section 4.1 normative note | Replace per-client dirty tracking with per-pane cumulative dirty tracking. |
| Doc 04 | Section 4.3 (DirtyRows) | Redefine DirtyRows as "cumulative since reference I-frame" (not "since last client send"). |
| Doc 04 | Section 7 (dirty modes) | Update dirty=0/1/2 descriptions for I/P-frame semantics. Add preedit/keyframe independence note. |
| Doc 04 | New section | Add catch-up algorithm specification (Resolution 28). |
| Doc 06 | Section 2 (output queue) | Replace per-client output buffer model with shared per-pane ring buffer. Add ring buffer invariant (Resolution 25). Add ring sizing recommendation. |
| Doc 06 | Section 2 (buffer limit) | Redefine 512KB as delivery lag cap (Resolution 26). |
| Doc 06 | Section 2 (PausePane) | Add selective advancement for dirty=0 frames (Resolution 27). |
| Doc 06 | Section 2 (ContinuePane) | Add catch-up procedure (skip-to-keyframe). |
| Doc 06 | Coalescing section | Update: server generates at global tier rate, clients read at own rate (Resolution 29). |

### Deferred to v2

| Item | Rationale |
|------|-----------|
| `KEYFRAME_DELIVERY` capability flag | Not needed in v1 (model is mandatory). May be needed in v2 if the keyframe model changes. |
| `keyframe_interval_ms` in FlowControlConfig | Keyframe interval is server-internal for v1. May be exposed if clients need to detect server scheduling anomalies. |

---

## Prior Art References

| Decision | tmux precedent | zellij precedent | ghostty precedent |
|----------|---------------|-------------------|-------------------|
| Cumulative dirty tracking (Option B) | Every redraw re-reads full authoritative state. No sequential delta chains. | OutputBuffer accumulates changed_lines; consumed destructively on read. | RenderState.update() evolved from full-clone to incremental -- no chain dependency. |
| Periodic keyframes | No periodic keyframes. Full redraws are event-driven only (attach, resize, TTY_BLOCK recovery). | No periodic full redraws. `set_force_render()` is event-driven. | Periodic state reset every 100,000 frames (~12 min at 120fps) for memory safety. |
| Discard-and-resync recovery | TTY_BLOCK: discard all pending, 100ms timer, full redraw from authoritative state. | Disconnect client on bounded(5000) channel overflow. Devs acknowledge wanting "redraw-on-backpressure mechanism." | `markDirty()` forces full redraw at any time. |
| Shared vs per-client output | Per-client `tty->out` evbuffer (fan-out). No shared buffer. | Per-client CharacterChunk clone with TODO comment acknowledging suboptimality. | Single Terminal behind mutex; RenderState is renderer-local snapshot. |
| Event-driven rendering | Redraws only on specific events. No timer-based periodic redraws. | 10ms debounce. No timer-based periodic redraws. | Event-driven via `xev.Async.notify()` with natural coalescing. Commented-out timer code was abandoned. |
| Dirty granularity | Global `PANE_REDRAW` flag + per-client 64-bit pane bitmask for deferral. No per-row tracking. | Per-line `changed_lines: HashSet<usize>` in OutputBuffer. | Three-tier: Terminal-level, Page-level, Row-level (1 bit per row). No per-cell tracking. |

---

## Research Inputs

The following research reports were produced by tmux-expert, zellij-expert, and ghostty-expert agents and served as evidence for the discussion:

- `research-tmux-frame-delivery.md` -- tmux multi-client frame delivery analysis (per-client buffering, TTY_BLOCK mechanism, discard-and-redraw pattern, control mode output)
- `research-zellij-frame-delivery.md` -- zellij multi-client frame delivery analysis (per-client render state, bounded channel behavior, full screen redraws, plugin vs terminal pane rendering, multi-client output routing)
- `research-ghostty-dirty-tracking.md` -- ghostty dirty tracking and frame generation analysis (three-tier dirty hierarchy, full vs partial redraw, VT-to-render pipeline, cell data structures)
