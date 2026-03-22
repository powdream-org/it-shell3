# 00014. Application-Layer Compression Deferred

- Date: 2026-03-16
- Status: Superseded by 00027

## Context

Application-layer compression could reduce bandwidth for large FrameUpdate
payloads, especially over WAN connections. However, SSH tunneling already
provides transport-layer compression.

## Decision

Application-layer compression removed from v1. No commitment to reintroduce. SSH
compression (`Compression yes`) covers WAN scenarios. Neither tmux nor zellij
compresses at the application protocol layer. The COMPRESSED flag (header bit 1)
and `"compression"` capability name are reserved for potential future use.

If benchmarking in v2 shows benefit beyond SSH compression, application-layer
compression will be added with explicit exclusion of Preedit and Interactive
tier messages to preserve latency guarantees.

## Consequences

- No compression/decompression overhead on the hot path.
- COMPRESSED flag reserved — v2 can add compression without header format
  change.
- WAN bandwidth is covered by SSH's built-in compression.
- If SSH compression is insufficient for specific workloads (e.g., large CJK
  I-frames over high-latency links), there is no application-layer mitigation in
  v1.
