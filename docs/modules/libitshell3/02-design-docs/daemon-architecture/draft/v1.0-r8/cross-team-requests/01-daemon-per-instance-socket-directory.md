# Per-Instance Socket Directory for Debug Subsystem

- **Date**: 2026-03-26
- **Source team**: daemon
- **Source version**: daemon debug subsystem spec 2026-03-26
- **Source resolution**: ADR 00053 (daemon-embedded debug subsystem), ADR 00054
  (per-instance socket directory)
- **Target docs**: `03-integration-boundaries.md`, `01-module-structure.md`,
  `02-state-and-types.md`
- **Status**: open

---

## Context

ADR 00053 adds a debug subsystem to the daemon with a Unix domain socket for
diagnostic commands. ADR 00054 changes the socket layout to a per-instance
directory structure to accommodate the debug socket alongside the client socket.

The daemon architecture docs describe the startup sequence (socket bind, stale
detection) and the event loop (socket listener registration). Both must be
updated to reflect the new directory structure and the additional debug socket.

## Required Changes

### 1. `03-integration-boundaries.md` — Daemon startup sequence

- **Current**: Step 4 binds a single Unix socket at `<server_id>.sock`.
- **After**: Step 4 creates the per-instance directory (`<server_id>/`), then
  binds two sockets: `daemon.sock` (client protocol) and `debug.sock` (debug
  protocol). Writes `daemon.pid`.
- **Rationale**: ADR 00054 requires a per-instance directory for multiple
  sockets. The debug socket (ADR 00053) is the second socket in this directory.

### 2. `03-integration-boundaries.md` — Stale detection

- **Current**: Step 2 probes a single `<server_id>.sock` file.
- **After**: Step 2 checks for a stale instance directory — probe
  `daemon.sock` + verify PID in `daemon.pid`.
- **Rationale**: ADR 00054 changes the socket path structure; stale detection
  must match.

### 3. `03-integration-boundaries.md` — Daemon shutdown/cleanup

- **Current**: No multi-file cleanup described.
- **After**: On clean shutdown, unlink `daemon.sock`, `debug.sock`, and
  `daemon.pid`. Remove the instance directory if empty.
- **Rationale**: ADR 00054 creates multiple files; all must be cleaned up.

### 4. `01-module-structure.md` — Event loop event sources

- **Current**: No debug socket listener in event loop diagram/table.
- **After**: Add debug Unix socket listener as an additional event source (udata
  = 99).
- **Rationale**: ADR 00053 adds a debug listener that the event loop must
  service.

### 5. `02-state-and-types.md` — Socket path references

- **Current**: Socket path format references `<id>.sock`.
- **After**: Update to `<id>/daemon.sock`.
- **Rationale**: ADR 00054 changes the path structure.

## Summary Table

| Target Doc                  | Section/Message    | Change Type | Source Resolution |
| --------------------------- | ------------------ | ----------- | ----------------- |
| `03-integration-boundaries` | Startup sequence   | Update      | ADR 00053 + 00054 |
| `03-integration-boundaries` | Stale detection    | Update      | ADR 00054         |
| `03-integration-boundaries` | Shutdown cleanup   | Add         | ADR 00054         |
| `01-module-structure`       | Event loop sources | Add         | ADR 00053         |
| `02-state-and-types`        | Socket path refs   | Update      | ADR 00054         |
