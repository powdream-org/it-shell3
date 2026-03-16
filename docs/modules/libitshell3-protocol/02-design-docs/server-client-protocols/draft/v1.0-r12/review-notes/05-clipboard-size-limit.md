# Clipboard Size Limit

- **Date**: 2026-03-16
- **Raised by**: owner
- **Severity**: MEDIUM
- **Affected docs**: Doc 06 §3 (Clipboard)
- **Status**: open

---

## Problem

The clipboard protocol (`ClipboardWrite` 0x0600, `ClipboardRead` 0x0601) defines
no maximum payload size. A client or server could send arbitrarily large
clipboard contents (e.g., megabytes of text or binary data), potentially causing
unbounded memory allocation, excessive socket backlog, or denial-of-service.

## Analysis

Clipboard data in typical terminal use is small (URLs, command output snippets).
However, nothing prevents programmatic misuse. Other terminal protocols handle
this inconsistently: tmux has no clipboard size limit; OSC 52 implementations
typically have an implicit limit from the terminal buffer size.

Two concerns:

1. **Memory safety**: The receiver must allocate a buffer for the full payload
   before parsing. Without a limit, a malicious peer can exhaust memory.
2. **Flow control interaction**: Large clipboard writes could stall the socket
   write loop, delaying FrameUpdate delivery for the same connection.

A 10 MB limit would cover all practical clipboard use cases (including large
code snippets or logs). Chunked transfer is an alternative for larger content,
but adds protocol complexity with no clear v1 use case.

## Proposed Change

**Option A**: Hard 10 MB limit enforced at the framing layer. Payloads exceeding
the limit are rejected with an `Error` response (`payload_too_large`). No
chunked transfer in v1.

- Pro: Simple, no additional message types.
- Con: 10 MB may be too small for some automation use cases.

**Option B**: Configurable limit (default 10 MB, server-enforced). Client
declares `max_clipboard_bytes` in `FlowControlConfig`.

- Pro: Flexible.
- Con: Added complexity; limit negotiation adds round-trips.

Suggestion: Option A for v1. If chunked clipboard transfer is needed, track as a
post-v1 feature.

## Owner Decision

Option A. Hard 10 MB limit, no chunked transfer in v1.

## Resolution

Pending. Owner decided Option A. Spec update required: add 10 MB limit normative
note to Doc 06 §3 (Clipboard). ADR 00035 to be accepted after spec update.
