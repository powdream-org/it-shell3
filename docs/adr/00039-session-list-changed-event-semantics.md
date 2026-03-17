# 00039. SessionListChanged Event Semantics

- Date: 2026-03-17
- Status: Accepted

## Context

`SessionListChanged` (0x0182) was defined as a broadcast notification sent to
all connected clients when sessions are created or destroyed. The `event` field
had only `"created"` shown as an example; `"destroyed"` appeared only in the
cascade behavior description under `DestroySessionRequest`, not in the message
definition itself. No broadcast notification existed for session rename, leaving
other clients with no way to learn about name changes.

## Decision

`SessionListChanged` is the authoritative broadcast for all session list
mutations. The server MUST send `SessionListChanged` to all connected clients in
the following cases:

| `event`       | Trigger                          | Fields present                  |
| ------------- | -------------------------------- | ------------------------------- |
| `"created"`   | `CreateSessionRequest` succeeds  | `session_id`, `name`            |
| `"destroyed"` | `DestroySessionRequest` succeeds | `session_id`, `name`            |
| `"renamed"`   | `RenameSessionRequest` succeeds  | `session_id`, `name` (new name) |

No other `event` values are defined in v1.

## Consequences

- `SessionListChanged` §4.3 updated: description text, event table, and JSON
  example updated to reflect all three event values.
- `RenameSessionRequest` (0x010A): server sends `SessionListChanged` with
  `event: "renamed"` to all connected clients after a successful rename.
- Cascade behavior (what the server sends to attached clients on session
  destroy) is a daemon implementation concern — see daemon design docs.
