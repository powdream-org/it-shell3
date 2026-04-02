# Pane foreground_process: Separate Name and Path Fields

- **Date**: 2026-04-02
- **Source team**: impl
- **Source version**: libitshell3 Plan 8 verification
- **Source resolution**: Plan 8 Step 3 triage (SC-7)
- **Target docs**: daemon-architecture 02-state-and-types.md
- **Status**: open

---

## Context

Plan 8 verification found the spec defines
`foreground_process: [MAX_SESSION_NAME]u8` (64 bytes) with
`foreground_process_length: u8`. Two issues:

1. **Wrong constant**: `MAX_SESSION_NAME` is a session name constant (64 bytes),
   not appropriate for a process field. A dedicated constant is needed.
2. **Missing path field**: The owner confirmed that both a process name (e.g.,
   `vim`, `node`) and a process path (e.g., `/usr/local/bin/node`) are needed.
   The spec only has one field. The code currently uses `MAX_FOREGROUND_PROCESS`
   (PATH_MAX = 1024) which conflates name and path.

## Required Changes

1. **02-state-and-types.md Pane type table**: Replace the single
   `foreground_process` field with two fields:
   - `foreground_process`: process name, with a dedicated
     `MAX_FOREGROUND_PROCESS_NAME` constant (64 bytes is likely sufficient)
   - `foreground_process_path`: full process path, with a dedicated
     `MAX_FOREGROUND_PROCESS_PATH` constant (PATH_MAX or similar)
   - Update length fields accordingly

2. **02-state-and-types.md constants table**: Add the new constants.

## Summary Table

| Target Doc            | Section/Message | Change Type          | Source Resolution |
| --------------------- | --------------- | -------------------- | ----------------- |
| 02-state-and-types.md | Pane type table | Add field + constant | SC-7 triage       |
| 02-state-and-types.md | Constants table | Add constants        | SC-7 triage       |
