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

JSON encoding for all handshake and control messages. Self-describing,
debuggable, cross-language (Swift JSONDecoder). Capability arrays use string
names (not bitmasks) in JSON for readability and forward compatibility — unknown
names are ignored. The server maps string names to internal bitmask
representation for O(1) lookups. CELLDATA_ENCODING capability flag is a no-op in
v1, reserving a negotiation path for v2 alternative encodings (FlatBuffers,
protobuf) without v1 complexity.

## Consequences

- Cell data path is compact and RLE-friendly.
- Control messages are human-readable and self-describing.
- Two parsing paths in client/server code (binary + JSON).
- v2 can negotiate alternative encodings via capability flags without header
  changes.
- JSON payloads add ~30 bytes per message compared to binary encoding. This is
  negligible and well worth the debuggability gain (seeing `"text": "한"`
  instead of hex bytes). At preedit message frequencies (~15/s at 60 WPM Korean
  typing), the overhead is ~450 B/s.
