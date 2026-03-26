# 00054. Per-Instance Socket Directory

- Date: 2026-03-26
- Status: Accepted

## Context

The current socket path layout places a single socket file per daemon instance:

```
$BASE/itshell3/<server_id>.sock
```

The debug subsystem (ADR 00053) introduces a second socket per instance
(`debug.sock`) alongside the client protocol socket. The current flat layout
cannot accommodate multiple sockets per instance without ad-hoc naming
conventions (e.g. `<server_id>.sock`, `<server_id>-debug.sock`).

Additionally, workspace support is planned — a workspace groups multiple
sessions and maps to one daemon instance. Workspaces need a clean namespace for
instance-level resources (sockets, PID files, log directories).

Alternatives considered:

- **Suffix convention** (`default.sock`, `default-debug.sock`): Works for two
  sockets but does not scale to additional per-instance files (PID file, log
  dir). Naming becomes ad-hoc.
- **Flat directory with prefixes** (`default.sock`, `default.debug.sock`,
  `default.pid`): Same scalability problem, plus glob patterns become fragile.
- **Per-instance subdirectory**: Each instance gets its own directory. All
  instance resources live together. Clean glob pattern (`*/daemon.sock`) for
  discovery.

## Decision

Change the socket layout from a flat file per instance to a **per-instance
subdirectory**:

```
# Before (current)
$BASE/itshell3/<server_id>.sock

# After
$BASE/itshell3/<server_id>/daemon.sock
$BASE/itshell3/<server_id>/debug.sock
$BASE/itshell3/<server_id>/daemon.pid
```

**Resolution algorithm** (unchanged priority, new path format):

1. `$ITSHELL3_SOCKET` — exact path override (points to `daemon.sock`)
2. `$XDG_RUNTIME_DIR/itshell3/<server_id>/daemon.sock`
3. `$TMPDIR/itshell3-<uid>/<server_id>/daemon.sock`
4. `/tmp/itshell3-<uid>/<server_id>/daemon.sock`

**Debug socket** is always at `debug.sock` in the same directory as
`daemon.sock`. The debug socket path is derived from the daemon socket path by
replacing the filename.

**PID file** (`daemon.pid`) contains the daemon's process ID as a decimal
string. Used by clients and `it-shell3-ctl` for stale instance detection: if the
PID is not running, the instance directory is stale and can be cleaned up.

**Directory permissions**:

- `$BASE/itshell3/` or `$BASE/itshell3-<uid>/` — `0700` (existing)
- `$BASE/itshell3/<server_id>/` — `0700` (new, per-instance)

**`<server_id>`** defaults to `"default"`. When workspace support is added, this
becomes the workspace name.

## Consequences

**What gets easier:**

- Adding per-instance resources (debug socket now, PID file and log dir later)
  without naming convention proliferation.
- Instance discovery: `glob("$BASE/itshell3/*/daemon.sock")` finds all running
  daemons.
- Workspace support: `<server_id>` naturally becomes the workspace name.
- Cleanup: removing an instance directory removes all its resources at once.

**What gets harder:**

- Socket path is one level deeper, consuming more of the 104-byte
  `sockaddr_un.path` limit. `default/daemon.sock` adds 19 bytes vs
  `default.sock` (12 bytes) — 7 bytes more. Acceptable given typical base paths.
- `$ITSHELL3_SOCKET` override now points to the daemon socket specifically, not
  the instance directory. Users must specify the full path including
  `daemon.sock`.

**What changes:**

- `socket_path.resolve()` returns path to `daemon.sock` (not `<id>.sock`)
- `socket_path.resolveDebug()` (new) returns path to `debug.sock` in the same
  directory
- `ensureDirectory()` creates the per-instance subdirectory (one more `mkdir`)
- Transport `Listener.listen()` and `connect()` use the new path format
- Daemon CLI `--socket-path` points to `daemon.sock` (or the instance directory)
