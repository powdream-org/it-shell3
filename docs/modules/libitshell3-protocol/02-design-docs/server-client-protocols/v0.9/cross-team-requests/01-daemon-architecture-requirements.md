# Protocol Changes Required (from Daemon Architecture v0.1)

**Date**: 2026-03-09
**Source team**: daemon
**Source version**: Daemon design v0.1
**Source resolution**: design-resolutions/01-daemon-architecture.md (R5, R7, review-notes 01/03)
**Target docs**: Protocol doc 03 (session/pane mgmt), protocol library architecture
**Status**: open

---

## Context

The daemon architecture v0.1 revision cycle produced three requirements for the protocol team:

1. **Layer 4 Transport**: R5 decided that the protocol library owns transport (socket lifecycle, I/O wrappers), not just codec/framing/state-machine. This is the most significant structural change.
2. **C API export**: R7 decided the protocol library should export a C API header for Swift client interop.
3. **Pane limit error response**: Review note 01 introduced a 16-pane-per-session limit. The server needs a way to reject SplitPane requests that exceed this limit.

---

## Required Changes

### Change 1: Layer 4 Transport in Protocol Library (R5)

The protocol library must implement a fourth layer (Transport) alongside the existing three I/O-free layers. Layer 4 has OS dependencies (socket syscalls) and provides:

**1.1 Socket path resolution** — 4-step fallback algorithm:
1. `$ITSHELL3_SOCKET` (explicit override)
2. `$XDG_RUNTIME_DIR/itshell3/<server-id>.sock`
3. `$TMPDIR/itshell3-<uid>/<server-id>.sock`
4. `/tmp/itshell3-<uid>/<server-id>.sock`

Both daemon and client use this identically. Centralizing it eliminates duplication.

**1.2 `transport.Listener` (server-side)**:
- `Listener.init(config)`: socket + stale socket detection + bind + listen + chmod 0600 + O_NONBLOCK → returns Listener
- `Listener.accept()`: accept + `getpeereid()`/`SO_PEERCRED` UID verification + O_NONBLOCK + setsockopt buffer sizes → returns Connection
- `Listener.deinit()`: close(listen_fd) + unlink(socket_path) + free path string
- `Listener.fd()`: returns listen_fd for consumer's event loop registration

**1.3 `transport.Connection` (both sides)**:
```zig
pub const Connection = struct {
    fd: posix.fd_t,  // pub, for kqueue/RunLoop registration

    pub fn recv(self: Connection, buf: []u8) RecvResult { ... }
    pub fn send(self: Connection, buf: []const u8) SendResult { ... }
    pub fn sendv(self: Connection, iovecs: []posix.iovec_const) SendvResult { ... }
    pub fn close(self: *Connection) void { posix.close(self.fd); self.fd = -1; }
};
```

Result types map EOF/EPIPE/ECONNRESET → `.peer_closed`, EAGAIN → `.would_block`.

Created by `Listener.accept()` (server) or `transport.connect(config)` (client).

**1.4 `transport.connect(config)` (client-side)**: Resolves socket path, creates socket, connects → returns Connection.

**1.5 Stale socket detection**: `connect()` probe → ECONNREFUSED → stale socket reported to caller.

**1.6 Peer credential extraction**: Platform-specific (`getpeereid` on macOS, `SO_PEERCRED` on Linux), centralized in `Listener.accept()`.

**1.7 Socket option configuration**: `SO_SNDBUF`/`SO_RCVBUF` defaults at 256 KiB, configurable.

**What Layer 4 does NOT own**: event loop, ring buffer, reconnection logic, application-level error handling.

**Rationale**: Without Layer 4, daemon and client independently implement socket path resolution (4-step fallback), bind/listen/accept, stale socket detection, peer credential extraction, and socket option configuration — all with identical logic and edge cases.

**SSH (Phase 5)**: v1 is Unix socket only. In Phase 5, Connection internals expand to hold SSH channel state; recv/send dispatch to `libssh2_channel_read()`/`libssh2_channel_write()`. Consumer call sites are unchanged. No vtable or interface in v1.

### Change 2: C API Header Export (R7)

The protocol library SHOULD export a C API header for the codec and framing layers (Layers 1-2), enabling the Swift client to use them directly. This is separate from the daemon library (which has no C API).

Specific scope:
- Layer 1 Codec: `encode()`/`decode()` functions
- Layer 2 Framing: `MessageReader`/`MessageWriter` types
- Layer 3 and 4 may also benefit from C API exposure, but L1-L2 are the minimum for Swift interop.

### Change 3: SplitPane Error Response — PANE_LIMIT_EXCEEDED (Review Note 01)

The daemon enforces a maximum of 16 panes per session. When a SplitPaneRequest would exceed this limit, the server rejects it.

**Required**: Add `PANE_LIMIT_EXCEEDED` as an error reason in the SplitPaneResponse (or equivalent error response) in protocol doc 03.

```json
{
  "type": "SplitPaneResponse",
  "success": false,
  "error": "PANE_LIMIT_EXCEEDED"
}
```

**Design decision**: The limit is NOT announced in ServerHello. The server is the single source of truth for pane count. The client does not need to track pane counts — it sends SplitPane requests and handles success/failure. This keeps the client thin and avoids client-server counter synchronization issues.

---

## Summary Table

| Target | Section/Component | Change Type | Source |
|--------|------------------|-------------|--------|
| Protocol library | New Layer 4 (transport module) | New module | R5 |
| Protocol library | C API header | New build artifact | R7 |
| Protocol doc 03 | SplitPaneResponse | Add `PANE_LIMIT_EXCEEDED` error | Review note 01 |
