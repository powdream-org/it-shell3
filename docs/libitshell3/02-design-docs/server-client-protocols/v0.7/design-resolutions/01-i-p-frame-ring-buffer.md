# Design Resolutions: I/P-Frame Model, Shared Ring Buffer, and P-Frame Diff Base

**Version**: v0.7
**Date**: 2026-03-05
**Status**: Resolved (unanimous consensus)
**Participants**: protocol-architect, system-sw-engineer, cjk-specialist, ime-expert, principal-architect
**Discussion rounds**: Multiple (positions, counterarguments, wire format convergence, final confirmation)
**Source issues**: Owner Architectural Review Issues 22, 23, 24 (`review-notes/03-owner-architectural-review.md`)

---

## Table of Contents

1. [Issue 24: P-Frame Diff Base](#issue-24-p-frame-diff-base)
   - [Resolution 1: Option B — cumulative diff from most recent I-frame](#resolution-1-option-b--cumulative-diff-from-most-recent-i-frame)
2. [Issue 23: Periodic Keyframes (I/P-Frame Model)](#issue-23-periodic-keyframes-ip-frame-model)
   - [Resolution 2: Adopt I/P-frame model with periodic keyframes](#resolution-2-adopt-ip-frame-model-with-periodic-keyframes)
   - [Resolution 3: 1-second default keyframe interval](#resolution-3-1-second-default-keyframe-interval)
   - [Resolution 4: Wire format — `frame_type` field replaces `dirty`](#resolution-4-wire-format--frame_type-field-replaces-dirty)
   - [Resolution 5: Keyframe self-containment rule](#resolution-5-keyframe-self-containment-rule)
   - [Resolution 6: `unchanged` advisory hint — strict server-side rule](#resolution-6-unchanged-advisory-hint--strict-server-side-rule)
   - [Resolution 7: No `keyframe_sequence` field — implicit reference rule](#resolution-7-no-keyframe_sequence-field--implicit-reference-rule)
   - [Resolution 8: No capability negotiation for I/P-frame model](#resolution-8-no-capability-negotiation-for-ip-frame-model)
   - [Resolution 9: No client-to-server keyframe acknowledgment](#resolution-9-no-client-to-server-keyframe-acknowledgment)
   - [Resolution 10: Per-pane dirty bitmap replaces per-client dirty bitmaps](#resolution-10-per-pane-dirty-bitmap-replaces-per-client-dirty-bitmaps)
3. [Issue 22: Shared Ring Buffer](#issue-22-shared-ring-buffer)
   - [Resolution 11: Adopt shared per-pane ring buffer](#resolution-11-adopt-shared-per-pane-ring-buffer)
   - [Resolution 12: 2 MB default ring size per pane](#resolution-12-2-mb-default-ring-size-per-pane)
   - [Resolution 13: Retire 512KB per-client buffer limit — ring size is single resync knob](#resolution-13-retire-512kb-per-client-buffer-limit--ring-size-is-single-resync-knob)
   - [Resolution 14: Recovery codepath unification — advance cursor to latest I-frame](#resolution-14-recovery-codepath-unification--advance-cursor-to-latest-i-frame)
   - [Resolution 15: PausePane role shift — advisory signal, not flow control](#resolution-15-pausepane-role-shift--advisory-signal-not-flow-control)
   - [Resolution 16: Ring invariant — at least one I-frame always present](#resolution-16-ring-invariant--at-least-one-i-frame-always-present)
4. [Preedit Delivery Model](#preedit-delivery-model)
   - [Resolution 17: Preedit-only frames bypass the ring — per-client delivery](#resolution-17-preedit-only-frames-bypass-the-ring--per-client-delivery)
   - [Resolution 18: Ring contains only grid-state frames](#resolution-18-ring-contains-only-grid-state-frames)
   - [Resolution 19: frame_sequence incremented only for grid-state frames](#resolution-19-frame_sequence-incremented-only-for-grid-state-frames)
   - [Resolution 20: Dedicated preedit messages remain outside the ring](#resolution-20-dedicated-preedit-messages-remain-outside-the-ring)
5. [FlowControlConfig Changes](#flowcontrolconfig-changes)
   - [Resolution 21: Retire `max_queue_bytes` and `max_queue_frames`](#resolution-21-retire-max_queue_bytes-and-max_queue_frames)
6. [Wire Protocol Changes Summary](#wire-protocol-changes-summary)
7. [Spec Documents Requiring Changes](#spec-documents-requiring-changes)
8. [Evidence Base](#evidence-base)
9. [Key Design Properties](#key-design-properties)

---

## Issue 24: P-Frame Diff Base

### Resolution 1: Option B — cumulative diff from most recent I-frame

**Consensus (5/5).** Every P-frame's dirty rows are cumulative since the most recent I-frame. Any P-frame is independently decodable given only the current I-frame. There is no sequential dependency chain between P-frames.

```
I₀ → P₁ → P₂ → P₃ → I₁ → P₄ → ...
 ↑    ↑    ↑    ↑
 └────┴────┴────┘  all reference I₀
```

A client needs only: latest I-frame + latest P-frame. It MAY skip any number of intermediate P-frames freely.

**Rationale — four independent arguments converged on the same conclusion:**

1. **Coalescing tier compatibility** (protocol-architect): The protocol's 4-tier adaptive coalescing assigns per-client tiers. Different clients skip different P-frames. Under Option A (sequential chain), the server must recompute custom diffs for clients that skipped frames — reintroducing the per-client O(N) dirty bitmap problem that Issues 22-23 aim to eliminate. Under Option B, any client applies the latest P to the latest I with zero per-client computation.

2. **Wide-character atomicity** (cjk-specialist): CJK wide characters are atomic 2-cell units (`wide=1` + `spacer_tail`). Option A's sequential chain creates a fragility window where coalescing-induced frame skipping could leave surrounding context (cursor position, adjacent cells) inconsistent on a row containing a wide character. Option B's cumulative dirty set always contains complete row state since the I-frame, preventing this class of rendering artifact.

3. **Preedit self-containment alignment** (ime-expert): Preedit-bypass FrameUpdates are already independently decodable (self-contained preedit JSON, no sequential dependency). Option B extends this self-containment principle to the grid state layer. Option A would create an asymmetry — two different consistency models within the same frame type.

4. **Implementation complexity** (system-sw-engineer): Option B requires one cumulative dirty bitmap per pane (O(1) maintenance). Option A requires per-client catch-up diff computation when clients skip frames (O(N) maintenance). The bandwidth "savings" of Option A (smaller individual P-frames) are illusory — worst-case Option B P-frame equals I-frame size, which means all rows changed and the data must be sent regardless.

**P-frame size growth is bounded**: Within a 1-second keyframe interval, the cumulative dirty set grows as rows are modified. For typical interactive use (1-3 rows per keystroke), P-frames remain a small fraction of I-frame size. Worst case (all rows dirty) = I-frame size = the data must be sent anyway. No wasted bandwidth.

**Owner constraint satisfied**: The owner left this decision to the design team. Option B is the team's unanimous recommendation.

---

## Issue 23: Periodic Keyframes (I/P-Frame Model)

### Resolution 2: Adopt I/P-frame model with periodic keyframes

**Consensus (5/5).** Adopt an I-frame/P-frame model with periodic keyframes, analogous to video codec keyframes.

| Concept | Video codec | Terminal protocol |
|---------|-------------|-------------------|
| Keyframe (I-frame) | Full image, self-contained | `frame_type=2`: all rows, all CellData |
| Delta (P-frame) | Diff from reference | `frame_type=1`: cumulative dirty rows since last I-frame |
| Keyframe interval | e.g., every 1 second | Configurable (default 1 second) |
| Seek/recovery | Jump to nearest I-frame | Client skips to latest I-frame in ring |

**What this eliminates:**

| Current model (v0.6) | I/P-frame + ring model (v0.7) |
|----------------------|-------------------------------|
| N per-client dirty bitmaps per pane | 1 per-pane dirty bitmap |
| O(N) frame serialization per interval | O(1) per interval |
| O(N) memcpy per frame | O(1) ring write |
| Explicit discard-and-resync codepath | "Skip to I-frame" (normal codepath) |
| Silent state drift, no recovery | Auto-heals every keyframe interval |

**Cost**: ~116KB/s per pane at 1 keyframe/s (120x40 CJK worst case). 4 panes = ~464KB/s total. Negligible on local Unix socket. <0.5MB/s on SSH.

### Resolution 3: 1-second default keyframe interval

**Consensus (5/5).** Default keyframe interval is 1 second, configurable via server configuration (not protocol-negotiated).

**Rationale**:
- Korean composition typically takes 0.5-2 seconds per syllable. A 1-second interval ensures composition-related rendering corruption heals within one composition cycle (cjk-specialist).
- At ~116KB/s per pane worst case, bandwidth cost is negligible on Unix socket and acceptable on SSH (ime-expert, system-sw-engineer).
- ghostty's 100,000-frame periodic reset (~12 minutes at 120Hz) is for memory management, not state sync. Our 1-second keyframe serves a different purpose (multi-client state synchronization) and the more aggressive interval is justified.

**Configurable range**: 0.5-5 seconds. Shorter intervals (0.5s) improve recovery speed on local connections. Longer intervals (5s) reduce bandwidth on slow SSH links.

### Resolution 4: Wire format — `frame_type` field replaces `dirty`

**Consensus (5/5).** The `dirty` field at binary frame header offset 32 is renamed to `frame_type` with 4 values.

```
Offset  Size  Field         Description
------  ----  -----         -----------
32       1    frame_type    Frame type (replaces 'dirty', same byte position)
33       1    screen        0=primary, 1=alternate (UNCHANGED)
```

`frame_type` values:

| Value | Name | Description |
|-------|------|-------------|
| 0 | P-frame, metadata-only | No DirtyRows section (section_flags bit 4 unset). JSON metadata only (cursor, preedit, modes). Equivalent to the former `dirty=0`. |
| 1 | P-frame, partial | DirtyRows section present. Cumulative dirty rows since most recent I-frame. Equivalent to former `dirty=1` with cumulative semantics. |
| 2 | I-frame | All rows present. Self-contained keyframe. `num_dirty_rows` MUST equal the pane's total row count. Equivalent to former `dirty=2`. |
| 3 | I-frame, unchanged | All rows present. Self-contained. Entire payload (CellData + JSON metadata) identical to previous I-frame. Advisory hint — see Resolution 6. |

**Rationale for rename**: The field's semantics shifted from "per-client dirty extent" (v0.6) to "per-pane frame type in the I/P-frame model" (v0.7). The rename makes this semantic break explicit and prevents implementers from assuming the old per-client dirty tracking semantics. Code that dispatches on this field reads `switch (frame_type)` with values mapping directly to the I/P-frame conceptual model.

**Backward wire compatibility**: `frame_type` values 1 and 2 are byte-compatible with old `dirty=1` and `dirty=2`. Value 0 is byte-compatible with old `dirty=0`. Value 3 is new.

### Resolution 5: Keyframe self-containment rule

**Consensus (5/5).** This satisfies the owner's non-negotiable binding constraint.

> **Normative**: I-frames (`frame_type=2` or `frame_type=3`) MUST always carry full CellData for ALL rows of the pane. A client that receives an I-frame has a complete, self-contained terminal state. I-frames MUST never reference a previous frame in place of data. The self-containment property is the defining characteristic of a keyframe.

**CJK validation** (cjk-specialist): Self-containment guarantees that wide characters are always complete in I-frames — both the `wide=1` cell and its `spacer_tail` are always present. No dangling spacer_tail references, no missing wide-cell partners.

**IME validation** (ime-expert): Self-containment guarantees that I-frames carry complete preedit overlay state in the JSON metadata blob when composition is active. A client recovering via I-frame seek has both the grid state (CellData) and the preedit rendering data (text, cursor position, display_width) in a single frame. PreeditSync (0x0403) provides additional composition metadata (composition_state, preedit_session_id, preedit_owner) sent after the I-frame.

### Resolution 6: `unchanged` advisory hint — strict server-side rule

**Consensus (5/5).** This satisfies the owner's advisory hint constraint with a strict server-side enforcement rule.

> **Normative**: The server MUST set `frame_type=3` (I-frame, unchanged) only when the entire frame payload — CellData AND JSON metadata — is byte-identical to the most recent I-frame (`frame_type=2` or `frame_type=3`) for this pane. If any field has changed — including cursor position, preedit state, terminal modes, colors, or dimensions — the server MUST use `frame_type=2` (normal I-frame).

> **Normative**: Caught-up clients receiving `frame_type=3` MAY skip the entire frame without processing. Clients that arrived at this frame by seeking (ring buffer skip, ContinuePane recovery, initial attach) MUST ignore the unchanged hint and process the frame as `frame_type=2`.

**Rationale for strict rule** (ime-expert, protocol-architect): A relaxed rule (unchanged = CellData identical, metadata may differ) would require every client to correctly distinguish "skip cell rendering" from "skip JSON parsing." A buggy client that skips the entire frame would miss preedit updates. The strict rule (unchanged = entire payload identical) eliminates this edge case. One enforcement point (server), one hash comparison per keyframe. The cost is that `frame_type=3` fires rarely (only during true terminal idle), but this is acceptable — the hint was always a minor optimization.

### Resolution 7: No `keyframe_sequence` field — implicit reference rule

**Consensus (5/5).** No explicit `keyframe_sequence` field in the binary frame header.

> **Normative**: A P-frame (`frame_type=0` or `frame_type=1`) always references the most recent I-frame (`frame_type=2` or `frame_type=3`) that the client has received. The client MUST track the `frame_sequence` of the most recently received I-frame as local state. All subsequent P-frames are applied against this I-frame's state. When the client receives a new I-frame, it replaces its reference and discards the previous I-frame state.

**Rationale** (principal-architect, cjk-specialist): Under Option B + reliable transport + ring buffer cursor management, there is no scenario where a client receives a P-frame without having already received its reference I-frame. An explicit field would add 8 bytes per P-frame for information the client already knows. Scenarios examined: normal operation, coalescing skip, ring recovery, screen switch, reconnect — all derive the reference I-frame from the stream.

### Resolution 8: No capability negotiation for I/P-frame model

**Consensus (5/5).** The I/P-frame model requires no new capability flag.

**Rationale** (protocol-architect): The model is a transparent server-side optimization. P-frames (`frame_type=1`) are wire-compatible with current `dirty=partial` FrameUpdates. I-frames (`frame_type=2`) are wire-compatible with current `dirty=full` FrameUpdates. The only new concept (`frame_type=3`, unchanged hint) is safely ignored by older clients — treating it as a normal I-frame (conservative behavior) is correct.

### Resolution 9: No client-to-server keyframe acknowledgment

**Consensus (5/5).** The server does not need to know which I-frame the client holds. The server writes frames unconditionally to the ring. The only per-client state is the read cursor position. If the cursor falls behind the ring tail, the server advances it to the latest I-frame. No acknowledgment protocol, no sequence tracking, no round-trip.

### Resolution 10: Per-pane dirty bitmap replaces per-client dirty bitmaps

**Consensus (5/5).** The v0.6 normative note in doc 04 stating "The server maintains independent dirty bitmaps per (client, pane) pair" is replaced.

> **Normative**: The server maintains a single dirty bitmap per pane. Frame data (I-frames and P-frames) is serialized once per pane per frame interval. All clients viewing the same pane receive identical frame data from the shared ring buffer. Clients at different coalescing tiers receive different subsets of frames from the same sequence, but each frame's content is identical regardless of which client receives it.

**CJK validation** (cjk-specialist): A single per-pane bitmap eliminates the class of bugs where wide characters span the boundary between "dirty for client A" and "not dirty for client B." Row-level dirty tracking (matching ghostty's `Row.dirty` boolean) is sufficient to guarantee wide-char atomicity — a wide character always occupies cells within a single row.

---

## Issue 22: Shared Ring Buffer

### Resolution 11: Adopt shared per-pane ring buffer

**Consensus (5/5).** Replace per-client output buffers with a shared per-pane ring buffer. The server serializes each frame once into the ring. Per-client read cursors track delivery position.

**Memory comparison** (100 clients, 4 panes):

| Metric | Per-client buffers (v0.6) | Shared ring (v0.7) |
|--------|--------------------------|---------------------|
| Total memory | 200 MB (100 x 4 x 512KB) | 8 MB (4 x 2MB) + cursors |
| memcpy per frame | 100 copies | 1 ring write |
| Per-client state | 512KB buffer | 12 bytes (cursor + partial offset) |

**Implementation model** (system-sw-engineer):
- Variable-length byte-level ring (not fixed-slot) — frames vary from ~100 bytes to ~116KB.
- Ring overwrites unconditionally. No drain coordination (unlike tmux's control mode which drains when the slowest client catches up). No "convoy effect" from slow clients.
- Socket write path: `writev()` directly from ring memory — zero-copy.
- EAGAIN handling: cursor stays at current position, re-arm epoll/kqueue. No special recovery.
- Concurrency: pane_mutex -> ring_lock ordering. Socket writers do not need pane_mutex — they read from the ring only. This decouples the socket write path from the pane mutex.

**Protocol-visible behavior**: Unchanged. Same frame format, same FrameUpdate message type, same client processing.

### Resolution 12: 2 MB default ring size per pane

**Consensus (5/5).** Default ring buffer size is 2 MB per pane, configurable via server configuration (not protocol-negotiated).

**Sizing analysis** (system-sw-engineer, 120x40 CJK worst case, 1s keyframe interval, 60fps Active tier):

| Component | Size |
|-----------|------|
| 1 I-frame | ~116 KB |
| 60 P-frames (typical) | ~10-30 KB each = ~600KB-1.8MB |
| Minimum ring (2 I-frames) | ~232 KB |
| Typical interactive ring usage | ~1.3 MB |
| Worst case (sustained full-screen rewrite) | ~7 MB |

2 MB covers typical interactive use with headroom. For heavy output (sustained full-screen rewrite), the ring wraps and slow clients skip to the latest I-frame — correct behavior.

### Resolution 13: Retire 512KB per-client buffer limit — ring size is single resync knob

**Consensus (5/5).** The 512KB per-(client, pane) buffer limit from v0.6 Resolution 13 is **retired**. Ring size is the single resync trigger.

**Resync trigger**: The ring overwrites the client's cursor position (write head advances past the read cursor). The server advances the cursor to the latest I-frame in the ring.

**Rationale** (system-sw-engineer): The 512KB limit was designed for per-client buffer memory allocation. In the ring model, per-client memory is just a cursor (12 bytes). The resource being managed is ring space, and the ring size already defines the maximum lag. A separate delivery lag cap would be a second knob protecting no additional resource. Under Option B, "gradual catch-up through stale P-frames" is actually worse than jumping to the latest I-frame — the client spends time and bandwidth reading stale data when it could show current state immediately.

**Supersedes**: v0.6 Resolution 13 ("512KB per (client, pane)").

### Resolution 14: Recovery codepath unification — advance cursor to latest I-frame

**Consensus (5/5).** Three distinct recovery procedures in the current spec collapse into a single operation: **advance client cursor to latest I-frame in the ring.**

| Recovery trigger | v0.6 procedure | v0.7 procedure |
|-----------------|----------------|----------------|
| ContinuePane (after PausePane) | Discard buffered frames, send dirty=full snapshot | Advance cursor to latest I-frame |
| Buffer overflow | Discard all buffered frames, send dirty=full resync | Advance cursor to latest I-frame |
| Stale recovery | LayoutChanged + dirty=full FrameUpdate + PreeditSync | Advance cursor to latest I-frame |

The I-frame IS the dirty=full FrameUpdate — same data, same wire format, same client processing. The only variation is what additional messages accompany recovery:

- **ContinuePane**: Advance cursor. No additional messages needed.
- **Stale recovery**: Advance cursor + enqueue LayoutChanged (if layout changed during stale period) and PreeditSync (if preedit active on any pane) into the direct message queue. Per socket write priority (Resolution 17), these context messages arrive BEFORE the I-frame from the ring.

**Supersedes**: v0.6 Resolutions 14 and 15 (discard-and-resync pattern and stale recovery resync procedure).

### Resolution 15: PausePane role shift — advisory signal, not flow control

**Consensus (5/5).** In the ring model, PausePane no longer stops frame production. The ring writes unconditionally for all clients.

PausePane becomes an **advisory signal** for the health escalation state machine:

- PausePane → resize exclusion (T=5s) → stale (T=60s/120s) → eviction (T=300s)
- The server keeps writing to the ring regardless of which clients are paused.
- PausePane tells the client "you are falling behind, expect an I-frame resync."

**PausePane trigger**: Client cursor falls behind ring write head by >90% of ring capacity.

**What PausePane still does**:
- Triggers the health escalation timeline (Resolutions 7-12 from v0.6 design resolutions).
- Excludes the client from resize calculation (v0.6 Resolution 3).

**What PausePane no longer does**:
- Does NOT stop frame production for the pane (ring writes unconditionally).
- Does NOT allocate or manage a per-client output buffer (buffer is retired).

**Preedit delivery during PausePane**: Preedit-only frames are always delivered via the per-client bypass buffer (Resolution 17), independent of ring cursor state. No special PausePane exception needed — the bypass path applies to all clients at all times.

### Resolution 16: Ring invariant — at least one I-frame always present

**Consensus (5/5).** The ring MUST always contain at least one complete I-frame for each pane.

> **Normative**: When the ring write head is about to overwrite the only remaining I-frame in the ring, the server MUST first write a new I-frame before the overwrite proceeds. This ensures that any client seeking to the latest I-frame (recovery, attach, ContinuePane) always finds one.

---

## Preedit Delivery Model

### Resolution 17: Preedit-only frames bypass the ring — per-client delivery

**Consensus (5/5).** Preedit-only frames (`frame_type=0` with preedit state change) are delivered directly to each client via a per-client latest-wins priority buffer. They are NOT written to the shared ring buffer. This applies to ALL clients regardless of health state, not just paused clients.

This satisfies v0.6 Resolution 16: "Preedit-only FrameUpdates MUST be delivered to clients in ANY health state, including stale."

**Rationale** (ime-expert, cjk-specialist, system-sw-engineer): A behind client's ring cursor creates position-dependent latency for preedit-only frames. A Bulk-tier client with unread frames queued ahead in the ring must process those frames before reaching a preedit frame, violating the <33ms preedit latency target. Delivering preedit-only frames outside the ring eliminates this latency source entirely.

**Per-client preedit bypass buffer** (system-sw-engineer):
- Holds at most 1 preedit-bypass frame (~128 bytes).
- Latest-wins: any new preedit frame unconditionally replaces whatever is in the buffer.
- Drained with highest priority on socket-writable events (before direct message queue and ring data).

**Bypass condition**: `frame_type=0 AND preedit JSON present AND (preedit.active changed OR preedit.text changed)`. Cursor-only metadata updates without preedit changes go into the ring as normal `frame_type=0` entries — they are not latency-critical.

**O(N) cost is negligible**: At ~110 bytes per frame at typing speed (~15/s), preedit bypass costs 110 * 15 * N = 1650N bytes/s. Even with 100 clients: ~165KB/s.

**Socket write priority order** (system-sw-engineer):
1. Preedit-bypass buffer (~110 bytes, highest priority)
2. Direct message queue (LayoutChanged, PreeditSync, etc.)
3. Ring buffer frames (via `writev()` zero-copy from ring memory)

### Resolution 18: Ring contains only grid-state frames and non-preedit metadata

**Consensus (5/5).** The shared ring buffer contains:
- I-frames (`frame_type=2`, `frame_type=3`): all rows, self-contained keyframes
- P-frames with dirty rows (`frame_type=1`): cumulative dirty rows since last I-frame
- Metadata-only frames without preedit changes (`frame_type=0`, cursor-only moves, mode changes): non-latency-critical metadata updates

The ring does NOT contain preedit-only frames (those go through the per-client bypass buffer per Resolution 17).

### Resolution 19: frame_sequence tracks ring frames only

**Consensus (5/5).** The per-pane `frame_sequence` counter is incremented for every frame written to the ring buffer. Preedit-only frames delivered via the per-client bypass buffer (Resolution 17) do NOT increment `frame_sequence` because they are not in the ring.

**Rationale** (ime-expert): `frame_sequence` is incremented each time the server writes a frame to the ring buffer. It tracks the ring's ordered frame sequence that clients consume via their ring cursors. Preedit-only frames are outside this stream and do not participate in the I-frame reference mechanism (Resolution 7).

**Practical rule**: All ring frames (`frame_type=0` cursor-only in ring, `frame_type=1` P-frames, `frame_type=2` I-frames, `frame_type=3` I-frames unchanged) increment `frame_sequence`. Only preedit-bypass frames (delivered outside the ring) are excluded.

### Resolution 20: Dedicated preedit messages remain outside the ring

**Consensus (5/5).** The dedicated preedit protocol messages (0x0400-0x0405: PreeditStart, PreeditUpdate, PreeditEnd, PreeditSync, InputMethodSwitch, InputMethodAck) remain entirely outside the ring buffer. They are separate message types sent directly per-client.

PreeditSync is enqueued in the direct message queue (priority 2) during resync/recovery. Under the socket write priority model (Resolution 17), the direct queue drains BEFORE ring data (priority 3), so PreeditSync arrives BEFORE the I-frame. The client processes PreeditSync first (records composition metadata: composition_state, preedit_session_id, preedit_owner), then processes the I-frame (renders grid + preedit overlay with full context). This follows the "context before content" principle.

---

## FlowControlConfig Changes

### Resolution 21: Retire `max_queue_bytes` and `max_queue_frames`

**Consensus (5/5).** Remove `max_queue_bytes` and `max_queue_frames` from FlowControlConfig. They are replaced by the ring buffer model.

**Retained fields**:

| Field | Purpose |
|-------|---------|
| `max_queue_age_ms` | Time-based staleness trigger (orthogonal to byte-based lag) |
| `auto_continue` | Auto-resync after PausePane |

Plus the health escalation timeouts from v0.6 design resolutions (`stale_timeout_ms`, `eviction_timeout_ms`, `resize_exclusion_timeout_ms`), which are time-based and orthogonal to the ring model.

**Ring size**: Server configuration (daemon config file or startup flag), not protocol-negotiated. Clients do not see or influence it. Default: 2 MB per pane.

**Supersedes**: `max_queue_bytes` and `max_queue_frames` fields in FlowControlConfig (v0.6 doc 06).

---

## Wire Protocol Changes Summary

### Binary Frame Header Change

```
v0.6:
  Offset 32: dirty (u8)      0=none, 1=partial, 2=full
  Offset 33: screen (u8)     0=primary, 1=alternate

v0.7:
  Offset 32: frame_type (u8) 0=P-metadata, 1=P-partial, 2=I-frame, 3=I-unchanged
  Offset 33: screen (u8)     0=primary, 1=alternate (UNCHANGED)
```

### Normative Notes Added/Changed

| Note | Location | Change |
|------|----------|--------|
| Per-client dirty tracking | Doc 04, Section 4.1 | Replaced: per-pane dirty bitmap, single serialization, shared ring |
| P-frame cumulative semantics | Doc 04, Section 4.1 | Added: dirty rows cumulative since last I-frame, clients MAY skip intermediate P-frames |
| I-frame self-containment | Doc 04, Section 4.1 | Added: all rows present, never references previous frame |
| `frame_type=3` unchanged rule | Doc 04, Section 4.1 | Added: entire payload identical, caught-up clients MAY skip, seeked clients MUST process |
| Implicit I-frame reference | Doc 04, Section 4.1 | Added: client tracks last I-frame frame_sequence locally |
| frame_sequence scope | Doc 04, Section 4.1 | Updated: incremented only for grid-state frames (section_flags bit 4 set) |

### FlowControlConfig Field Changes

| Field | v0.6 | v0.7 |
|-------|------|------|
| `max_queue_bytes` | 512KB per (client, pane) | **Retired** — replaced by ring size |
| `max_queue_frames` | Per-client frame count limit | **Retired** — frame count meaningless in ring model |
| `max_queue_age_ms` | Time-based staleness | Retained, unchanged |
| `auto_continue` | Auto-resync after PausePane | Retained, unchanged |

### Recovery Procedure Changes

| Trigger | v0.6 | v0.7 |
|---------|------|------|
| ContinuePane | Discard buffer, send dirty=full | Advance cursor to latest I-frame |
| Buffer overflow | Discard buffer, send dirty=full resync | Advance cursor to latest I-frame |
| Stale recovery | LayoutChanged + dirty=full + PreeditSync | Advance cursor + LayoutChanged + PreeditSync |

---

## Spec Documents Requiring Changes

| Document | Changes Required |
|----------|-----------------|
| **Doc 04** (Input/RenderState) | Replace `dirty` field with `frame_type` (4 values). Replace per-client dirty bitmap normative note with per-pane bitmap. Add I/P-frame cumulative semantics. Add keyframe self-containment rule. Add `unchanged` hint normative note. Update `frame_sequence` scope (grid-state frames only). |
| **Doc 06** (Flow Control) | Replace per-client output buffer model with shared ring buffer. Retire 512KB buffer limit. Add keyframe interval configuration. Update PausePane semantics (advisory signal). Update discard-and-resync to "advance cursor to latest I-frame." Collapse three recovery procedures into one. Update FlowControlConfig fields (retire max_queue_bytes, max_queue_frames). Add ring invariant (at least one I-frame). Add preedit PausePane bypass. Add socket write priority order. |
| **Doc 01** (Protocol Overview) | Update architecture overview to mention I/P-frame model and shared ring buffer. |
| **Doc 03** (Session/Pane Mgmt) | Update multi-client output model references. |

---

## Evidence Base

Decisions were informed by three research reports:

| Report | Key findings relevant to these resolutions |
|--------|---------------------------------------------|
| `research/01-tmux-multi-client-frame-delivery.md` | Control mode uses shared buffer with per-client offsets — architecturally identical to shared ring (Issue 22). TTY mode is inherently O(N). Recovery is always full redraw from authoritative state (no keyframe concept). PANE_REDRAW is a boolean, not a bitmap — fails closed to full redraw. |
| `research/02-zellij-multi-client-frame-delivery.md` | One authoritative grid per terminal pane, cloned N times at output layer (O(N), acknowledged suboptimal with a TODO comment). Bounded channel (5000) with disconnect on overflow — no render coalescing, no frame dropping. No periodic keyframes. `set_force_render()` is the closest analogue to our I-frame. |
| `research/03-ghostty-dirty-tracking-frame-generation.md` | Single-consumer dirty tracking (row-level boolean in packed u64). RenderState snapshot with three-level dirty (`false`/`partial`/`full`). No inter-frame dependency — each frame independently generated from authoritative state. Periodic full rebuild every 100,000 frames for memory management. Dirty flags consumed (cleared) by single consumer. |

---

## Key Design Properties

| Property | How it is achieved |
|----------|-------------------|
| O(1) frame serialization | One frame per pane per interval, written once to ring |
| O(1) memory per frame | Shared ring buffer, not N per-client copies |
| No per-client state tracking | Option B: any client applies latest P to latest I |
| Auto-healing state drift | Every keyframe (1s) corrects any client-side divergence |
| CJK wide-char safety | Row-level dirty guarantees atomic 2-cell units; cumulative P-frames prevent split updates |
| Preedit latency preserved | Preedit coalescing tier (0ms) + per-client bypass buffer for all clients (Resolution 17) |
| Single recovery codepath | "Advance cursor to latest I-frame" for all three recovery triggers |
| Backward wire compatibility | `frame_type` values 1 and 2 are byte-compatible with old `dirty` values 1 and 2 |
| Three issues form indivisible package | Option B enables shared ring; shared ring enables O(1) serialization; I/P-frame model enables seek points for ring recovery |
