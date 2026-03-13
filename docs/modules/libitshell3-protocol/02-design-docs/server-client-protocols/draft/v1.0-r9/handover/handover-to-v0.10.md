# Handover: Server-Client Protocols v0.9 to v0.10

**Date**: 2026-03-08
**Author**: team-lead

---

## Insights and New Perspectives

### FlatCell is a flattened Style-resolved projection

The 16-byte wire FlatCell is NOT a raw dump of ghostty's 8-byte `page.Cell`. ghostty stores a `style_id` — an opaque index into a per-page `RefCountedSet`. The server must dereference this index, extract colors and flags from the resolved `Style` struct, and pack them inline into the FlatCell. This "flattening" is the dominant export cost (~11 ns/cell). The client avoids this entirely by reconstructing `RenderState.Cell` directly from the flat data (~4 ns/cell).

This asymmetry (server-heavy, client-light) is a deliberate design choice: the server has the Terminal and page data structures; the client is a thin RenderState populator.

### SSH compression eliminates the need for application-layer compression

SSH's `zlib@openssh.com` provides persistent-dictionary transport-layer compression that is highly effective for our wire format. Empty cells (mostly zeros), repeated colors, and the fixed 16-byte struct layout produce estimated 10-20x compression for typical terminals, 3-5x for dense colored output. The `COMPRESSED` header flag (bit 1) is correctly reserved but unused in v1. No application-layer compression is needed.

Key detail: SSH compression is off by default on the client side (`Compression no` in `ssh_config`). Remote connection documentation should recommend `Compression yes` or `ssh -C`.

### PoC gap closure

All 5 known gaps from the PoC (grapheme clusters, underline_color, row metadata, palette, minimum size) are now resolved in v0.9 through side tables (GraphemeTable, UnderlineColorTable), row_flags, I-frame palette requirement, and dimension-based suppression. The wire format is PoC-complete — no remaining PoC gaps block implementation.

### Verification convergence

v0.9 verified in 3 rounds (5 → 4 → 3 issues), compared to v0.8's 11 rounds. Two factors contributed: (1) single-topic scope (Priority 0 only), (2) mechanical fixes (number/offset changes) don't cascade, while prose fixes (new sentences with references) do. The one regression per round came from prose changes — the V1-02 fix introduced a phantom message name (`PaneExited`), the V2-01 fix left a MUST precedence ambiguity. Number-only fixes (V2-02, V2-03, V2-04) never cascaded.

---

## Design Philosophy

### The wire format carries semantic content, not internal representation

The protocol sends what the client needs for rendering (codepoint, colors, style flags), not how ghostty stores it internally (style_id, packed unions, RefCountedSet indices). This makes the wire format stable even if ghostty changes its internal storage. The transformation cost (22 µs export + 12 µs import = 34 µs for 80x24) is negligible relative to the 16.6 ms frame budget.

### content_tag preserves ghostty's tagged union optimization

ghostty's `ContentTag` enum (2 bits: codepoint, codepoint_grapheme, bg_color_palette, bg_color_rgb) overloads the content field to hold either a codepoint or a background color. Tags 2-3 are a space optimization for background-only cells that bypass style lookup. The wire format preserves this 1:1 to avoid lossy transformation. The client must dispatch on content_tag when interpreting the codepoint field — same as ghostty's renderer does internally.

### Transport compression is not the protocol's responsibility

SSH handles compression transparently at the transport layer. For local Unix sockets, bandwidth is not a constraint (>1 GB/s). The protocol should not complicate its wire format with compression concerns. If a non-SSH transport is ever needed (e.g., raw TCP for iOS), application-layer compression can be added via the reserved `COMPRESSED` flag without changing the message format.

---

## Owner Priorities

### Wire format efficiency matters

During the review, the owner asked about SSH compression, CellData flattening overhead, and whether raw bypass into ghostty is possible. These questions indicate the owner cares about minimizing unnecessary transformation and bandwidth. The v0.10 team should keep efficiency in mind when making design decisions — avoid adding fields or complexity that increases per-cell cost.

### No new review notes from v0.9

The owner asked investigative questions (SSH compression, CellData/RenderState relationship, content_tag origin) but did not request any review notes. All questions were answered satisfactorily.

---

## New Conventions and Procedures

### Process lesson: mechanical fixes converge, prose fixes cascade

Added as L4 in `docs/insights/design-principles.md`. When fixing verification issues, prefer mechanical substitutions (change a number, rename an identifier) over new prose. If new prose is necessary, avoid introducing new message names or cross-references that verifiers will need to check.

### Insights materialized during v0.9

Three new entries added to `docs/insights/design-principles.md`:
- **A6**: FlatCell is a flattened Style-resolved projection
- **A7**: SSH compression makes application-layer compression unnecessary for v1
- **L4**: Mechanical fixes converge; prose fixes cascade

`docs/insights/ghostty-api-extensions.md` updated:
- New "Flattening" concept section with diagrams
- Known Gaps table: all 5 PoC gaps marked Resolved with v0.9 protocol sections
- SSH compression synergy note

`docs/insights/reference-codebase-learnings.md` updated:
- Style indirection as export bottleneck
- SSH compression complementarity

---

## Cross-Team Requests

### Daemon architecture v0.1 (01-daemon-architecture-requirements.md)

The daemon team's v0.1 revision cycle produced three requirements for the protocol team. See `draft/v1.0-r9/cross-team-requests/01-daemon-architecture-requirements.md` for full details.

1. **Layer 4 Transport**: The protocol library must own transport (Listener, Connection, socket path resolution, stale socket detection, peer credential extraction). This is the most significant structural addition — a new module alongside the existing I/O-free layers.
2. **C API header export**: Codec and framing layers (L1-L2) need a C API header for the Swift client.
3. **PANE_LIMIT_EXCEEDED error**: SplitPaneResponse needs a new error reason for the 16-pane-per-session limit. ErrorResponse only — no ServerHello announcement (the server is the sole source of truth for pane count; the client does not track it).

---

## Pre-Discussion Research Tasks

### Review notes 01-15 triage

Before starting v0.10 discussion, the team should triage the 15 carried-over review notes from v0.8. Some may have been partially addressed by v0.9 changes (e.g., CellData format changes may affect notes about wire format). Recommend reading each note against the current v0.9 documents to identify which are still relevant, which are partially resolved, and which can be closed.

Priority candidates for v0.10:
- **01-scroll-delivery-design** (critical, open): Scroll I-frame delivery path flagged by owner as "fundamentally wrong" in v0.7. Doc 04 §6.1 still contains text the owner ruled incorrect. This has been open since v0.7 and should be resolved.
- Any notes that interact with the new 16-byte FlatCell format, side tables, or row_flags

### Doc 03 frame_type=2 wording fix (R3-T01)

Doc 03 §1.6 and §1.14 say `(frame_type=2)` in the attach sequence — should be `(frame_type=1 or frame_type=2)`. This is a v0.8 regression (authoring error during preedit overhaul). Simple fix, but doc 03 was out of v0.9 scope. Include in v0.10 as a mechanical correction.

### ghostty content union sizing verification

The ghostty-expert noted that `page.Cell`'s packed union has a subtle sizing issue: `color_rgb` (24 bits) is larger than `codepoint` (u21), so the union may occupy 24 bits rather than 21. This should be verified during implementation to ensure the FlatCell `codepoint` field (u32) has sufficient width for all content variants.
