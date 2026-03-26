# Per-Instance Socket Directory for Debug Subsystem

- **Date**: 2026-03-26
- **Source team**: daemon debug subsystem design
- **Source version**: debug subsystem spec 2026-03-26
- **Source resolution**: ADR 00053 (debug subsystem) + ADR 00054 (per-instance
  socket directory)
- **Target docs**: 03-integration-boundaries.md
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

1. **03-integration-boundaries.md — Daemon startup sequence**

   - **Current**: Step 4 binds a single Unix socket at `<server_id>.sock`
   - **New**: Step 4 creates the per-instance directory (`<server_id>/`), then
     binds two sockets: `daemon.sock` (client protocol) and `debug.sock` (debug
     protocol). Writes `daemon.pid`.
   - Stale detection (Step 2) now checks for a stale instance directory (probe
     `daemon.sock` + verify PID in `daemon.pid`).

2. **03-integration-boundaries.md — Daemon shutdown/cleanup**

   - Add: On clean shutdown, unlink `daemon.sock`, `debug.sock`, and
     `daemon.pid`. Remove the instance directory if empty.

3. **01-module-structure.md — Event loop event sources (if documented)**

   - Add debug Unix socket listener as an additional event source in the event
     loop diagram/table. udata = 99.

4. **02-state-and-types.md — Socket path references (if any)**

   - Update any socket path format references from `<id>.sock` to
     `<id>/daemon.sock`.

## Summary Table

| Target Doc                | Section/Message    | Change Type | Source Resolution |
| ------------------------- | ------------------ | ----------- | ----------------- |
| 03-integration-boundaries | Startup sequence   | Update      | ADR 00053 + 00054 |
| 03-integration-boundaries | Shutdown cleanup   | Add         | ADR 00054         |
| 01-module-structure       | Event loop sources | Add         | ADR 00053         |
| 02-state-and-types        | Socket path refs   | Update      | ADR 00054         |
