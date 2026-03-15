# 00004. Symmetric Encoding Field for Clipboard Messages

- Date: 2026-03-15
- Status: Proposed

## Context

The protocol uses JSON payloads with string-typed `data` fields for clipboard
content. Clipboard data is not always plain text — OS clipboards can hold
arbitrary binary content (images, rich text, encoded blobs). JSON strings are
UTF-8, so binary data must be base64-encoded to survive transport.

The clipboard protocol has an asymmetry in how it handles this:

- **ClipboardWrite** (0x0600, S→C) has an `encoding` field (`"utf8"` or
  `"base64"`) and a `data` string field. This allows the server to send either
  plain UTF-8 text or base64-encoded binary data.
- **ClipboardWriteFromClient** (0x0604, C→S) has only a `data` string field with
  no `encoding` field. Binary clipboard content from the client cannot be
  represented — the receiver has no way to know whether `data` is plain text or
  base64-encoded binary.

Additionally, the OSC 52 integration procedure instructs the server to "decode
the base64 data" before sending ClipboardWrite. OSC 52
(`ESC ] 52 ; c ;
<base64-data> ST`) always carries base64-encoded content per
the xterm spec. Decoding this and placing the raw bytes into a JSON string field
corrupts any non-UTF-8 content. The server should pass through the base64 string
as-is.

These are two facets of the same issue: clipboard data can be either UTF-8 text
or arbitrary binary, and both directions of the protocol must handle both cases
consistently.

Discovered during libitshell3-protocol server-client-protocols v1.0-r12
verification (issue S4-03). Both problems are pre-existing — present since the
clipboard messages were first defined.

## Decision

1. Add an `encoding` field (`"utf8"` | `"base64"`) to `ClipboardWriteFromClient`
   (0x0604), matching the existing field in `ClipboardWrite` (0x0600).

2. Fix the OSC 52 integration procedure in Doc 06 §3.3: the server extracts the
   base64 string from the OSC 52 sequence and sends it as-is in ClipboardWrite
   with `encoding: "base64"`. No server-side decoding.

3. Convention for both directions:
   - `encoding: "utf8"` — `data` contains plain UTF-8 text.
   - `encoding: "base64"` — `data` contains base64-encoded binary content. The
     receiver decodes.

## Consequences

- **Symmetric encoding**: both S→C and C→S clipboard messages can carry binary
  data without corruption.
- **Simpler server logic**: OSC 52 base64 data is passed through without
  decode/re-encode round-trip.
- **Client responsibility**: when `encoding` is `"base64"`, the client (or
  server, for C→S) must decode before using the content.
- **Docs affected**: ClipboardWrite OSC 52 procedure and
  ClipboardWriteFromClient payload definition in the flow control doc.
