# Review Notes: v0.6 Owner Architectural Review

**Date**: 2026-03-05
**Reviewer**: Owner
**Scope**: Multi-client output delivery architecture -- scalability, error tolerance, and frame delivery model
**Context**: Issues raised during owner review of `design-resolutions-resize-health.md` and protocol v0.6 specs. These are new architectural questions, not consistency fixes.

> **Related review notes:**
> - `02-cross-document-consistency.md` -- Team consistency review (17 items: Issues 1-20, unapplied design resolutions)
> - `01-residual-empty-state.md` -- Residual cosmetic issue (1 item)

---

## Issue 21: Client-Side Viewport Clipping Under `latest` Policy

**Severity**: HIGH
**Affected docs**: Doc 03 (Sec 5.1 or Sec 8)
**Category**: Resize policy

### Problem

Under `latest` resize policy, the PTY dimensions are set to the most recently active
client's size. Clients with smaller dimensions than the effective size receive
FrameUpdates containing a larger grid than they can display. The spec does not define
what the smaller client should do.

### Owner Decision

Clients MUST clip to their own viewport dimensions (top-left origin), matching tmux
`latest` policy behavior. Per-client viewports (scroll to see clipped areas) remain
deferred to v2.

### Owner Note: Strong Preference for `latest` as Default

Owner tested zellij extensively -- despite documenting `smallest`, zellij actually
behaves as `latest` in practice. The UX is excellent: the active device always gets
full use of its screen real estate, and switching devices seamlessly resizes. This
confirms that `latest` (already decided in Resolution 1) is the right default.
**This is a strong owner preference -- do not reconsider `smallest` as default
without compelling evidence.** `smallest` remains available as opt-in server
configuration.

### Required Change

Add normative statement to Doc 03 Section 5.1 or Section 8:

> When the effective terminal size exceeds a client's reported dimensions
> (WindowResize cols/rows), the client MUST render only the top-left region
> corresponding to its own dimensions. Content beyond the client's viewport
> boundary is clipped. The protocol does not provide per-client viewport
> scrolling in v1.

---

## Issue 22: Shared Ring Buffer vs Per-Client Output Buffers

**Severity**: HIGH
**Affected docs**: Doc 06 (Sec 2, Server Output Queue Management)
**Category**: Output delivery architecture

### Problem

Resolution 13 prescribes "512KB per (client, pane)" buffer allocation. This implies
per-client copies of identical frame data. Under our shared-focus model, all clients
viewing the same pane receive the same terminal content. Yet the server copies the
same serialized frame N times.

**Quantified impact** (100 clients, 120x40 CJK worst case, ~116KB per frame):

| Metric | Per-client buffers | Shared ring buffer |
|--------|-------------------|-------------------|
| Memory (100 clients, 4 panes) | 200 MB | ~2 MB + 100 cursors |
| memcpy per frame | 11.6 MB (100 copies) | 0 (one write to ring) |
| Bandwidth at 60fps | ~696 MB/s | ~7 MB/s (socket sends only) |
| Cache behavior | Thrashes L2/L3 across 400 locations | Hot data stays in cache |

### Proposed Change

Reframe Resolution 13 as a **delivery lag cap** ("a client may fall at most 512KB
behind the current frame sequence") rather than a per-client buffer allocation.

**Recommended implementation pattern**: Shared per-pane ring buffer with per-client
read cursors. Server serializes each frame once into the ring. Each client's socket
write reads directly from the ring at its cursor position. When a cursor falls behind
the ring tail, discard-and-resync (advance to latest keyframe per Issue 23).

All protocol-visible behavior is preserved: same backpressure thresholds, same stale
triggers, same discard-and-resync semantics.

### Status

Proposed by owner. Left to design team for adoption decision.

---

## Issue 23: Periodic Keyframes (I-frame/P-frame Model)

**Severity**: CRITICAL
**Affected docs**: Doc 04 (Sec 4, FrameUpdate dirty tracking), Doc 06 (Sec 2, output queue)
**Category**: Output delivery architecture
**Dependencies**: Issue 22 (shared ring buffer)

### Problem

The per-client dirty bitmap model has three interconnected problems at scale:

**(a) Diff calculation cost.** Server maintains per-client dirty bitmaps per pane.
With N clients, every terminal state change requires N bitmap updates. Frame generation
requires N separate serializations because dirty sets diverge across coalescing tiers.
This is O(N) bitmap maintenance + O(N) frame serialization per output event.

**(b) No error tolerance.** The protocol relies on reliable transport (TCP/Unix socket),
but client-side state can silently diverge from server state through application bugs
in delta application, race conditions, or coalescing artifacts dropping intermediate
states. Current design has no detection mechanism and no auto-recovery -- corruption
persists indefinitely until an explicit trigger (resize, reattach, stale recovery).
With many active clients, silent divergence on any one client is undetectable by
either side.

**(c) Catch-up complexity.** A client behind by K frames needs either K coalesced
deltas (complex union of K dirty sets -- effectively a per-client operation) or a full
resync (heavyweight, requires a special codepath distinct from normal frame delivery).

### Proposed Change

Adopt an I-frame/P-frame model with periodic keyframes, analogous to MPEG video codecs:

| Concept | Video codec | Terminal protocol |
|---------|-------------|-------------------|
| Keyframe (I-frame) | Full image, self-contained | dirty=full FrameUpdate: all rows, all CellData |
| Delta (P-frame) | Diff from reference | dirty=partial FrameUpdate: only changed rows |
| Keyframe interval | e.g., every 1 second | Configurable (suggested 1-2 seconds) |
| Seek/recovery | Jump to nearest I-frame | Client skips to latest keyframe in ring |

Combined with Issue 22's shared ring buffer: server writes one frame (I or P) to the
ring. Clients read from the ring at their cursor. Clients behind by >= 1 keyframe
interval skip to the latest keyframe. Discard-and-resync becomes simply "advance cursor
to latest keyframe" -- same codepath as normal delivery, no special case.

**What this eliminates:**

| Current model | Keyframe + ring model |
|--------------|----------------------|
| N per-client dirty bitmaps per pane | 1 per-pane dirty bitmap |
| O(N) frame serialization per interval | O(1) per interval |
| O(N) memcpy per frame | O(1) ring write |
| Explicit discard-and-resync codepath | "Skip to keyframe" (normal codepath) |
| Silent state drift, no recovery | Auto-heals every keyframe interval |

**Cost**: ~116KB/s per pane at 1 keyframe/s. 4 panes = ~464KB/s total. Negligible on
local Unix socket. <0.5MB/s on SSH.

### Owner Decisions (binding)

1. **Keyframe self-containment**: Keyframes MUST always carry full CellData. Never a
   reference to a previous frame in place of data. A client that just skipped from a
   distant cursor has no previous state to reference. Self-containment is the defining
   property of a keyframe. **Non-negotiable.**

2. **Advisory `unchanged` hint**: Keyframes MAY include an advisory `unchanged` boolean
   (default false). When true, it signals content is identical to the previous keyframe.
   Caught-up clients can use this hint to skip re-rendering. Clients that jumped to this
   keyframe MUST ignore the hint and render from the full data. The hint is purely a
   client-side render optimization -- safe to ignore, safe to use.

### Status

Proposed by owner with two binding constraints (above). Adoption decision left to
design team.

---

## Issue 24: P-frame Diff Base (Open Design Question)

**Severity**: CRITICAL
**Affected docs**: Doc 04 (FrameUpdate), Doc 06 (flow control)
**Category**: Output delivery architecture
**Dependencies**: Issues 22, 23

### Problem

If Issues 22-23 adopt an I-frame/P-frame model, the team must decide the P-frame's
reference point. This is architecturally fundamental -- it determines whether the
shared ring buffer (Issue 22) can truly eliminate per-client state tracking or merely
defer it.

### Option A: P-frame = diff from previous frame (P or I)

```
I₀ → P₁ → P₂ → P₃ → I₁ → P₄ → ...
      ↑         ↑
      depends   depends
      on I₀     on P₂
```

- Sequential dependency chain. To decode P₃, client needs I₀ + P₁ + P₂ + P₃ applied
  in order.
- **Pro**: Smallest individual P-frames (only the true delta between consecutive frames).
- **Con**: Skipping any P invalidates all subsequent P-frames until the next I.
  Coalescing (clients at different tiers skip different P-frames) re-introduces
  per-client diff computation -- defeating the shared ring buffer model.

### Option B: P-frame = diff from the most recent I-frame (cumulative)

```
I₀ → P₁ → P₂ → P₃ → I₁ → P₄ → ...
 ↑    ↑    ↑    ↑
 └────┴────┴────┘  all reference I₀
```

- Every P independently decodable given only the current I-frame. No chain.
- **Pro**: Client needs only latest I + latest P. Skip any number of intermediate
  P-frames freely. No per-client state tracking. Coalescing is trivial.
- **Con**: P-frames grow within a keyframe interval (cumulative dirty set expands).
  Bounded by terminal row count -- worst case P = I size (all rows changed, data
  must be sent anyway).

### Trade-off Summary

| Criterion | Option A (prev frame) | Option B (prev I-frame) |
|-----------|----------------------|------------------------|
| P-frame size | Minimal | Grows within interval (bounded) |
| Sequential dependency | Yes (chain) | No (independent) |
| Skip intermediate frames | Impossible without per-client tracking | Free |
| Shared ring compatibility | Partial (re-introduces per-client diffs) | Full (no per-client state) |
| Coalescing interaction | Complex (custom diffs per tier) | Trivial (latest P works for any client) |
| Error cascade | One bad P corrupts all subsequent | Each P self-corrects |

### Owner Position

**Left to designers for resolution.** Owner did NOT pre-decide. Both options presented
with full trade-off analysis. The team should resolve this before finalizing Issues
22-23, as Option A potentially re-introduces the per-client state tracking that those
issues aim to eliminate.

---

## Summary

| Issue | Severity | Category | Status |
|-------|----------|----------|--------|
| 21 | HIGH | Resize/viewport | **Owner decided** -- clip to top-left |
| 22 | HIGH | Output delivery | Proposed, left to team |
| 23 | CRITICAL | Output delivery | Proposed with 2 binding constraints |
| 24 | CRITICAL | Output delivery | Open question, left to team |

Issues 22-24 are tightly coupled and should be discussed together.
Recommended resolution order: Issue 24 first (foundational), then 23, then 22.
