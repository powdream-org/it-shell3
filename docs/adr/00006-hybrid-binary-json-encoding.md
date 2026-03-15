# 00006. Hybrid Binary-JSON Encoding

- Date: 2026-03-16
- Status: Accepted

## Context

Terminal cell data is the bulk of wire traffic (~70-95% of payload). Control
messages (handshake, session management, IME) are low-frequency. A uniform
encoding forces a tradeoff: binary everywhere (compact but opaque) or JSON
everywhere (debuggable but bloated for cell data).

## Decision

Hybrid encoding: binary for CellData (3x smaller than JSON, RLE-compatible),
JSON for everything else (debuggable via `socat | jq`, cross-language
`JSONDecoder`). ENCODING flag in header (bit 0) enables per-message dispatch. No
protobuf for v1 — RLE outperforms protobuf for cell data, and Zig protobuf
ecosystem is immature. `CELLDATA_ENCODING` capability flag reserved for v2
alternatives.

No TLV (tag-length-value) for payload fields. JSON payloads provide natural
extensibility (optional fields, forward-compatible parsing). Binary payloads
(CellData) use fixed layouts for performance. TLV adds unnecessary complexity
given the hybrid approach.

## Consequences

- Cell data path is compact and RLE-friendly.
- Control messages are human-readable and self-describing.
- Two parsing paths in client/server code (binary + JSON).
- v2 can negotiate alternative encodings via capability flags without header
  changes.
