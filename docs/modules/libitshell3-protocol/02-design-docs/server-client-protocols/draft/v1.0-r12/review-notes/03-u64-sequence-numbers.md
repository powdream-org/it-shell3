# u64 Sequence Numbers

- **Date**: 2026-03-16
- **Raised by**: owner
- **Severity**: MEDIUM
- **Affected docs**: Doc 01 (header format §3, hex dump appendix), Doc 04
  (header references)
- **Status**: deferred to next revision

---

## Problem

The protocol header uses u32 for the `sequence` field. At 1000 messages/second,
this wraps after ~49 days. Long-lived daemon instances could hit the wrap
boundary.

## Analysis

u64 eliminates the wrap concern entirely (~584 million years at 1000 msg/s). The
cost is +4 bytes per message header (16 -> 20 bytes). At typical terminal
workloads (0-30 msg/s), this overhead is negligible.

This is a header format change, which requires a version byte bump per ADR
00005.

## Proposed Change

Change `sequence` from u32 to u64. Adjust header layout (potentially repurpose
the 2-byte reserved field). Update all header offset references.

See ADR 00015 for the full decision record.

## Owner Decision

Approved. Deferred to next revision for implementation.

## Resolution

Recorded as ADR 00015. To be applied in the next protocol revision cycle.
