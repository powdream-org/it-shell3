# Symmetric Encoding Field for Clipboard Messages

- **Date**: 2026-03-15
- **Raised by**: owner
- **Severity**: MEDIUM
- **Affected docs**: Doc 06 (ClipboardWrite OSC 52 procedure,
  ClipboardWriteFromClient)
- **Status**: deferred to next revision

---

## Problem

Two issues in the clipboard protocol:

1. **OSC 52 procedure error** (verification issue S4-03): Doc 06 §3.3 instructs
   the server to decode base64 data from OSC 52 before sending ClipboardWrite.
   Placing decoded binary bytes into a JSON string field corrupts non-UTF-8
   content. The server should pass through the base64 string as-is with
   `encoding: "base64"`.

2. **Encoding field asymmetry**: `ClipboardWrite` (0x0600, S→C) has an
   `encoding` field, but `ClipboardWriteFromClient` (0x0604, C→S) does not.
   Binary clipboard content from the client cannot be represented.

## Analysis

Both issues stem from incomplete handling of the binary-vs-text distinction in
clipboard data. OSC 52 always provides base64-encoded content. The protocol
already has the `encoding` field on ClipboardWrite but omitted it on the reverse
direction.

## Proposed Change

1. Add `encoding` field to `ClipboardWriteFromClient` (0x0604).
2. Fix OSC 52 procedure to pass through base64 without decoding.

See ADR 00004 for the full decision record.

## Owner Decision

Approved. Deferred to next revision for implementation. S4-03 is closed by this
decision.

## Resolution

Recorded as ADR 00004. To be applied in the next protocol revision cycle.
