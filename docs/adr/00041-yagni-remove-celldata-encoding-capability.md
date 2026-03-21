# 00041. YAGNI — Remove `celldata_encoding` Capability

- Date: 2026-03-21
- Status: Accepted

## Context

The capability table (§4 (server-client-protocols Doc 02, v1.0-r12)) includes a
`"celldata_encoding"` entry at internal bit 12. Its stated purpose is to enable
negotiation of alternative CellData binary encodings (e.g., FlatBuffers,
protobuf) in future protocol versions.

In v1, the capability is explicitly a no-op: CellData always uses raw binary
encoding (fixed-size cell structs with optional RLE), and declaring
`"celldata_encoding"` has no effect on the wire format. Section 4.2
(server-client-protocols Doc 02, v1.0-r12) documents a hypothetical v2+
negotiation flow — `ClientHello` sends a `celldata_encodings` preference array,
`ServerHello` echoes back the selected encoding — but no alternative encoding
has ever been designed, specified, or shown to be needed.

Section 7.5 (server-client-protocols Doc 02, v1.0-r12) contains a pseudocode
block labeled "CELLDATA_ENCODING Negotiation (v2+)" that is itself marked as a
no-op in v1. The degradation table (§9.2 (server-client-protocols Doc 02,
v1.0-r12)) likewise notes "v1: no effect; v2+: raw binary used" — confirming the
capability carries no implementation obligation in the current version.

The rationale in §4.2 (server-client-protocols Doc 02, v1.0-r12) cites ecosystem
evolution as a motivation for reserving the negotiation path. However, raw
binary with RLE already outperforms protobuf for cell data (22B vs 400B for a
blank 80-column row), and no concrete workload or partner requirement has been
identified that would motivate a different encoding. Keeping the capability
embeds speculative infrastructure — a phantom bit, a phantom negotiation flow,
and phantom JSON fields — into a v1 handshake that must be implemented, tested,
and maintained without any active use.

## Decision

We do not reserve `"celldata_encoding"` as a protocol capability flag. No
speculative negotiation infrastructure for an unproven future encoding need
belongs in v1. The capability entry, its associated handshake fields, and the
hypothetical negotiation flow are removed entirely.

If an alternative CellData encoding is ever needed in a future version, it will
be designed at that time — with evidence of need, a concrete encoding candidate,
and a full negotiation design. A future design is unconstrained and may use a
different mechanism entirely (e.g., a dedicated extension, a versioned format
field, or a separate capability with defined semantics).

## Consequences

- `"celldata_encoding"` is removed from the capability registry. Capability
  internal bit 12 becomes reserved (unassigned). No active implementation is
  affected because the capability was a no-op in v1.
- `ClientHello` and `ServerHello` MUST NOT include `"celldata_encoding"` in
  their capabilities arrays. The `celldata_encodings` and `celldata_encoding`
  JSON fields are no longer valid protocol fields.
- Future encoding changes, if ever needed, must be designed from scratch with
  demonstrated need. No v1 reservation exists as a starting point.
