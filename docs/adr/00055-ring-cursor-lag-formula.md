# 00055. Ring Cursor Lag Formula

- Date: 2026-03-26
- Status: Proposed

## Context

The daemon behavior spec (daemon-behavior Doc 03, v1.0-r8, Section 4.4 "Smooth
Degradation Before PausePane") defines three graduated thresholds based on "ring
cursor lag" as a percentage of "ring capacity":

| Ring cursor lag | Action                                              |
| --------------- | --------------------------------------------------- |
| > 50%           | Auto-downgrade coalescing tier (Active -> Bulk)     |
| > 75%           | Force Bulk tier regardless of throughput            |
| > 90%           | Next ContinuePane advances cursor to latest I-frame |

Additionally, Section 3.3 uses ring cursor lag > 90% sustained for
`stale_timeout_ms` as a stale trigger.

However, neither the behavior spec nor the architecture spec
(daemon-architecture Doc 02, v1.0-r8, Section 4.5) formally defines what "ring
cursor lag" means or how to compute the percentage. The architecture spec
defines a `RingCursor` with a `position` field, but the actual implementation
(`ring_buffer.zig`) uses monotonic counters (`RingBuffer.total_written` and
`RingCursor.total_read`) -- not wrapping positions. Without a formula, each
implementor would have to reverse-engineer the intent, risking inconsistent
threshold behavior.

Neither tmux nor zellij has an analogous ring-buffer lag concept. tmux drops
output for slow clients outright; zellij uses per-client channels with
independent backpressure. The graduated degradation model is specific to this
project and requires an unambiguous definition.

## Decision

**Ring cursor lag** for a given client is the number of unread bytes in the ring
buffer for that client, computed from the monotonic counters already present in
the implementation:

```
lag_bytes = total_written - cursor.total_read
```

**Ring cursor lag percentage** is lag expressed as a fraction of ring capacity:

```
lag_percent = lag_bytes * 100 / capacity
```

The thresholds in the behavior spec use strict greater-than (`>`), not
greater-than-or-equal (`>=`). A lag of exactly 50% does not trigger the first
threshold; only values strictly above 50% do.

When `lag_bytes > capacity`, the cursor has been overwritten (the ring has
wrapped past the client's read position). This is already handled by
`isCursorOverwritten()`, which checks exactly this condition. An overwritten
cursor implies lag_percent > 100%, which exceeds all thresholds -- the client
must recover via `seekToLatestIFrame()` before any delivery resumes. The
graduated degradation thresholds (50%, 75%, 90%) are only meaningful when
`lag_bytes <= capacity`.

The computation `total_written - cursor.total_read` is safe from unsigned
underflow because `total_read` can never exceed `total_written` -- the ring
buffer API enforces this via `advanceCursor()` (which asserts
`n <= available(cursor)`) and `seekToLatestIFrame()` (which sets `total_read` to
a valid frame offset within the ring). The defensive
`cursor.total_read > total_written` guard in `isCursorOverwritten()` catches any
hypothetical violation.

Note that `RingBuffer.available()` already computes
`total_written - cursor.total_read` -- this is identical to `lag_bytes`. The lag
percentage computation can reuse `available()` directly:

```zig
const lag_percent = rb.available(&cursor) * 100 / rb.capacity;
```

## Consequences

- The behavior spec's thresholds are now precisely defined. Implementors can
  compute lag percentage with a single subtraction and division using existing
  ring buffer API methods.
- The monotonic counter model avoids the ambiguity that a wrapping `position`
  field would introduce (where distinguishing "fully caught up" from "exactly
  one full ring behind" requires additional state).
- The formula is consistent with the existing `isCursorOverwritten()` and
  `available()` implementations, which already use the same
  `total_written - cursor.total_read` subtraction. No new fields or methods are
  needed.
- The strict greater-than semantics (`>`, not `>=`) mean that a client sitting
  at exactly 50% lag continues at its current coalescing tier. This provides a
  stable boundary -- a client oscillating around 50% does not thrash between
  tiers on every frame.
- The monotonic counters use `usize` (u64 on all current targets). On 32-bit
  platforms, the counters would need explicit `u64` fields to prevent overflow.
