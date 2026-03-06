# Scroll I-frame Delivery Design

**Date**: 2026-03-06
**Raised by**: verification team (V2-04, V3-01) + owner design review
**Severity**: CRITICAL
**Affected docs**: Doc 04 (Input/RenderState) Section 6.1, Doc 06 (Flow Control)
**Status**: open

---

## Problem

Round 2 verification (V2-04) identified that scroll-response I-frames had no specified delivery path. The Round 2 fix team added text to Doc 04 §6.1 routing scroll I-frames through the per-client direct message queue, treating scroll as a per-client viewport operation.

Round 3 verification (V3-01) then found that this fix introduced a new inconsistency: `frame_sequence` is defined as ring-only (Resolution 19), but direct-queue I-frames have no specified `frame_sequence` behavior.

During owner review of Round 3, the owner identified that the V2-04 fix premise was **fundamentally wrong**:

1. **The design is globally singleton.** All clients share the same session state — there are no per-client independent viewports. Per-client scroll positions contradict this core design principle.
2. **Direct message queue is for small control messages** (~110B preedit bypass, LayoutChanged, PreeditSync), not full I-frames (~38KB–116KB).
3. **Viewport-only transmission** means clients receive only visible cells. If one client scrolls, the server produces the scrolled viewport as an I-frame. This is a full-viewport operation, not a delta.

The current text in Doc 04 §6.1 (added by V2-04 fix) is incorrect and must be reverted.

## Analysis

The scroll delivery question intersects several design areas:

- **Ring buffer model**: Scroll I-frames are full I-frames. Writing them to the ring is mechanically correct — they get a `frame_sequence`, all clients consume them, no special path needed.
- **Global singleton implication**: If client A scrolls up 500 lines, ALL clients see the scrolled viewport. This is consistent with the design (like tmux — all clients see the same thing). But it means any client can disrupt other clients' view.
- **ScrollPosition message** (Doc 04 §6.2): Currently sends viewport position metadata. In a global model, this is broadcast to all clients, not per-client.
- **Interaction with ResizeRequest**: Resize is already global (one client resizes, all clients get the new viewport). Scroll follows the same principle.

## Proposed Change

**Revert V2-04 text**: Remove the sentence in Doc 04 §6.1 that reads "This I-frame is delivered via the per-client direct message queue (priority 2), NOT the shared ring buffer, because scroll is a per-client viewport operation — writing it to the shared ring would expose a scrolled viewport to all clients, including those that did not request the scroll."

**Replace with**: Scroll-response I-frames are written to the shared ring buffer like any other I-frame. When one client scrolls, all attached clients receive the scrolled viewport. This is consistent with the globally singleton session model.

## Owner Decision

Per-client independent scroll positions are wrong. The design is globally singleton — all clients share the same viewport state. Scroll I-frames go through the ring buffer like any other I-frame.

## Resolution

{To be resolved in v0.8.}
