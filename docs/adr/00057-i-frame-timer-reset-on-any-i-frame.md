# 00057. I-Frame Timer Resets on Any I-Frame Production

- Date: 2026-03-26
- Status: Accepted

## Context

The daemon architecture spec (v1.0-r8, 02-state-and-types §4.9) defines an
I-frame scheduling timer that fires at a fixed interval (default 1 second,
configurable 0.5–5 seconds). The spec says the timer is "independent" of
coalescing tiers, but does not define whether the timer resets when an I-frame
is produced by a non-timer source.

I-frames are produced by multiple sources:

| Source                  | When                                                                          |
| ----------------------- | ----------------------------------------------------------------------------- |
| I-frame timer           | Fixed interval, if changes exist since last I-frame                           |
| Client attach           | READY → OPERATING transition (v1.0-r8, 03-policies §12)                       |
| Stale recovery          | Client recovers from stale state (v1.0-r8, 03-policies §3.5)                  |
| ContinuePane            | After PausePane, cursor seeks to latest I-frame (v1.0-r8, 03-policies §4.2)   |
| Resize                  | Window resize produces I-frame for affected panes (v1.0-r8, 03-policies §2.6) |
| Alternate screen switch | Screen transition triggers I-frame (v1.0-r8, 03-policies §8.2)                |

Without a reset rule, the following scenario wastes ring capacity: a client
attaches at T=0.7s, triggering an I-frame. The I-frame timer fires at T=1.0s and
produces another I-frame (only 0.3s later) even though the ring already contains
a valid recovery point.

## Decision

The I-frame timer resets whenever an I-frame is written to the ring, regardless
of which source produced it. The timer tracks "time since last I-frame was
written to the ring," not "time since last timer fire."

Concretely: after any `writeFrame(data, true, seq)` call (where
`is_i_frame =
true`), the I-frame timer deadline is reset to
`now + keyframe_interval`.

The §4.9 "no-op when unchanged" rule still applies: if the timer fires and no
changes exist since the last I-frame (from any source), no frame is written.

## Consequences

- No redundant I-frames. An event-triggered I-frame (attach, recovery, resize)
  pushes the next timer-driven I-frame forward by the full interval. Ring
  capacity is preserved for P-frames.
- The "independence" statement in §4.9 is refined: the timer interval is
  independent of coalescing tiers (it does not speed up or slow down based on
  throughput), but the timer deadline is reset by any I-frame production. These
  are not contradictory — the interval is fixed, the deadline floats.
- The implementation needs a single `last_i_frame_time` timestamp per pane,
  updated on every I-frame write. The timer check becomes:
  `if (now - last_i_frame_time >= keyframe_interval and has_changes)`.
- Bursty I-frame sources (e.g., rapid resize drag producing multiple I-frames)
  do not cause the timer to starve — each I-frame resets the deadline, and the
  timer fires normally once the burst ends.
