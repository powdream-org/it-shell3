# 00040. YAGNI — Remove Compression Header Flag and Capability

- Date: 2026-03-20
- Status: Accepted

## Context

ADR 00014 deferred application-layer compression and reserved two protocol
elements for speculative future use: (1) header flags bit 1 (COMPRESSED flag)
and (2) the `"compression"` capability string with internal bit 0.

These reservations embed a hypothetical future feature into the v1 wire format
before any evidence of need. The COMPRESSED flag has a paradoxical normative
status: senders MUST NOT set it, and receivers SHOULD reject it with
`ERR_PROTOCOL_ERROR`. A flag reserved purely to be rejected adds implementation
burden with zero benefit. The `"compression"` capability string occupies the
lowest-numbered internal bit, shifting all other capabilities up by one with no
active use.

## Decision

Remove the COMPRESSED flag from the header flags byte. Shift subsequent flag
bits down by one:

| Before         | Bit   | After          | Bit |
| -------------- | ----- | -------------- | --- |
| ENCODING       | 0     | ENCODING       | 0   |
| ~~COMPRESSED~~ | ~~1~~ | RESPONSE       | 1   |
| RESPONSE       | 2     | ERROR          | 2   |
| ERROR          | 3     | MORE_FRAGMENTS | 3   |
| MORE_FRAGMENTS | 4     | (reserved)     | 4–7 |
| (reserved)     | 5–7   |                |     |

Remove `"compression"` from the capability registry. Shift capability internal
bit numbers down by one:

| Before          | Bit   | After          | Bit |
| --------------- | ----- | -------------- | --- |
| ~~compression~~ | ~~0~~ |                |     |
| clipboard_sync  | 1     | clipboard_sync | 0   |
| mouse           | 2     | mouse          | 1   |
| (etc.)          | N     | (etc.)         | N-1 |

If application-layer compression is ever needed in a future version, it will be
designed at that time. A future design may use a different approach (e.g.,
capability-negotiated, per-message-type selective, dedicated header extension),
and will not be constrained by a v1 reservation.

## Consequences

- Header flags byte: 4 defined bits (ENCODING, RESPONSE, ERROR, MORE_FRAGMENTS)
  at bits 0–3; bits 4–7 reserved. No phantom flags.
- The `"compression"` capability string is no longer valid and MUST NOT appear
  in `ClientHello` or `ServerHello` capabilities arrays. Capability table loses
  one unused entry; existing capabilities shift to lower bit numbers.
- Protocol docs require updates across multiple files (tracked in owner-review
  cleanup-todo File 5):
  - Doc 01: §3.4 flags table, §3.5 section deleted, example updated,
    `ERR_PROTOCOL_ERROR` description updated
  - Doc 02: `"compression"` capability row removed; §4.1 note removed;
    capability fallback table row removed; capability bit numbers updated
  - Doc 04: COMPRESSED flag paragraph removed; wire dump comment updated
  - 99-post-v1: `"COMPRESSED flag reserved"` language removed from compression
    section
- Daemon docs require update (CTR-16): `03-lifecycle-and-connections.md`
  capability field description removes `"compression support"` example.
