# Wire-Level Field Length Validation for User-Settable String Fields

- **Date**: 2026-03-26
- **Source team**: daemon
- **Source version**: N/A (implementation cycle Plan 5, not a
  design-doc-revision)
- **Source resolution**: ADR 00058 (Fixed-Size Inline Buffers for Session
  Fields)
- **Target docs**: `03-session-pane-management.md`, `01-protocol-overview.md`
- **Status**: open

---

## Context

ADR 00058 introduces fixed-size inline buffers for all string fields in the
daemon's `Session` and `Pane` structs. Each buffer is guarded by a MAX_SIZE
constant. Some fields are user-settable or externally-set:

| Constant           | Value | Field origin                                          |
| ------------------ | ----- | ----------------------------------------------------- |
| `MAX_SESSION_NAME` | 64    | User-supplied (CreateSession, Rename, AttachOrCreate) |
| `MAX_PANE_TITLE`   | 256   | Shell-set via OSC 0/2 escape sequences                |
| `MAX_PANE_CWD`     | 4096  | Shell-set via OSC 7                                   |

A client can send a session name of arbitrary length over the wire, and a shell
can emit an arbitrarily long OSC title string. The daemon stores these in
fixed-size buffers, so values exceeding MAX_SIZE must be handled before the
store operation.

The protocol spec currently defines no field length limits and no behavior for
values that exceed the daemon's storage capacity.

## Required Changes

### 1. `03-session-pane-management.md` — Field length constraints

- **Current**: No byte-length constraints on string fields in message
  definitions.
- **After**: Add a constraint row or note to each affected message's field table
  specifying the maximum UTF-8 byte length:
  - **CreateSessionRequest (0x0100)** — `name` field: max 64 bytes UTF-8
  - **RenameSessionRequest (0x010A)** — `name` field: max 64 bytes UTF-8
  - **AttachOrCreateRequest (0x010C)** — `session_name` field: max 64 bytes
    UTF-8
  - **PaneMetadataChanged (0x0181)** — `title` field: max 256 bytes UTF-8; `cwd`
    field: max 4096 bytes UTF-8
- **Rationale**: ADR 00058 introduces fixed-size buffers; the protocol must
  document limits so client implementors know what the daemon will accept.

### 2. `03-session-pane-management.md` — Overflow behavior for client-originated messages

- **Current**: No overflow behavior defined.
- **After**: Define behavior when client-to-server messages
  (CreateSessionRequest, RenameSessionRequest, AttachOrCreateRequest) carry
  string fields exceeding the byte limit. Choose one of:
  - **Reject**: Return an error response (e.g., `ERR_FIELD_TOO_LONG`) without
    processing the request. The client controls the value and can enforce the
    limit before sending. Silent truncation hides a client bug.
  - **Truncate**: Truncate at the nearest complete UTF-8 character boundary at
    or below the limit and proceed.
- **Rationale**: Without a defined behavior, the daemon would either silently
  corrupt data or crash on buffer overrun.

### 3. `03-session-pane-management.md` — Overflow behavior for OSC-originated fields

- **Current**: No overflow behavior defined for server-to-client metadata.
- **After**: For PaneMetadataChanged `title` and `cwd` (which originate from
  shell OSC output, not client requests), define: truncate at the nearest
  complete UTF-8 character boundary at or below the limit before storing and
  broadcasting. The daemon cannot reject these values (the shell already wrote
  them to the PTY). Specify whether truncation is silent or logged
  (recommendation: log at debug level).
- **Rationale**: OSC sequences are unbounded; the daemon must truncate before
  storing in fixed-size buffers.

### 4. `01-protocol-overview.md` or `03-session-pane-management.md` — Error code

- **Current**: No error code for over-length fields.
- **After**: If reject behavior is chosen for client-originated messages, add
  `ERR_FIELD_TOO_LONG` to the error code registry. The error response SHOULD
  include an `error` string identifying which field exceeded the limit and what
  the limit is.
- **Rationale**: Clients need a well-defined error to display a message to the
  user.

## Summary Table

| Target Doc                     | Section/Message                | Change Type                               | Source Resolution |
| ------------------------------ | ------------------------------ | ----------------------------------------- | ----------------- |
| `03-session-pane-management`   | CreateSessionRequest (0x0100)  | Add `name` byte-length constraint         | ADR 00058         |
| `03-session-pane-management`   | RenameSessionRequest (0x010A)  | Add `name` byte-length constraint         | ADR 00058         |
| `03-session-pane-management`   | AttachOrCreateRequest (0x010C) | Add `session_name` byte-length constraint | ADR 00058         |
| `03-session-pane-management`   | PaneMetadataChanged (0x0181)   | Add `title` and `cwd` constraints         | ADR 00058         |
| `03-session-pane-management`   | (new)                          | Define reject/truncate for client fields  | ADR 00058         |
| `03-session-pane-management`   | (new)                          | Define truncate for OSC-originated fields | ADR 00058         |
| `01-protocol-overview` or `03` | error codes                    | Add `ERR_FIELD_TOO_LONG` if reject chosen | ADR 00058         |
