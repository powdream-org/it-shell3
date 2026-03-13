# Remove frame_type=2 (I-unchanged)

**Date**: 2026-03-10
**Raised by**: owner
**Severity**: MEDIUM
**Affected docs**: Doc 04 (Sections 4.1, 7.3, 8.3), Doc 01 (Section 11.3), Doc 02 (attach sequences)
**Status**: open

---

## Problem

`frame_type=2` (I-unchanged) is a full I-frame (~6-33KB) that is byte-identical to the previous I-frame. Caught-up clients MAY skip processing, but still receive the bytes. This adds complexity (3 frame types instead of 2) without clear benefit.

## Analysis

All terminal state changes flow through RenderState dirtying — there are no bypass paths. This means the decision between frame_type=1 and frame_type=2 reduces to a single dirty boolean per pane:

- **Dirty** → emit I-frame (frame_type=1)
- **Not dirty** → the last I-frame in the per-pane ring buffer is still valid; don't send anything

When the pane is idle, no new frames are written, so the ring cursor doesn't advance. The last I-frame stays in the ring indefinitely. New or recovering clients seek to it and get correct state. There is no need to write a duplicate entry.

Eliminating frame_type=2:

- Saves ~6-33 KB/s bandwidth per idle pane (currently sent every keyframe interval)
- Removes a duplicate ring buffer entry per idle keyframe tick
- Simplifies frame_type from 3 values to 2 (KISS)
- Removes the byte-comparison logic the server must perform each keyframe tick

## Proposed Change

1. Remove `frame_type=2` from the frame_type enum. Values become: 0=P-frame, 1=I-frame.
2. When the I-frame timer fires and the pane is not dirty, do nothing (idle suppression).
3. Remove all `frame_type=2` references, client processing rules (Section 7.3), and the byte-comparison normative text (Section 7.3 line 999).
4. Seeking clients no longer need the "MUST ignore unchanged hint" rule — every I-frame in the ring is frame_type=1.

## Owner Decision

Remove for KISS. The `frame_type` field name is kept (not renamed to `dirty`) for extensibility.

## Resolution

