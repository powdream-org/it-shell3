# 00056. FrameEntry as Prose Concept, Not Code Type

- Date: 2026-03-26
- Status: Accepted

## Context

The daemon architecture spec (§4.3) says: "The ring buffer stores pre-serialized
wire-format frames (FrameEntry = header + payload bytes)." This names
`FrameEntry` as a concept but provides no struct definition.

During the ring buffer implementation, the question arose: should `FrameEntry`
exist as a named type in the code? Analysis by the daemon-architect and
ghostty-integration-engineer identified the frame export data flow:

```
ghostty/render_export.bulkExport()  →  ExportResult (FlatCell[] + dirty_bitmap)
ghostty/preedit_overlay.overlayPreedit()  →  mutates FlatCell[] in-place
server/frame_builder.buildDirtyRows()  →  DirtyRow[]  [not yet implemented]
server/frame_serializer.serializeAndWrite()  →  raw bytes written to ring
```

The pipeline calls the serializer unidirectionally. The structured data
(session_id, pane_id, frame_type, dirty_rows) is constructed and consumed within
the same timer handler scope — it is never stored, queued, or passed between
modules. The serializer's flat parameter list already serves as its input
contract.

A missing conversion step was identified: `FlatCell[]` (ghostty-internal, field
order: codepoint/fg/bg/flags/wide/content_tag) must be converted to `CellData[]`
(protocol wire format, field order: codepoint/wide/flags/content_tag/fg/bg).
Despite both being 16-byte extern structs, their field orderings differ — no
bitcast is valid. This conversion belongs in a new `server/frame_builder.zig`
module (the runtime policies implementation), which sits at the boundary between
ghostty-domain and protocol-domain types.

Note: the integration boundaries spec (§4.3) states FlatCell and CellData have
"identical memory layout." The code shows they do not — the field order
diverges. This is a spec-code discrepancy to address in the next spec revision.

## Decision

`FrameEntry` remains a prose concept in the spec. No named struct is introduced
in code.

The frame export data flows as local variables within the event loop's timer
handler, passed directly to `serializeAndWrite()` as individual arguments. The
serializer's existing parameter list (session_id, pane_id, frame_type,
dirty_rows, next_sequence) is its input contract — callers conform to it.

The FlatCell→CellData conversion and dirty bitmap → DirtyRow[] assembly will
live in `server/frame_builder.zig` (the runtime policies implementation). This
module depends on both `ghostty/` (for ExportResult/FlatCell) and
`libitshell3-protocol` (for CellData/DirtyRow). The ring buffer remains
type-agnostic — it stores and delivers raw bytes via `writeFrame()`.

## Consequences

- No new type to maintain. The serializer's flat parameter list is the only
  interface contract between the frame export pipeline and the serialization
  step.
- If the runtime policies implementation reveals that frames need to be batched,
  queued, or inspected before serialization, a local struct in
  `frame_builder.zig` can be introduced at that point — driven by implementation
  need, not speculative design.
- The spec's "FrameEntry = header + payload bytes" accurately describes what the
  ring buffer stores (raw wire bytes), not a pre-serialization struct. No spec
  change needed.
- The FlatCell/CellData field order discrepancy (spec says identical layout,
  code says different) must be flagged for the next daemon-architecture spec
  revision.
