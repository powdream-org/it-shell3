# Move Session Restore Procedure from Protocol to Daemon

- **Date**: 2026-03-16
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: daemon design docs
- **Status**: superseded — Snapshot/Restore removed from v1 scope (ADR 00036).
  No implementation needed.

---

## Context

During owner review of the protocol spec (v1.0-r12), Doc 06 Section 4.6
(RestoreSessionResponse) was identified as containing server-internal restore
procedure details:

- The sequence of messages after a successful restore (RestoreSessionResponse,
  LayoutChanged, FrameUpdate I-frame per pane)
- IME state restoration (active_input_method and active_keyboard_layout fields)
- Snapshot reading, pane creation, IME engine re-initialization, and scrollback
  restoration procedure

The wire-observable parts (RestoreSessionResponse payload fields, status codes,
and the message sequence visible to clients) remain in the protocol spec. The
server-internal procedure (how the daemon reads snapshots, creates panes,
initializes IME engines, restores scrollback) belongs in daemon docs.

## Required Changes

1. **Session restore orchestration**: Document the daemon-internal procedure for
   restoring a session from a snapshot — snapshot file reading, validation, pane
   recreation in the correct layout order.
2. **IME engine re-initialization**: Document how the daemon re-initializes IME
   engines for each restored pane using the persisted `active_input_method` and
   `active_keyboard_layout` values.
3. **Scrollback restoration**: Document the scrollback buffer restoration
   procedure, including handling of the `restore_scrollback` flag from the
   request.
4. **Post-restore message sequence**: Document the daemon-internal logic for
   emitting the post-restore message sequence (RestoreSessionResponse, then
   LayoutChanged, then I-frame per pane).

## Summary Table

| Target Doc       | Section/Message              | Change Type | Source Resolution             |
| ---------------- | ---------------------------- | ----------- | ----------------------------- |
| Runtime policies | Session restore procedure    | Add         | Protocol v1.0-r12 Doc 06 §4.6 |
| Runtime policies | IME engine re-initialization | Add         | Protocol v1.0-r12 Doc 06 §4.6 |
| Runtime policies | Scrollback restoration       | Add         | Protocol v1.0-r12 Doc 06 §4.6 |
| Runtime policies | Post-restore message emit    | Add         | Protocol v1.0-r12 Doc 06 §4.6 |

## Reference: Original Protocol Text (removed from Doc 06 §4.6)

The following is the original text as it appeared in the protocol spec before
removal. Provided as reference for the daemon team — adapt as needed.

### 4.6 RestoreSessionResponse (0x0703)

On success, the server follows with CreateSessionResponse-like data and
LayoutChanged notifications.

**Payload** (JSON):

```json
{
  "status": 0,
  "session_id": 5,
  "pane_count": 3,
  "error": ""
}
```

| Field        | Type   | Description                                                     |
| ------------ | ------ | --------------------------------------------------------------- |
| `status`     | number | 0 = success, 1 = snapshot not found, 2 = corrupt, 3 = I/O error |
| `session_id` | u32    | Newly assigned by server                                        |
| `pane_count` | number | Number of restored panes                                        |

**Wire behavior**: On success, the server sends `RestoreSessionResponse`,
followed by `LayoutChanged` for the restored session, followed by `FrameUpdate`
(I-frame) for each pane. The restored session includes `active_input_method` and
`active_keyboard_layout` fields.

Session restore procedure (snapshot reading, pane creation, IME engine
re-initialization, scrollback restoration) is defined in daemon design docs.
