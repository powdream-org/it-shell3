# 00035. Clipboard Size Limit

- Date: 2026-03-16
- Status: Proposed

## Context

The clipboard protocol (`ClipboardWrite` 0x0600, `ClipboardRead` 0x0601) defines
no maximum payload size. Without a limit, a peer can send arbitrarily large
clipboard contents, causing unbounded memory allocation on the receiver. Large
clipboard writes also stall the socket write loop, delaying `FrameUpdate`
delivery on the same connection.

Two options were considered:

**Option A**: Hard limit (10 MB) enforced at the framing layer. Payloads
exceeding the limit are rejected with an `Error` response (`payload_too_large`).
No chunked transfer in v1.

**Option B**: Configurable limit (default 10 MB, server-enforced). Client
declares `max_clipboard_bytes` in `FlowControlConfig`.

Option B adds complexity and a negotiation round-trip with no clear v1 use case
— clipboard data in typical terminal use is small (URLs, command output
snippets).

## Decision

**Option A: hard 10 MB limit, no chunked transfer in v1.** The framing layer
rejects payloads exceeding 10 MB with an `Error` response (`payload_too_large`).
Chunked clipboard transfer is deferred post-v1.

## Consequences

- Simple enforcement: one size check at the framing layer, no additional message
  types or negotiation.
- 10 MB covers all practical terminal clipboard use cases.
- Automation scenarios requiring larger payloads must use out-of-band transfer;
  chunked clipboard can be added post-v1 if demand arises.
