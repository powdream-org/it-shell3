# Per-Instance Socket Directory for Debug Subsystem

- **Date**: 2026-03-26
- **Source team**: daemon
- **Source version**: daemon debug subsystem spec 2026-03-26
- **Source resolution**: ADR 00054 (per-instance socket directory)
- **Target docs**: `01-protocol-overview.md`
- **Status**: open

---

## Context

ADR 00054 changes the socket layout from a flat file per daemon instance to a
per-instance subdirectory. This is driven by the debug subsystem (ADR 00053),
which requires a second socket (`debug.sock`) alongside the client protocol
socket, and by planned workspace support which needs a clean namespace for
per-instance resources.

The current protocol overview documents the socket path as
`$BASE/itshell3/<server-id>.sock`. This must be updated to reflect the new
directory structure.

## Required Changes

### 1. `01-protocol-overview.md` — Socket path specification (§2.1 or equivalent)

- **Current**: Socket path resolves to `$BASE/itshell3/<server-id>.sock`.
- **After**: Socket path resolves to `$BASE/itshell3/<server-id>/daemon.sock`.
  The 4-step resolution algorithm (ITSHELL3_SOCKET > XDG > TMPDIR > /tmp) is
  unchanged; only the final path format changes. Add: `debug.sock` and
  `daemon.pid` exist in the same directory as `daemon.sock`. These are not part
  of the client protocol but are documented for completeness.
- **Rationale**: ADR 00054 requires a per-instance directory for multiple
  sockets.

### 2. `01-protocol-overview.md` — Socket path examples

- **Current**: Inline examples use `<id>.sock`.
- **After**: Update to `<id>/daemon.sock`.
- **Rationale**: Examples must match the new path format.

### 3. `01-protocol-overview.md` — `$ITSHELL3_SOCKET` override

- **Current**: Override semantics not clarified for directory structure.
- **After**: Clarify that the override points to the `daemon.sock` file
  specifically, not the instance directory.
- **Rationale**: The override must be unambiguous with the new multi-file
  directory structure.

## Summary Table

| Target Doc             | Section/Message       | Change Type | Source Resolution |
| ---------------------- | --------------------- | ----------- | ----------------- |
| `01-protocol-overview` | Socket path spec      | Update      | ADR 00054         |
| `01-protocol-overview` | Socket path examples  | Update      | ADR 00054         |
| `01-protocol-overview` | ITSHELL3_SOCKET notes | Update      | ADR 00054         |
