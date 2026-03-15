# Daemon Lifecycle and Client Connections

**Version**: v0.5 **Status**: Draft **Scope**: Daemon startup/shutdown
sequences, client connection lifecycle, ring buffer delivery model, auto-start,
crash recovery, reconnection, version conflict handling **Source resolutions**:
R8 (Daemon Lifecycle), R9 (Client Connection Lifecycle) **Cross-references**: R5
(Protocol Boundary / Transport Layer), R2 (Event Loop Model), R6 (IME
Integration) **v0.3 changes**: Absorbed P1 (auto-start), P2 (crash recovery FD
passing), P6 (reconnection procedure), P9 (ring buffer sizing/keyframe), A1
(local version conflict), A2 (remote version conflict) from protocol and
AGENTS.md per daemon v0.3 cross-team revision **v0.4 changes**: Applied R1
(message type renames: `ServerShutdown`→`Disconnect(reason:server_shutdown)`,
`SessionDetachRequest`→`DetachSessionRequest`, `ResizeRequest`→`WindowResize`),
R4 (`pty_master_fd`→`pty_fd`), updated §4.3 `ClientState.attached_session` to
`?*SessionEntry` per R2

---

## 1. Daemon Startup

The daemon follows a 7-step startup sequence. Each step has a single
responsibility, a clear failure mode, and a defined recovery action. Steps are
ordered by dependency: kqueue must exist before FDs can be registered, ghostty
config must be loaded before Terminal instances are created, etc.

### 1.1 Startup Sequence

```mermaid
flowchart TD
    S1["Step 1: Parse CLI args"]
    S2["Step 2: Check existing daemon<br/>(stale socket detection)"]
    S3["Step 3: Initialize kqueue<br/>(+ signal filters)"]
    S4["Step 4: Bind Unix socket<br/>(transport.Listener)<br/><i>register listener.fd() with kqueue</i>"]
    S5["Step 5: Initialize ghostty config"]
    S6["Step 6: Create default session<br/>(PTY fork + Terminal.init)<br/><i>register pty_fd with kqueue</i>"]
    S7["Step 7: Enter event loop<br/>(kevent64)"]

    S1 --> S2 --> S3 --> S4 --> S5 --> S6 --> S7
```

#### Step 1: Parse CLI Arguments

| Argument        | Default     | Description                                                                         |
| --------------- | ----------- | ----------------------------------------------------------------------------------- |
| `--server-id`   | `"default"` | Identifies this daemon instance. Used in socket path resolution.                    |
| `--socket-path` | (computed)  | Override the socket path. Bypasses the 4-step resolution algorithm.                 |
| `--foreground`  | `false`     | Run in foreground. Skips LaunchAgent registration. Required for SSH fork+exec mode. |

#### Step 2: Check Existing Daemon

Uses `transport.connect()` to probe the resolved socket path:

| Probe result        | Meaning                                | Action                                                                                                                    |
| ------------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Connection succeeds | Daemon already running                 | Exit with message: "daemon already running at {path}"                                                                     |
| `ECONNREFUSED`      | Stale socket (previous daemon crashed) | Transport layer's stale socket detection reports this to caller. Caller proceeds — `Listener.init()` will handle cleanup. |
| `ENOENT`            | No socket file                         | Proceed (first startup)                                                                                                   |

This step prevents two daemons from binding to the same socket path. The probe
uses the same `transport.connect()` API that clients use, ensuring identical
path resolution logic.

#### Step 3: Initialize kqueue

```
kqueue() -> kq_fd

Register signal filters:
  EVFILT_SIGNAL, SIGTERM  — graceful shutdown
  EVFILT_SIGNAL, SIGINT   — graceful shutdown (Ctrl-C in foreground mode)
  EVFILT_SIGNAL, SIGHUP   — graceful shutdown (terminal hangup)
```

**Why step 3 (before socket bind)?** kqueue is created early so that FDs
produced by subsequent steps (listen_fd in step 4, pty_fd in step 6) can be
registered with kqueue immediately after creation. This eliminates a window
where events on those FDs could be missed between creation and registration.

Signal delivery via `EVFILT_SIGNAL` requires the corresponding signals to be
blocked with `sigprocmask(SIG_BLOCK, ...)` so they are consumed by `kevent64()`
rather than invoking default signal handlers. The block mask is set once at
daemon startup, before any FDs are created.

SIGCHLD is also registered via `EVFILT_SIGNAL` for child process reaping during
normal operation (see Section 3.2).

#### Step 4: Bind Unix Socket

```
transport.Listener.init(config)
  socket(AF_UNIX, SOCK_STREAM)
  -> stale socket detection (connect probe + unlink if ECONNREFUSED)
  -> mkdir(socket_dir, 0700)   (create parent directory if needed)
  -> bind(sock_fd, sockaddr_un)
  -> listen(sock_fd, backlog)
  -> chmod(socket_path, 0600)  (owner-only access)
  -> fcntl(sock_fd, F_SETFL, O_NONBLOCK)

Register listener.fd() with kqueue:
  EVFILT_READ on listen_fd — triggers on incoming connections
```

`transport.Listener.init()` encapsulates the full socket setup sequence. The
daemon receives a `Listener` value and registers `listener.fd()` with kqueue.
The transport layer owns socket creation, security setup, and stale socket
cleanup. The daemon owns event loop integration.

**Socket path resolution** (in transport layer): `$ITSHELL3_SOCKET` ->
`$XDG_RUNTIME_DIR/itshell3/<server-id>.sock` ->
`$TMPDIR/itshell3-<uid>/<server-id>.sock` ->
`/tmp/itshell3-<uid>/<server-id>.sock`. This 4-step fallback algorithm is shared
by both daemon and client via the transport layer.

#### Step 5: Initialize ghostty Config

Load terminal configuration (font, colors, scrollback size, default palette) via
ghostty config APIs. This creates the shared config object used as a template
for all `Terminal.init()` calls. Must complete before step 6 creates the first
Terminal instance.

#### Step 6: Create Default Session

```
Allocate SessionEntry:
  session.session_id = 1
  session.name = "default"
  session.ime_engine = HangulImeEngine.init(allocator, "direct")
  pane_slots = [MAX_PANES]?Pane{null} // initialized empty
  free_mask = 0xFFFF
  dirty_mask = 0x0000

Create initial Pane:
  forkpty() -> (pty_fd, child_pid)
  Terminal.init(allocator, .{.cols = 80, .rows = 24})
  pane_id = 1

Register pty_fd with kqueue:
  EVFILT_READ on pty_fd — triggers on shell output
```

`forkpty()` combines `openpty()` + `fork()` + `login_tty()`. The child process
execs the user's shell (`$SHELL` or `/bin/sh`). The parent (daemon) receives the
master fd and child pid.

The Session's `tree_nodes[0]` is initialized as a single `SplitNodeData` leaf
pointing to pane slot 0. The `focused_pane` is set to `PaneSlot` 0.

#### Step 7: Enter Event Loop

```
loop {
    n = kevent64(kq_fd, changelist, eventlist, timeout)
    for eventlist[0..n] -> |event| {
        switch (event.filter, event.ident) {
            listen_fd, EVFILT_READ   => acceptClient()
            pty_fd, EVFILT_READ      => handlePtyOutput(pane)
            conn_fd, EVFILT_READ     => handleClientMessage(client)
            conn_fd, EVFILT_WRITE    => drainToClient(client)
            EVFILT_TIMER             => coalesceAndExport()
            EVFILT_SIGNAL            => handleSignal(event.ident)
        }
    }
}
```

The event loop is single-threaded (Resolution 2). All state mutations — key
input processing, PTY output handling, client message parsing, frame export,
connection accept/close — are serialized by the event loop. No locks, no
mutexes, no data races.

### 1.2 Startup Failure Modes

| Step | Failure                             | Action                                                                                                                              |
| ---- | ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| 2    | Connection succeeds (daemon exists) | Exit with informational message. Not an error.                                                                                      |
| 3    | `kqueue()` fails                    | Fatal — exit with errno. Indicates severe OS resource exhaustion.                                                                   |
| 4    | `bind()` fails with `EADDRINUSE`    | Stale socket was not cleaned up. `Listener.init()` handles stale detection and cleanup internally. If bind still fails, fatal exit. |
| 4    | `mkdir()` fails with `EACCES`       | Fatal — cannot create socket directory. Log path and permissions.                                                                   |
| 5    | ghostty config load fails           | Fatal — cannot create Terminal instances without config.                                                                            |
| 6    | `forkpty()` fails                   | Fatal — cannot create initial PTY. Log errno (`EAGAIN` = process limit, `ENOMEM` = memory).                                         |
| 6    | `Terminal.init()` fails             | Fatal — out of memory for terminal state.                                                                                           |

All fatal failures exit with a non-zero status code and a descriptive log
message. There is no partial startup — either all 7 steps succeed or the daemon
does not enter the event loop.

### 1.3 Client-Initiated Daemon Auto-Start

If no daemon is running, the client is responsible for starting one. The
auto-start mechanism depends on the environment:

| Environment          | Mechanism                     | Details                                                                                          |
| -------------------- | ----------------------------- | ------------------------------------------------------------------------------------------------ |
| **macOS (local)**    | LaunchAgent socket activation | Client writes plist and calls `launchctl load`. See Section 6 for LaunchAgent integration.       |
| **Linux / Fallback** | Fork+exec                     | Client forks `itshell3-daemon --foreground`, waits up to 5s for socket to appear, then connects. |
| **Remote (SSH)**     | SSH fork+exec                 | Client runs `ssh user@host "itshell3-daemon --foreground --server-id=<id>"`. See Section 7.      |
| **iOS**              | In-process                    | Daemon embedded in app process (no separate daemon).                                             |

**Client connect-or-start flow:**

```mermaid
flowchart TD
    C{"connect(socket_path)"}
    SUCCESS["Success"]
    HANDSHAKE["handshake"]
    OPERATE["operate"]
    REFUSED["ECONNREFUSED<br/>(stale socket)"]
    R1["unlink(socket_path)"]
    NOENT["ENOENT<br/>(no socket file)"]
    START["start daemon<br/>(LaunchAgent or fork+exec)"]
    RETRY["retry connect with backoff"]

    C --> SUCCESS --> HANDSHAKE --> OPERATE
    C --> REFUSED --> R1 --> START
    C --> NOENT --> START
    START --> RETRY
```

**Reconnection backoff after daemon crash or restart:** Exponential backoff with
jitter: 100ms, 200ms, 400ms, ..., max 10s. After 5 consecutive failed connection
attempts, the client reports the failure to the user (e.g., dialog or status bar
notification). The client distinguishes clean exit (socket file removed by
graceful shutdown) from crash (stale socket file still present).

The backoff applies only to the client's connect retry loop, not to the daemon
itself. The daemon does not implement any retry logic — it either starts
successfully (Section 1.1) or exits with an error (Section 1.2).

---

## 2. Daemon Shutdown

Shutdown is triggered by three events:

1. **Signal**: SIGTERM, SIGINT, or SIGHUP received via `EVFILT_SIGNAL`
2. **Last session close**: The last remaining session's last pane exits (child
   process terminates, no sessions remain)
3. **Explicit command**: A client sends a shutdown request (future — not in v1)

All three trigger the same 7-step graceful shutdown sequence.

### 2.1 Graceful Shutdown Sequence

```mermaid
flowchart TD
    S1["Step 1: Stop accepting connections"]
    S2["Step 2: Flush all ImeEngines"]
    S3["Step 3: Notify clients<br/>(Disconnect with reason: server_shutdown)"]
    S4["Step 4: Wait for client disconnect<br/>(2-5s timeout)"]
    S5["Step 5: Reap child processes"]
    S6["Step 6: Close listener"]
    S7["Step 7: Exit"]

    S1 --> S2 --> S3 --> S4 --> S5 --> S6 --> S7
```

#### Step 1: Stop Accepting Connections

Remove `listen_fd` from kqueue. No new `accept()` calls will be made. Existing
connections continue to be serviced during the drain period.

#### Step 2: Flush All ImeEngines

For each session: call `entry.session.ime_engine.deactivate()`. This eagerly
flushes any active preedit composition:

- If the engine has pending preedit text, `deactivate()` returns an `ImeResult`
  with `committed_text` set.
- The daemon writes the committed text to the session's focused pane PTY via
  `write(pty_fd, committed_text)`.
- This ensures no user input is silently discarded during shutdown.
- If no composition is active, `deactivate()` returns `ImeResult{}` (all
  null/false) — zero cost.

#### Step 3: Notify Clients

Send `Disconnect` message with `reason: server_shutdown` to all connected
clients via their `conn.send()`. This is a best-effort notification — if
`send()` returns `.would_block` or `.peer_closed`, the daemon does not retry.

#### Step 4: Wait for Client Disconnect

Set a kqueue timer (EVFILT_TIMER, 2-5 seconds). Continue processing the event
loop during this window to allow clients to:

- Receive the `Disconnect` message
- Send any final messages (e.g., session detach acknowledgment)
- Close their connections gracefully

When all clients have disconnected (all `conn.fd` values closed by peers),
proceed immediately without waiting for the full timeout. If the timeout expires
with clients still connected, proceed anyway — force-close remaining
connections.

#### Step 5: Reap Child Processes

For each pane:

```
kill(child_pid, SIGHUP)       // signal shell to exit
waitpid(child_pid, WNOHANG)   // non-blocking reap attempt
close(pty_fd)                  // close PTY master
Terminal.deinit()              // free terminal state
```

`SIGHUP` is the conventional signal for "terminal hangup" — shells interpret it
as the terminal being closed and will exit. `WNOHANG` prevents blocking on a
slow-to-exit child. If `waitpid` returns 0 (child still running), the child
becomes orphaned and will be reaped by init/launchd. The daemon does NOT send
SIGKILL — that is excessively aggressive for a terminal multiplexer.

#### Step 6: Close Listener

```
listener.deinit()
  close(listen_fd)
  unlink(socket_path)    // remove socket file from filesystem
  free(path_string)      // deallocate socket path memory
```

`listener.deinit()` performs compound cleanup: close the listening fd, remove
the socket file, and free any allocated path string. This is the transport
layer's responsibility.

#### Step 7: Exit

`exit(0)` for clean shutdown, `exit(1)` for shutdown due to unrecoverable error.

### 2.2 Crash Recovery (Unclean Shutdown)

If the daemon crashes or is killed with SIGKILL, the graceful shutdown sequence
does not run. The consequences:

| Resource        | State after crash                                                            | Recovery                                                                                                     |
| --------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Socket file     | Stale file remains on disk                                                   | Next daemon startup detects via `connect()` probe -> `ECONNREFUSED` -> `Listener.init()` unlinks and rebinds |
| Child processes | Receive SIGHUP from PTY master close (kernel closes all FDs on process exit) | Shells exit on SIGHUP. No explicit cleanup needed.                                                           |
| PTY master FDs  | Closed by kernel on process exit                                             | Slave side gets EIO; child shells detect and exit                                                            |
| Active preedit  | Lost                                                                         | Acceptable — preedit is transient input state, not persistent data                                           |
| Terminal state  | Lost (in-memory only)                                                        | Session persistence (Phase 4) will save/restore terminal content                                             |

The key insight: Unix process cleanup guarantees (kernel closes all FDs, PTY
slaves get EIO) mean that crash recovery requires no special daemon code. The
only artifact is the stale socket file, which is handled by the transport
layer's stale socket detection.

### 2.3 PTY FD Passing for Crash Recovery

Unix domain sockets support file descriptor passing via `sendmsg(2)` with
`SCM_RIGHTS` ancillary data. This enables an optional crash recovery
optimization: a surviving daemon can pass PTY master FDs to a reconnecting
client (or a new daemon process inheriting the session).

| Aspect    | Detail                                                                                           |
| --------- | ------------------------------------------------------------------------------------------------ |
| Mechanism | `sendmsg(2)` / `recvmsg(2)` with `SCM_RIGHTS` control message                                    |
| Scope     | Unix socket only — not available over SSH tunnels                                                |
| Use case  | Passing PTY master FDs from a daemon to a client for direct PTY access (single-client fast path) |
| Status    | Optional optimization — the protocol works without it                                            |

**Limitations:**

- FD passing requires both processes to be on the same host. SSH-tunneled
  connections cannot use `SCM_RIGHTS` because `sshd` intermediates the Unix
  socket connection.
- In v1, the primary crash recovery mechanism is the standard reconnection flow
  (Section 4.6) with full I-frame state resync. FD passing is reserved for
  future optimization (e.g., zero-copy PTY relay in single-client mode).

---

## 3. Runtime Event Handling

### 3.1 New Client Connection

When `EVFILT_READ` fires on `listen_fd`:

```
conn = listener.accept()
  accept(listen_fd) -> client_fd
  getpeereid(client_fd) -> (uid, gid)    // macOS
  verify uid == daemon_uid               // reject unauthorized connections
  fcntl(client_fd, F_SETFL, O_NONBLOCK)
  setsockopt(client_fd, SO_SNDBUF, 256 KiB)
  setsockopt(client_fd, SO_RCVBUF, 256 KiB)
  return Connection{ .fd = client_fd }

Allocate ClientState:
  client_id = next_client_id++
  conn = conn
  state = .handshaking
  message_reader = MessageReader.init()

Register conn.fd with kqueue:
  EVFILT_READ on conn.fd
```

UID verification rejects connections from other users. On macOS, `getpeereid()`
extracts the peer's effective UID from the socket. On Linux, `SO_PEERCRED`
provides the same information. This check is centralized in `Listener.accept()`
(transport layer).

### 3.2 Child Process Exit

When `EVFILT_SIGNAL` fires for SIGCHLD:

```
loop {
    result = waitpid(-1, WNOHANG)
    if result.pid == 0 => break  // no more exited children
    if result.pid == -1 and errno == ECHILD => break  // no children

    pane = lookupPaneByChildPid(result.pid)
    if pane == null => continue  // unknown child (should not happen)

    // Clean up pane resources
    remove pty_fd from kqueue
    close(pty_fd)
    Terminal.deinit()
    remove pane from session's tree_nodes array

    if session has no remaining panes:
        // Last-pane close triggers session auto-destroy.
        // deactivate() before deinit() — flushes any active composition
        // and performs engine-specific cleanup, consistent with the
        // "Session close" contract in doc02 §4.1.
        entry.session.ime_engine.deactivate()
        entry.session.ime_engine.deinit()
        destroy session
        if no sessions remain:
            initiate graceful shutdown (Section 2.1)
    else:
        // Non-last pane close: discard any active composition without
        // flushing — the pane's PTY is gone, committing to it is pointless.
        // See doc02 §4.1 (Pane close, non-last pane) and doc04 §7.3.
        entry.session.ime_engine.reset()
}
```

The `waitpid(-1, WNOHANG)` loop reaps all exited children in one pass. Multiple
SIGCHLD signals can coalesce into one delivery (standard Unix behavior), so the
loop continues until `waitpid` returns 0 or `ECHILD`.

### 3.3 Client Disconnect (Unexpected)

When `conn.recv()` returns `.peer_closed`:

```
Remove conn.fd from kqueue
conn.close()
Free ClientState:
  clear ring_cursors
  if client was attached to a session:
    // no session cleanup needed — sessions persist
    // independently of client connections
  deallocate ClientState
```

Client disconnection does NOT affect sessions. Sessions persist until their
panes exit or the daemon shuts down. This is the fundamental property of a
terminal multiplexer — sessions survive client detach/crash/reconnect.

**Note on DISCONNECTING bypass**: Unexpected disconnects go directly to
`[closed]` without passing through the DISCONNECTING state. This is intentional.
The DISCONNECTING state exists to drain pending outbound messages (e.g., after
`Disconnect` with `reason: server_shutdown`), but when the peer has already
disconnected, there is no socket to drain to — any pending messages are
undeliverable. The state machine diagram in Section 4.1 shows the primary
graceful flow; unexpected disconnects (`conn.recv()` returning `.peer_closed`)
are a distinct path that skips DISCONNECTING because the drain step is
semantically inapplicable.

---

## 4. Client Connection Lifecycle

Each client connection is managed by a per-client state machine. The daemon
tracks client state from `accept()` to `close()`.

### 4.1 State Machine

The daemon uses a subset of the canonical 6-state model from protocol doc 01
(Section 5.2). DISCONNECTED and CONNECTING are client-side only — the daemon
never initiates connections. The daemon's state machine starts at HANDSHAKING
after `Listener.accept()`.

```mermaid
stateDiagram-v2
    [*] --> HANDSHAKING : accept()
    HANDSHAKING --> READY : success
    READY --> OPERATING : AttachSessionRequest
    OPERATING --> READY : DetachSessionRequest
    OPERATING --> [*] : peer closed (unexpected disconnect)
    OPERATING --> [*] : socket error
    OPERATING --> DISCONNECTING : Disconnect msg (graceful shutdown)
    DISCONNECTING --> [*] : conn.close(), state freed
```

### 4.2 State Transitions

| From          | Event                                    | To            | Action                                                                                                 |
| ------------- | ---------------------------------------- | ------------- | ------------------------------------------------------------------------------------------------------ |
| HANDSHAKING   | Valid ClientHello received               | READY         | Send ServerHello with capabilities, protocol version                                                   |
| HANDSHAKING   | Invalid ClientHello / timeout            | [closed]      | Send error, close connection                                                                           |
| READY         | AttachSessionRequest                     | OPERATING     | Set `attached_session`, initialize ring cursors for all visible panes, send I-frame for initial screen |
| READY         | Client disconnect                        | [closed]      | Clean up ClientState                                                                                   |
| OPERATING     | DetachSessionRequest                     | READY         | Clear `attached_session`, clear ring cursors                                                           |
| OPERATING     | AttachSessionRequest (different session) | OPERATING     | Detach from current session, attach to new session, reinitialize ring cursors                          |
| OPERATING     | KeyEvent / MouseEvent                    | OPERATING     | Route to attached session's focused pane (Section 4.5)                                                 |
| OPERATING     | WindowResize                             | OPERATING     | Update `display_info`, recalculate pane dimensions                                                     |
| OPERATING     | Client disconnect                        | [closed]      | Clean up ClientState                                                                                   |
| OPERATING     | `Disconnect` (reason: `server_shutdown`) | DISCONNECTING | Begin drain sequence                                                                                   |
| DISCONNECTING | All pending messages sent                | [closed]      | `conn.close()`, free ClientState                                                                       |
| DISCONNECTING | Drain timeout expires                    | [closed]      | `conn.close()`, free ClientState                                                                       |

The key transition is **OPERATING -> READY** (detach without disconnect). This
allows session switching without reconnecting: the client detaches from session
A, returns to READY, then attaches to session B. The Unix socket connection
stays open throughout.

### 4.3 Per-Client State

```zig
const ClientState = struct {
    client_id: u32,
    conn: transport.Connection,
    state: enum { handshaking, ready, operating, disconnecting },
    attached_session: ?*SessionEntry,
    capabilities: CapabilitySet,
    ring_cursors: [MAX_PANES]?RingCursor, // indexed by PaneSlot (0..15)
    display_info: ClientDisplayInfo,
    message_reader: protocol.MessageReader,
};
```

| Field              | Description                                                                                                                  |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| `client_id`        | Monotonically increasing identifier assigned at `accept()`                                                                   |
| `conn`             | Transport connection (4-byte struct, holds fd)                                                                               |
| `state`            | Current state in the per-client state machine                                                                                |
| `attached_session` | Pointer to the session this client is viewing. Null when in READY state.                                                     |
| `capabilities`     | Negotiated capabilities from handshake (e.g., compression support, protocol extensions)                                      |
| `ring_cursors`     | Per-pane read positions into the shared ring buffer. Fixed array indexed by `PaneSlot` (0..15). One cursor per visible pane. |
| `display_info`     | Client's terminal dimensions and display capabilities (used for pane layout calculation)                                     |
| `message_reader`   | Per-connection framing state. Accumulates partial messages across `recv()` calls.                                            |

### 4.4 Message Receive Path

When `EVFILT_READ` fires on a client's `conn.fd`:

```
result = client.conn.recv(buf)
switch (result) {
    .bytes_read => |n| {
        client.message_reader.feed(buf[0..n])
        while (client.message_reader.next()) |message| {
            // Validate message against current state
            // (Layer 3 connection protocol rejects invalid sequences)
            processMessage(client, message)
        }
    },
    .would_block => {
        // Spurious wakeup, ignore (re-armed automatically by kqueue)
    },
    .peer_closed => {
        handleClientDisconnect(client)  // Section 3.3
    },
    .err => |e| {
        log.err("recv error on client {}: {}", .{client.client_id, e})
        handleClientDisconnect(client)
    },
}
```

`MessageReader.feed()` appends bytes to the framing buffer.
`MessageReader.next()` attempts to extract a complete message (16-byte header +
payload). Multiple messages may arrive in a single `recv()` — the `while` loop
processes all of them.

### 4.5 Multi-Client Input Model

All attached clients can send input. There is no primary/secondary distinction:

- **KeyEvent**: Routed to the `attached_session`'s focused pane. Processed
  through Phase 0->1->2 key routing (Resolution 6).
- **MouseEvent**: Encoded as mouse escape sequence and written to the focused
  pane's PTY, if mouse reporting is enabled in the terminal's DEC mode state.
- **Last writer wins**: If two clients send KeyEvents to the same pane
  simultaneously, the events are processed in the order they arrive at the event
  loop. The single-threaded model (Resolution 2) provides total ordering.

Readonly attachment is a client-requested mode (per protocol doc 03 Section 9).
The daemon enforces it by discarding input messages from clients that requested
readonly mode. This is NOT server-enforced based on connection order.

### 4.6 Reconnection Procedure

When a client reconnects to a running daemon (after disconnect, crash, or daemon
restart), the reconnection follows the standard handshake flow. There is no
incremental reconnection protocol — no "replay from sequence N."

**Reconnection sequence:**

```mermaid
sequenceDiagram
    participant Client
    participant Server

    Note over Client,Server: 1. Client establishes new Unix socket connection
    Client->>Server: 2. ClientHello
    Server->>Client: 2. ServerHello (new client_id, monotonic, never reused)
    Client->>Server: 3. ListSessionsRequest (discover available sessions)
    Server->>Client: 3. ListSessionsResponse
    Client->>Server: 4. ClientDisplayInfo (terminal dimensions)
    Client->>Server: 5. AttachSessionRequest (desired session)
    Server->>Client: 6. AttachSessionResponse<br/>(includes active_input_method,<br/>active_keyboard_layout)
    Server->>Client: 6. I-frame per visible pane (full screen state)
    Note over Client,Server: 7. Client is fully resynchronized
```

**Why no incremental replay:** Every reconnection is a full state resync via
I-frame from the shared ring buffer (Section 5). The full state for a typical
terminal (120x40) is under 35 KB — small enough that full resync is simpler and
more reliable than maintaining per-client sequence watermarks across
disconnections. If reconnection latency becomes a problem, incremental replay
can be added later.

**Reconnection is client-driven:** The daemon has no reconnection logic. It
simply accepts connections, performs handshake, and serves sessions. Whether a
connection is a first-time connect or a reconnection is indistinguishable from
the daemon's perspective — every connection starts fresh with a new `client_id`,
new `MessageReader`, and new `ring_cursors`.

---

## 5. Ring Buffer Delivery Model

The ring buffer is the daemon's mechanism for delivering frame updates to
multiple clients efficiently. It lives in `server/`, not in the protocol
library.

### 5.1 Per-Pane Ring Buffer

Each pane maintains a single ring buffer containing serialized frame data:

```
Ring Buffer (per pane, in server/)
+-------+-------+-------+-------+-------+-------+
| I-0   | P-1   | P-2   | I-3   | P-4   | P-5   |  <- frame slots
+-------+-------+-------+-------+-------+-------+
  ^                        ^               ^
  |                        |               |
  oldest                   client B        client A
  (will be overwritten)    cursor          cursor
```

- **I-frame** (keyframe): Complete screen state. Self-contained — a client can
  render from an I-frame alone without any prior frames.
- **P-frame** (delta): Only changed rows since the last frame (cumulative dirty
  rows since last I-frame). Smaller than I-frames but requires the preceding
  I-frame as a base.

Frame data is serialized once per pane per coalescing interval, regardless of
how many clients are attached. This eliminates O(N) serialization cost for
multi-client delivery.

**Ring buffer parameters:**

| Parameter         | Default       | Configurable                            | Description                                        |
| ----------------- | ------------- | --------------------------------------- | -------------------------------------------------- |
| Ring size         | 2 MB per pane | Server config (not protocol-negotiated) | Total ring buffer capacity                         |
| Keyframe interval | 1 second      | Server config (0.5-5 seconds)           | How often the server writes an I-frame to the ring |

**Sizing analysis** (120x40 CJK worst case, 1s keyframe interval, 60fps Active
tier):

| Component                                         | Size    |
| ------------------------------------------------- | ------- |
| I-frame (120x40, 16-byte FlatCells)               | ~77 KB  |
| P-frame (typical 5 dirty rows)                    | ~10 KB  |
| 1 second of Active tier (60 P-frames + 1 I-frame) | ~677 KB |

2 MB covers typical interactive use with headroom. For sustained heavy output
(e.g., full-screen rewrite at maximum rate), the ring wraps and slow clients
skip to the latest I-frame — this is the correct recovery behavior (Section
5.5).

**Ring invariant:** The ring MUST always contain at least one complete I-frame
for each pane. When the ring write head is about to overwrite the only remaining
I-frame, the server MUST write a new I-frame before the overwrite proceeds. This
ensures any client seeking to the latest I-frame (recovery, attach,
ContinuePane) always finds one.

### 5.2 Per-Client Cursors

Each client maintains its own read cursor (position) into the ring buffer for
each visible pane:

```zig
const RingCursor = struct {
    position: usize,    // current read position in the ring
    last_i_frame: usize, // position of last I-frame sent to this client
};
```

Cursors are independent — clients at different frame rates (e.g., 60fps desktop,
20fps battery-saving iPad) read from the same ring at their own pace.

### 5.3 Frame Delivery

When the coalescing timer fires (`EVFILT_TIMER`), the daemon:

1. For each dirty pane: export frame data (`RenderState.update()` +
   `bulkExport()` + `overlayPreedit()`), serialize into the ring buffer as
   either I-frame or P-frame.
2. For each client in OPERATING state: check if the client has pending data
   (cursor behind write position).
3. If pending data exists and `conn.fd` is write-ready: call
   `conn.sendv(iovecs)` for zero-copy delivery from ring buffer.

### 5.4 Write-Ready and Backpressure

Frame delivery uses `EVFILT_WRITE` on `conn.fd` to avoid blocking the event
loop:

```
sendv_result = client.conn.sendv(iovecs)
switch (sendv_result) {
    .bytes_written => |n| {
        advance client cursor by n bytes
        if cursor == write_position:
            // fully caught up — disable EVFILT_WRITE
            // (re-enable when new frame data is written)
        else:
            // partial write — keep EVFILT_WRITE armed
    },
    .would_block => {
        // socket send buffer full — keep EVFILT_WRITE armed
        // cursor stays at current position
        // next EVFILT_WRITE will retry
    },
    .peer_closed => {
        handleClientDisconnect(client)
    },
}
```

`EVFILT_WRITE` is only enabled when a client has pending data. When the client
is fully caught up, `EVFILT_WRITE` is disabled to avoid busy-looping (kqueue
reports write-ready continuously on an empty socket buffer).

### 5.5 Slow Client Recovery

When a client falls behind (its cursor is far from the write position and the
ring is about to wrap):

1. The ring buffer detects that the client's cursor would be overwritten by new
   data.
2. Instead of accumulating stale P-frames, the client's cursor **skips to the
   latest I-frame**.
3. The client receives a complete screen state (I-frame) and resumes normal
   P-frame delivery from that point.

This prevents slow clients from:

- Consuming unbounded memory (no P-frame accumulation queue)
- Receiving stale delta sequences that produce visual corruption
- Blocking the ring buffer from advancing

The I-frame skip is transparent to the client — it receives a full screen
update, which it can render directly.

---

## 6. LaunchAgent Integration

LaunchAgent support is behind a comptime flag:
`build_options.enable_launchagent`. This flag is `true` for the macOS
application bundle and `false` for standalone/testing builds.

### 6.1 Plist Configuration

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.powdream.itshell3.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/it-shell3-daemon</string>
        <string>--server-id</string>
        <string>default</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>Sockets</key>
    <dict>
        <key>Listeners</key>
        <dict>
            <key>SockPathName</key>
            <string>/path/to/socket</string>
            <key>SockPathMode</key>
            <integer>384</integer>  <!-- 0600 -->
        </dict>
    </dict>
</dict>
</plist>
```

### 6.2 Socket Activation

When launched by launchd with `Sockets` configuration, the daemon inherits a
pre-bound listen fd instead of creating one:

1. launchd creates the socket, binds, and listens on behalf of the daemon.
2. The daemon receives the fd via the `LAUNCH_DAEMON_SOCKET_NAME` check-in
   mechanism (`launch_activate_socket()`).
3. Step 4 of the startup sequence detects the inherited fd and skips
   `Listener.init()`. Instead, it wraps the inherited fd in a `Listener` (or
   uses the fd directly for kqueue registration).

**Benefit**: The socket is available immediately when launchd starts the daemon.
Clients connecting during daemon startup do not get `ECONNREFUSED` — launchd
queues the connections until the daemon is ready.

### 6.3 Client-Side LaunchAgent Registration

The client application (it-shell3.app) is responsible for:

1. Writing the plist to
   `~/Library/LaunchAgents/com.powdream.itshell3.daemon.plist`
2. Running `launchctl load` (or `launchctl bootstrap`) to register the agent
3. On app update: handling version conflicts (see Section 6.4)

This is client-side logic, not daemon logic. The daemon binary is the same
regardless of how it was started.

### 6.4 Local Version Conflict Handling

When the client connects to a running daemon, it receives `server_version` in
the ServerHello handshake message. If this version differs from the client's
bundled daemon binary version, the client initiates a daemon restart:

```mermaid
flowchart TD
    S1["1. Client receives ServerHello<br/>with server_version"]
    S2["2. Compare server_version with<br/>bundled binary version"]
    D{{"3. Version mismatch?"}}
    MATCH["Versions match:<br/>continue normal operation"]
    A["a. launchctl unload<br/>com.powdream.itshell3.daemon.plist"]
    B["b. kill(daemon_pid, SIGTERM)<br/>(graceful shutdown)"]
    C["c. Wait for socket to become<br/>unavailable (poll with timeout)"]
    E["d. launchctl load with updated<br/>plist pointing to new binary"]
    F["e. Reconnect via standard<br/>handshake flow (Section 4.6)"]

    S1 --> S2 --> D
    D -- No --> MATCH
    D -- Yes --> A --> B --> C --> E --> F
```

**Rationale:** The daemon binary is bundled inside the client app. When the user
updates the app (via DMG or Homebrew), the bundled daemon binary changes but the
running daemon is still the old version. The client detects this at handshake
and forces an upgrade. This is the same pattern used by tmux — the client and
server must be the same version.

**The daemon has no version conflict logic.** It simply responds to handshake
messages and serves clients. Version conflict detection and resolution are
entirely client-side. The daemon is passive — it does not compare its own
version against anything.

---

## 7. SSH Fork+Exec (Deferred to Phase 5)

**Status**: Design only. Not implemented in v1.

When implemented, the remote daemon startup path is:

```
Client SSH tunnel:
  ssh user@host -o StreamLocalBindUnlink=yes \
    -L /local/sock:/remote/sock

Remote daemon auto-start:
  ssh user@host "itshell3-daemon --foreground --server-id=<id>"
```

The `--foreground` flag skips LaunchAgent registration (not applicable on remote
hosts). The daemon runs the same startup sequence (Section 1.1), enters the same
event loop, and is indistinguishable from a locally started daemon. No daemon
code changes are needed — only the auto-start mechanism (client-side SSH
command) differs.

### 7.1 Remote Version Conflict Handling

Unlike local connections where the client can kill and restart the daemon
(Section 6.4), remote daemons cannot be trivially replaced — the user may have
installed a different version of the daemon on the remote host, or may not have
permission to upgrade it.

Version compatibility for remote connections uses `protocol_version` min/max
negotiation during the handshake:

```
ClientHello:
  protocol_version_min: u16  // oldest protocol version this client supports
  protocol_version_max: u16  // newest protocol version this client supports

ServerHello:
  protocol_version: u16      // protocol version the server selected
```

The server selects a protocol version within the client's declared range. If the
server's own version range does not overlap with the client's, the server sends
a `Disconnect` message with `reason: version_mismatch` and closes the
connection.

**Client behavior on incompatibility:** The client exits with a descriptive
error message (e.g., "Remote daemon protocol version 3 is not compatible with
this client (requires 5-7). Please update the remote daemon."). The client does
NOT attempt degraded operation — partial protocol compatibility would lead to
subtle bugs.

**Why not kill+restart for remote?** The client does not own the remote daemon.
The daemon may serve other users or sessions. Killing it would disrupt those
sessions. The client can only negotiate at the protocol level.

---

## 8. Transport-Agnostic Design

The daemon always interacts with `transport.Connection` values. Whether a client
connected locally or through an SSH tunnel is invisible to the daemon:

```mermaid
flowchart LR
    subgraph Local["Local client"]
        LC["Client"] --> US1["Unix socket"] --> D1["Daemon"]
    end

    subgraph SSH["SSH-tunneled client"]
        RC["Client"] --> ST["SSH tunnel"] --> SSHD["sshd"] --> US2["Unix socket"] --> D2["Daemon"]
    end

    D1 -.- Note1["Daemon sees:<br/>transport.Connection<br/>from Listener.accept()"]
    D2 -.- Note2["Daemon sees:<br/>transport.Connection<br/>from Listener.accept()<br/>(sshd's UID accepted per<br/>trust model in protocol<br/>doc 01 Section 2.2)"]
```

The daemon has no "local vs remote" code path. All clients are `Connection`
values with `recv()`, `send()`, `sendv()`, and `close()`. This is a structural
property of the architecture, not an abstraction to be maintained.

---

## Prior Art

| Reference                                                   | Relevance                                                                       |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------- |
| tmux server startup (`server_start()` in `server.c`)        | 7-step startup pattern: socket bind, session create, event loop enter           |
| tmux signal handling (`server_signal()`)                    | SIGTERM/SIGHUP/SIGCHLD via libevent signal events (equivalent to EVFILT_SIGNAL) |
| tmux client accept (`server_accept()` in `server-client.c`) | Per-client state, UID verification via `getpeereid()`                           |
| tmux control mode (`control_pane.offset`)                   | Shared pane buffer with per-client read offsets (ring cursor model)             |
| tmux multi-client input                                     | All clients can send input, last writer wins                                    |
| launchd socket activation (`launch_activate_socket()`)      | Inherited fd model for zero-downtime startup                                    |
