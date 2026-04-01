# 00015. u64 Sequence Numbers

- Date: 2026-03-16
- Status: Accepted

## Context

The protocol header uses a u32 `sequence` field (offset 12, 4 bytes) for
monotonic message numbering. At 1000 messages/second, u32 wraps after ~49 days.
While sufficient for most sessions, long-lived daemon instances (weeks/months of
uptime without restart) could theoretically hit the wrap boundary.

Discovered during libitshell3-protocol server-client-protocols v1.0-r12 review —
the item was listed as Proposed in §11.3 Design Decisions Needing Validation.

## Decision

Change the `sequence` field from u32 (4 bytes) to u64 (8 bytes). This eliminates
the wrap concern entirely (~584 million years at 1000 msg/s).

The header grows from 16 bytes to 20 bytes. The 2-byte reserved field could be
repurposed or removed to partially offset this, but the exact header layout
adjustment is deferred to the next revision.

## Consequences

- No sequence number wrap for any practical daemon lifetime.
- Header size increases by 4 bytes (16 -> 20). Every message pays this cost.
- At typical terminal workloads (0-30 msg/s), the 4-byte overhead is negligible
  relative to payload sizes.
- Header format change requires a version byte bump — this is the exact scenario
  the version byte was designed for (ADR 00005).
- All existing header offset references in docs 01, 04 and hex dump examples
  need updating.
