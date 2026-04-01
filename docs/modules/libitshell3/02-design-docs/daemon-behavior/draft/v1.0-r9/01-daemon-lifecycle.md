# Daemon Lifecycle

- **Date**: 2026-03-24
- **Scope**: Daemon startup sequence, shutdown sequence, LaunchAgent
  integration, crash recovery, and client-initiated auto-start — behavioral
  constraints only

---

## 1. Daemon Startup

### Trigger

The daemon binary is executed (directly, via LaunchAgent, or via SSH fork+exec).

### Preconditions

None — this is the entry point. The process has just started.

### Ordering Constraints

| # | Constraint                                                                    | Verification                                                                                           |
| - | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| 1 | Inherited fd check MUST complete BEFORE stale socket probe                    | `launch_activate_socket()` (or platform equivalent) is called first; if it returns an fd, step 2 is skipped |
| 2 | Stale socket probe MUST complete BEFORE socket bind (skipped if inherited fd) | Connect to socket path; if `ECONNREFUSED`, socket file is unlinked before bind attempt                 |
| 3 | Socket bind MUST succeed BEFORE event loop entry                              | No `EVFILT_READ` on `listen_fd` fires before bind+listen completes                                     |
| 4 | ghostty config MUST be loaded BEFORE first Terminal creation                  | No `Terminal.init()` call occurs without a valid config object                                         |
| 5 | Default session (PTY fork + Terminal) MUST be created BEFORE event loop entry | First client connecting after event loop start receives a session list containing at least one session |
| 6 | Event loop entry is the LAST startup step                                     | No client messages are processed before all initialization completes                                   |

### Observable Effects

On successful startup (no wire messages — no clients are connected yet):

1. Socket file appears at the resolved path with mode 0600
2. Socket directory has mode 0700, owned by daemon UID
3. Socket accepts connections (daemon is ready)
4. One default session exists with one pane (shell process running)

On startup failure:

1. Daemon exits with non-zero status
2. No socket file is created (or stale socket is cleaned up but no new one
   bound)

### Startup Failure Modes

| Step               | Failure                                      | Observable Effect                                                               |
| ------------------ | -------------------------------------------- | ------------------------------------------------------------------------------- |
| Inherited fd check | `launch_activate_socket()` error             | Falls through to normal stale socket probe + bind path                          |
| Stale socket probe | Connection succeeds (daemon already running) | New daemon exits with informational message; existing daemon unaffected         |
| kqueue creation    | `kqueue()` fails                             | Daemon exits non-zero; no socket file created                                   |
| Socket bind        | `bind()` fails after stale cleanup           | Daemon exits non-zero; no socket listening                                      |
| Socket directory   | Wrong ownership or mode > 0700               | Daemon refuses to start with descriptive error                                  |
| ghostty config     | Config load fails                            | Daemon exits non-zero; socket file may exist but daemon never enters event loop |
| PTY fork           | `forkpty()` fails                            | Daemon exits non-zero                                                           |
| Terminal init      | `Terminal.init()` fails                      | Daemon exits non-zero                                                           |

### Invariants

- **All-or-nothing startup**: Either all initialization steps succeed and the
  daemon enters the event loop, or the daemon exits. There is no partial startup
  state where the daemon is listening but not fully initialized.
- **No session restoration**: The daemon starts fresh every time (ADR 00036). No
  snapshot/restore from disk.
- **Startup orchestration is the binary's job**: The daemon binary
  (`daemon/main.zig`) orchestrates the startup sequence by calling into
  libitshell3 and libitshell3-protocol in the correct order. The libraries
  contain no startup orchestration logic (ADR 00048).

### Policy Values

| Parameter             | Value       | Notes                            |
| --------------------- | ----------- | -------------------------------- |
| Default server-id     | `"default"` | Used in socket path resolution   |
| Default session name  | `"default"` | First session created at startup |
| Default terminal size | 80 x 24     | Columns x rows for initial pane  |
| Socket directory mode | 0700        | Owner-only traversal             |
| Socket file mode      | 0600        | Owner-only read/write            |

### Edge Cases

- **Socket path override**: `--socket-path` bypasses the 4-step resolution
  algorithm. All other behavior is identical.
- **Foreground mode**: `--foreground` skips LaunchAgent registration. The
  startup sequence is otherwise identical. Required for SSH fork+exec mode.
- **LaunchAgent socket activation**: When launched by launchd with `Sockets`
  configuration, the daemon inherits a pre-bound listen fd. The inherited fd
  check (constraint #1) detects this and skips both the stale socket probe and
  `Listener.init()`. See Section 5.

---

## 2. Daemon Shutdown

### Trigger

One of:

1. **Signal**: SIGTERM, SIGINT, or SIGHUP received via `EVFILT_SIGNAL`
2. **No sessions remain**: The last remaining session is destroyed (whether by
   pane-exit auto-destroy or explicit `DestroySessionRequest`)
3. **Explicit command**: Client sends a shutdown request (reserved for future —
   not in v1)

All three triggers initiate the same shutdown sequence.

### Preconditions

Daemon is running (event loop is active).

### Ordering Constraints

| # | Constraint                                                                   | Verification                                                                                   |
| - | ---------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| 1 | Stop accepting new connections BEFORE sending Disconnect to existing clients | No new client receives a handshake after shutdown begins                                       |
| 2 | IME flush (deactivate) BEFORE client Disconnect notification                 | Committed text from active preedit is written to PTY before clients are told to disconnect     |
| 3 | Disconnect notification MUST be sent BEFORE force-closing client connections | Client receives `Disconnect(reason: server_shutdown)` before the connection is closed          |
| 4 | Client drain period BEFORE child process reaping                             | Clients have time to receive final messages and disconnect gracefully                          |
| 5 | Child process reaping BEFORE listener close                                  | All PTY resources are cleaned up before the socket file is removed                             |
| 6 | Listener close (socket file unlink) BEFORE process exit                      | Socket file is removed on clean shutdown; absence of socket file signals clean exit to clients |

### Observable Effects

Wire messages sent to all connected clients, in order:

1. `Disconnect(reason: server_shutdown)` — best-effort, no retry on
   `would_block` or `peer_closed`

Post-wire observable:

2. Socket stops accepting new connections
3. Existing connections are drained (up to timeout), then force-closed
4. Child processes receive SIGHUP
5. Socket file is removed from filesystem
6. Daemon process exits

### Invariants

- **No input loss on clean shutdown**: Active preedit compositions are flushed
  (committed text written to PTY) before clients are notified. No user input is
  silently discarded.
- **No SIGKILL to children**: The daemon sends SIGHUP (terminal hangup) to child
  processes, never SIGKILL. If a child does not exit promptly, it becomes
  orphaned and is reaped by init/launchd.
- **Best-effort client notification**: The Disconnect message is sent but not
  guaranteed to be delivered. The daemon does not block on slow clients.
- **Graceful shutdown logic lives in the library**: The daemon binary triggers
  shutdown; libitshell3 provides the drain/cleanup logic (ADR 00048).

### Policy Values

| Parameter                | Value       | Notes                                                         |
| ------------------------ | ----------- | ------------------------------------------------------------- |
| Client drain timeout     | 2–5 seconds | Daemon continues event loop during this window                |
| Early exit on full drain | Yes         | If all clients disconnect before timeout, proceed immediately |
| Child signal             | SIGHUP      | Not SIGKILL                                                   |
| Child reap mode          | `WNOHANG`   | Non-blocking; unreaped children become orphans                |

### Edge Cases

- **No connected clients at shutdown**: Steps 3–4 (notify + drain) are skipped.
  Proceed directly to child reaping.
- **Client sends messages during drain**: The daemon continues processing the
  event loop during the drain period. Client messages (e.g., detach
  acknowledgment) are handled normally.
- **Multiple simultaneous shutdown triggers**: The shutdown sequence is
  idempotent — if a signal arrives while already shutting down, it is ignored.

---

## 3. Crash Recovery (Unclean Shutdown)

### Trigger

Daemon crashes or is killed with SIGKILL (graceful shutdown does not run).

### Observable Effects (Post-Crash State)

| Resource        | State After Crash                                             | Recovery Mechanism                                                                              |
| --------------- | ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Socket file     | Stale file remains on disk                                    | Next daemon startup: `connect()` probe → `ECONNREFUSED` → `Listener.init()` unlinks and rebinds |
| Child processes | Receive SIGHUP from kernel (PTY master close on process exit) | Shells exit on SIGHUP; no explicit cleanup needed                                               |
| PTY master FDs  | Closed by kernel on process exit                              | Slave side gets EIO; child shells detect and exit                                               |
| Active preedit  | Lost                                                          | Acceptable — preedit is transient input state                                                   |
| Terminal state  | Lost (in-memory only)                                         | No recovery in v1 (ADR 00036)                                                                   |

### Invariants

- **Stale socket detection is automatic**: The transport layer's stale socket
  detection (connect probe + unlink) handles the only persistent artifact of a
  crash. No special daemon code is needed for crash recovery.
- **Kernel guarantees suffice**: Unix process cleanup (kernel closes all FDs,
  PTY slaves get EIO) ensures child processes are notified of daemon death
  without any daemon-side logic.

### Edge Cases

- **Client reconnection after crash**: Clients use exponential backoff with
  jitter (100ms, 200ms, 400ms, ..., max 10s). After 5 consecutive failures, the
  client reports the error to the user. Clients distinguish clean exit (no
  socket file) from crash (stale socket file present).

---

## 4. Client-Initiated Daemon Auto-Start

### Trigger

Client attempts to connect and no daemon is running.

### Preconditions

No daemon is currently bound to the resolved socket path (`ECONNREFUSED` or
`ENOENT` on connect attempt).

### Auto-Start Mechanisms

| Environment            | Mechanism                     | Details                                                                                                                 |
| ---------------------- | ----------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| macOS (local)          | LaunchAgent socket activation | Client writes plist, calls `launchctl bootstrap user/<uid>`. See Section 5. Uses `user/<uid>` domain (ADR 00049)        |
| macOS (remote via SSH) | LaunchAgent socket activation | Same mechanism as local — `ssh host "launchctl bootstrap user/<uid> <plist>"`. Daemon survives SSH disconnect (Phase 5) |
| Linux (local)          | Fork+exec                     | Client forks `it-shell3-daemon --foreground`, waits up to 5s for socket                                                 |
| Linux (remote via SSH) | systemd --user service        | `ssh host "systemctl --user start it-shell3-daemon"`. Daemon survives SSH disconnect (Phase 5)                          |

### Ordering Constraints

| # | Constraint                                                        | Verification                                                   |
| - | ----------------------------------------------------------------- | -------------------------------------------------------------- |
| 1 | Client MUST probe socket BEFORE attempting auto-start             | No daemon start attempted if a daemon is already running       |
| 2 | Stale socket cleanup (unlink) MUST happen BEFORE new daemon start | New daemon does not encounter `EADDRINUSE` from a stale socket |
| 3 | Client MUST wait for socket availability BEFORE connecting        | Client does not attempt handshake until daemon is ready        |

### Observable Effects

1. Client probes socket path: `ECONNREFUSED` or `ENOENT`
2. If `ECONNREFUSED`: client unlinks stale socket file
3. Client starts daemon via appropriate mechanism
4. Client retries connection with exponential backoff
5. Connection succeeds → normal handshake flow

### Policy Values

| Parameter                | Value                                                      | Notes                                    |
| ------------------------ | ---------------------------------------------------------- | ---------------------------------------- |
| Reconnection backoff     | Exponential with jitter: 100ms, 200ms, 400ms, ..., max 10s | Client-side only                         |
| Max consecutive failures | 5                                                          | After which client reports error to user |
| Fork+exec socket wait    | Up to 5 seconds                                            | Before giving up on daemon start         |

### Invariants

- **Auto-start is entirely client-side**: The daemon has no retry logic. It
  either starts successfully or exits with an error.
- **Daemon is identical regardless of start method**: LaunchAgent, fork+exec, or
  SSH — the daemon binary runs the same startup sequence (Section 1).

---

## 5. LaunchAgent Integration

### Trigger

macOS client needs to start or manage the daemon via launchd.

### Preconditions

- `build_options.enable_launchagent` is `true` (macOS application bundle only;
  `false` for standalone/testing builds)
- Client app has write access to `~/Library/LaunchAgents/`

### Socket Activation Behavior

When launched by launchd with `Sockets` configuration:

| # | Constraint                                                                                                        | Verification                                                                  |
| - | ----------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| 1 | Daemon MUST detect inherited fd via `launch_activate_socket()` BEFORE stale socket probe (Section 1, constraint #1) | Inherited fd detection skips both stale socket probe and `Listener.init()`    |
| 2 | Inherited fd MUST be registered with kqueue like a self-created fd                                                | Events on the inherited fd are dispatched identically to self-created sockets |

### Observable Effects

**Socket activation path** (daemon started by launchd):

1. launchd creates socket, binds, and listens on behalf of daemon
2. Daemon inherits the pre-bound fd
3. Daemon skips stale socket probe and `Listener.init()`, wraps inherited fd
4. Clients connecting during daemon startup are queued by launchd (no
   `ECONNREFUSED`)

**Client-side registration**:

1. Client writes plist to
   `~/Library/LaunchAgents/com.powdream.itshell3.daemon.plist`
2. Client runs `launchctl bootstrap user/$(id -u) <plist-path>`
3. launchd starts daemon with socket activation

### Plist Configuration

| Key                            | Value                          | Purpose                             |
| ------------------------------ | ------------------------------ | ----------------------------------- |
| Label                          | `com.powdream.itshell3.daemon` | Unique service identifier           |
| KeepAlive                      | `true`                         | launchd restarts daemon if it exits |
| Sockets.Listeners.SockPathName | Socket path                    | Pre-bound socket for activation     |
| Sockets.Listeners.SockPathMode | 384 (0600)                     | Owner-only socket access            |

### Version Conflict Handling

**Trigger**: Client receives `server_version` in ServerHello that differs from
the bundled daemon binary version.

| # | Constraint                                                    | Verification                                            |
| - | ------------------------------------------------------------- | ------------------------------------------------------- |
| 1 | Version comparison MUST use `server_version` from ServerHello | Client does not guess daemon version from file metadata |
| 2 | Old daemon MUST be fully stopped BEFORE new daemon starts     | No two daemons compete for the same socket path         |

**Observable effects on version mismatch** (all client-side):

1. `launchctl unload` the daemon plist
2. `kill(daemon_pid, SIGTERM)` — graceful shutdown
3. Wait for socket to become unavailable
4. `launchctl bootstrap user/$(id -u) <plist>` with updated plist pointing to
   new binary
5. Reconnect via standard handshake flow

### Invariants

- **Version conflict is entirely client-side**: The daemon has no version
  conflict logic. It responds to handshake messages and serves clients. Version
  detection and resolution are client responsibilities.
- **LaunchAgent code is comptime-gated in the binary**: The library
  (libitshell3) is platform-agnostic. LaunchAgent integration is the binary's
  responsibility (ADR 00048).
- **Daemon behavior is identical regardless of start method**: A
  LaunchAgent-started daemon and a foreground-started daemon run the same event
  loop and serve clients identically.

### Edge Cases

- **Remote connections (SSH)**: Socket activation is not used. Remote daemons
  start with `--foreground`. Version compatibility uses `protocol_version`
  min/max negotiation during handshake (not binary version comparison). If
  protocol versions are incompatible, the server sends
  `Disconnect(reason: version_mismatch)`.
- **KeepAlive restart**: If the daemon exits (clean or crash), launchd restarts
  it due to `KeepAlive: true`. The restarted daemon goes through the normal
  startup sequence (Section 1), including stale socket detection.

---

## 6. Socket Path Resolution

### Resolution Algorithm

The transport layer resolves the socket path using a 4-step fallback, shared
identically by daemon and client:

| Priority | Source             | Path                                         |
| -------- | ------------------ | -------------------------------------------- |
| 1        | `$ITSHELL3_SOCKET` | Exact value of environment variable          |
| 2        | `$XDG_RUNTIME_DIR` | `$XDG_RUNTIME_DIR/itshell3/<server-id>.sock` |
| 3        | `$TMPDIR`          | `$TMPDIR/itshell3-<uid>/<server-id>.sock`    |
| 4        | Fallback           | `/tmp/itshell3-<uid>/<server-id>.sock`       |

### Invariants

- **Daemon and client use identical resolution**: Both use the same transport
  layer function. A client will always find the daemon's socket if they share
  the same environment variables and server-id.
- **`--socket-path` overrides all resolution**: When provided, the entire 4-step
  algorithm is bypassed.
