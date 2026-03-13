# Resolution Document Text Fixes

**Date**: 2026-03-06
**Raised by**: verification team (V3-03, V3-04)
**Severity**: LOW
**Affected docs**: `design-resolutions/01-i-p-frame-ring-buffer.md`
**Status**: open

---

## Problem

Two minor text issues in the resolution document:

### V3-03 — ToC title mismatch for Resolution 19

ToC entry (line 36) reads: "Resolution 19: frame_sequence incremented only for grid-state frames."
Section heading (line 314) reads: "Resolution 19: frame_sequence tracks ring frames only."

These are textually inconsistent. "Grid-state frames" is also substantively narrower than "ring frames" (would exclude cursor-only frames in the ring).

### V3-04 — "Spec Documents Requiring Changes" table missing Doc 05

The table (lines 396–403) lists only Doc 01, 03, 04, 06. Doc 05 is absent despite having I/P-frame-driven changes:
- `dirty=full` to `frame_type=2` in §7.3/§7.4 (Resolutions 3-4)
- Preedit bypass model references in §8.2/§8.4 (Resolutions 17-19)
- Dedicated preedit messages note in §14 (Resolution 20)

## Analysis

Both are straightforward text corrections with no design implications. The ToC mismatch is a pre-existing issue first noted in Round 1. The missing Doc 05 entry was downgraded from critical to minor since the omission is in the resolution doc's summary table only — the spec docs themselves are correct.

## Proposed Change

1. Change ToC entry to match heading: "Resolution 19: frame_sequence tracks ring frames only."
2. Add Doc 05 entry to the "Spec Documents Requiring Changes" table describing the I/P-frame-related changes.

## Owner Decision

Left to designers for resolution.

## Resolution

{To be resolved in v0.8.}
