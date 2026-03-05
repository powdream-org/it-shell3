# AttachOrCreateResponse Missing `resize_policy` Field

**Date**: 2026-03-05
**Raised by**: verification team (round 3)
**Severity**: MEDIUM
**Affected docs**: 03-session-pane-management.md (Section 1.14)
**Status**: open

---

## Problem

`AttachOrCreateResponse` (0x010D, doc 03 Section 1.14, lines 351-372) is missing the `resize_policy` field that is present in `AttachSessionResponse` (0x0105, doc 03 Section 1.6, line 210/224).

The Round 2 fix correctly added `resize_policy` to `AttachSessionResponse` in both doc 03 Section 1.6 and doc 02 Section 9.2, but the parallel `AttachOrCreateResponse` was not updated. Section 1.14 itself states: "On success, the same post-attach sequence applies as for AttachSessionResponse," which reinforces that the two responses should carry the same informational fields.

**Current AttachOrCreateResponse JSON example** (line 351):

```json
{
  "action_taken": "attached",
  "session_id": 1,
  "pane_id": 1,
  "session_name": "main",
  "active_pane_id": 1,
  "pane_input_methods": [
    {"pane_id": 1, "active_input_method": "direct", "active_keyboard_layout": "qwerty"}
  ]
}
```

**Missing**: `"resize_policy": "latest"` is absent from both the JSON example and the field table.

## Analysis

`AttachOrCreate` is the recommended convenience path (equivalent to tmux's `new-session -A`). An implementor who exclusively uses `AttachOrCreate` -- the expected common case -- would never receive the `resize_policy` field. This defeats the purpose of adding the field to `AttachSessionResponse`.

The impact is informational only (clients do not negotiate `resize_policy`; they just observe it), so this is not a protocol-breaking issue. However, it creates an inconsistency that could confuse implementors who compare the two response formats.

Doc 02 Section 9.3 defers entirely to doc 03 for the `AttachOrCreate` specification, so the fix is localized to doc 03 Section 1.14.

## Proposed Change

Add `resize_policy` to `AttachOrCreateResponse` in doc 03 Section 1.14:

1. Add `"resize_policy": "latest"` to the JSON example (between `active_pane_id` and `pane_input_methods`).
2. Add a row to the field table: `resize_policy | string | Server's active resize policy: "latest" or "smallest". Informational -- not negotiated. See Section 5.1.`

This matches the field definition in `AttachSessionResponse` (Section 1.6, line 224).

## Owner Decision

(Pending.)

## Resolution

(Pending.)
