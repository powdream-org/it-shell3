# Protocol Overview and Message Framing

**Status**: Draft
**Date**: 2026-03-04
**Scope**: libitshell3 server-client wire protocol — transport, framing, message types, lifecycle, error handling

---

## 1. Design Goals and Principles

### 1.1 Primary Goals

| Goal | Description | Rationale |
|------|-------------|-----------|
| **Low-latency input** | Key events reach the PTY in under 1ms over Unix socket | Interactive typing (especially CJK composition) demands imperceptible delay |
| **Efficient rendering updates** | Delta-based RenderState transfer; typical partial update under 1 KB | Bandwidth efficiency enables 60 Hz updates without saturation |
| **CJK-first design** | Preedit synchronization, Jamo decomposition, ambiguous width negotiation are first-class protocol citizens | This is the project's primary differentiator; cannot be bolted on later |
| **Extensibility** | Reserved message type ranges, capability negotiation, version-tagged framing | Protocol must evolve across phases (local Unix, network TCP/TLS, new CJK languages) |
| **Debuggability** | Magic bytes for stream alignment, sequence numbers for packet tracing, well-defined error codes | Binary protocols are hard to debug without explicit observability affordances |

### 1.2 Design Principles

1. **Structured binary framing with fixed-size headers.** Every message has a constant-size header for O(1) dispatch. Variable-length payloads follow. No text-based line parsing for the primary channel.

2. **Server-authoritative state.** The daemon owns terminal state (PTY, scrollback, preedit, cursor). Clients are thin renderers that receive state updates and forward raw input. This simplifies multi-client consistency.

3. **Capability negotiation, not version guessing.** Clients and servers declare feature flags during handshake. The intersection determines the active feature set. No fragile version-string parsing (unlike tmux).

4. **Little-endian byte order throughout.** Matches native byte order of all target platforms (ARM64 macOS/iOS, x86_64 macOS/Linux). Eliminates byte-swap overhead. Zig's `std.mem.writeInt` with `.little` endianness is used for serialization.

5. **Sequence numbers for every message.** Enables request-response correlation, out-of-order detection, and protocol debugging. Each direction maintains its own monotonically increasing sequence counter.

6. **Explicit error reporting.** Every error is a structured message with an error code, the offending sequence number, and a human-readable description. No silent drops.

7. **Backpressure-aware.** Flow control messages prevent buffer bloat when the client cannot keep up with rendering updates.

---

## 2. Transport Layer

### 2.1 Primary Transport: Unix Domain Socket

| Property | Value |
|----------|-------|
| Domain | `AF_UNIX` |
| Type | `SOCK_STREAM` (reliable, ordered byte stream) |
| Path | `$XDG_RUNTIME_DIR/itshell3/<server-id>.sock` or `$TMPDIR/itshell3-<uid>/<server-id>.sock` |
| Permissions | Socket file: `0600` (owner-only). Directory: `0700`. |
| Authentication | Kernel-level: `SO_PEERCRED` / `getpeereid()` provides peer UID/GID. Only same-UID connections accepted. |
| Max message size | 16 MiB (covers full-screen RenderState with large scrollback queries) |
| Buffer sizes | `SO_SNDBUF` / `SO_RCVBUF`: 256 KiB (sufficient for ~30 full frames of buffering) |

**Socket path resolution algorithm:**

```
1. If $ITSHELL3_SOCKET is set → use it directly
2. If $XDG_RUNTIME_DIR is set → $XDG_RUNTIME_DIR/itshell3/<server-id>.sock
3. Otherwise → $TMPDIR/itshell3-<uid>/<server-id>.sock
4. If $TMPDIR is unset → /tmp/itshell3-<uid>/<server-id>.sock
```

The `<server-id>` is a short identifier (default: `default`) allowing multiple daemon instances.

### 2.2 Future Transport: TCP/TLS (Phase 5)

For iOS-to-macOS connectivity:

| Property | Value |
|----------|-------|
| Protocol | TCP with TLS 1.3 (via `std.crypto.tls`) |
| Port | User-configurable; default `7822` |
| Authentication | Mutual TLS with pre-shared client certificates, or SRP-based password authentication |
| Encryption | TLS 1.3 mandatory; no plaintext fallback |
| Framing | Same binary framing as Unix socket (the protocol is transport-agnostic) |
| Keepalive | Application-level heartbeat every 30 seconds; TCP keepalive as backup |

The protocol is designed to be **transport-agnostic**: the same message framing and semantics work over both Unix sockets and TCP/TLS. The transport layer is abstracted behind a `Connection` interface that provides ordered byte stream read/write.

### 2.3 FD Passing (Unix Socket Only)

Unix domain sockets support file descriptor passing via `sendmsg(2)` / `SCM_RIGHTS`. This is used for:

- **Crash recovery**: Passing PTY master FDs from a surviving daemon to a reconnecting client
- **Direct PTY access**: Optional fast path where the client can read/write the PTY FD directly (bypasses the daemon for raw throughput, used only in single-client mode)

FD passing is an optional optimization. The protocol works without it (essential for TCP/TLS transport).

---

## 3. Message Framing Format

### 3.1 Frame Header (16 bytes, fixed)

Every message on the wire begins with this 16-byte header:

```
Offset  Size  Field          Description
──────  ────  ─────          ───────────
 0      2     magic          Magic bytes: 0x49 0x54 (ASCII "IT")
 2      1     version        Protocol version (current: 1)
 3      1     flags          Frame flags (see below)
 4      2     msg_type       Message type ID (little-endian u16)
 6      2     reserved       Reserved, must be 0 (alignment padding)
 8      4     payload_len    Payload length in bytes (little-endian u32)
12      4     sequence       Sequence number (little-endian u32)
```

**Total header size: 16 bytes** (naturally aligned for 4-byte fields)

### 3.2 Frame Flags (byte at offset 3)

```
Bit  Name            Description
───  ────            ───────────
 0   COMPRESSED      Payload is zstd-compressed (see Section 3.5)
 1   RESPONSE        This message is a response to a request (sequence = request's sequence)
 2   ERROR           This message is an error response (implies RESPONSE)
 3   MORE_FRAGMENTS  More fragments follow (for messages exceeding max fragment size)
4-7  (reserved)      Must be 0
```

### 3.3 Wire Format

```
┌──────────────────────┬──────────────────────────────────┐
│  Header (16 bytes)   │  Payload (payload_len bytes)     │
│                      │  (may be empty if payload_len=0) │
│ magic version flags  │                                  │
│ msg_type  reserved   │                                  │
│ payload_len          │                                  │
│ sequence             │                                  │
└──────────────────────┴──────────────────────────────────┘
```

Messages are sent back-to-back on the stream with no inter-message padding. The reader loop:
1. Read exactly 16 bytes (header)
2. Validate magic bytes (`0x49 0x54`)
3. Read exactly `payload_len` bytes (payload)
4. Dispatch on `msg_type`

### 3.4 Sequence Numbers

Each connection direction (client-to-server, server-to-client) maintains its own sequence counter, starting at 1. Sequence 0 is reserved for unsolicited notifications.

- **Requests**: Use the sender's next sequence number
- **Responses**: Echo the request's sequence number and set the `RESPONSE` flag
- **Notifications**: Use the sender's next sequence number (not a response to anything)
- **Errors**: Echo the offending request's sequence number and set both `RESPONSE` and `ERROR` flags

The sequence counter wraps at `0xFFFFFFFF` back to 1 (skipping 0).

### 3.5 Compression

When the `COMPRESSED` flag is set, the payload is zstd-compressed. Compression is optional and negotiated during handshake.

- **Minimum payload size for compression**: 256 bytes (smaller payloads are not worth the overhead)
- **Compression level**: 1 (fastest; the goal is to reduce bandwidth, not maximize ratio)
- **Dictionary**: None in v1; a shared dictionary for RenderState cell data may be added later

Compression is primarily beneficial for RenderState `FrameUpdate` messages over network transport. Over Unix sockets, the bandwidth savings are negligible compared to the CPU cost.

### 3.6 Fragmentation

Messages larger than 1 MiB should be fragmented:

- Set `MORE_FRAGMENTS` flag on all fragments except the last
- All fragments share the same sequence number
- Fragments must arrive in order (guaranteed by `SOCK_STREAM`)
- The receiver reassembles fragments before dispatching

Fragmentation is a safety mechanism for edge cases (large scrollback queries, bulk clipboard data). Most messages are well under 64 KiB.

---

## 4. Message Type ID Allocation

Message type IDs are 16-bit unsigned integers (`u16`), allocated in ranges by functional category:

### 4.1 Allocation Ranges

| Range | Category | Description |
|-------|----------|-------------|
| `0x0000` | Reserved | Never used |
| `0x0001 - 0x00FF` | **Handshake & Lifecycle** | Connection setup, capability negotiation, heartbeat, disconnect |
| `0x0100 - 0x01FF` | **Session Management** | Session create/destroy/list, attach/detach |
| `0x0200 - 0x02FF` | **Tab & Pane Management** | Tab/pane create/destroy/resize/split, layout changes |
| `0x0300 - 0x03FF` | **Input Forwarding** | Key events, mouse events, clipboard, paste |
| `0x0400 - 0x04FF` | **Render State** | FrameUpdate, scrollback queries, search |
| `0x0500 - 0x05FF` | **CJK & IME** | Preedit sync, CJK config, ambiguous width, composition state |
| `0x0600 - 0x06FF` | **Flow Control** | Pause/resume, backpressure, rate limiting |
| `0x0700 - 0x07FF` | **Auxiliary** | File transfer, notifications, logging, debug |
| `0x0800 - 0x0FFF` | **Reserved for future** | Future protocol extensions |
| `0xF000 - 0xFFFE` | **Vendor extensions** | Third-party extensions (not part of the core protocol) |
| `0xFFFF` | Reserved | Never used |

### 4.2 Core Message Types (v1)

#### Handshake & Lifecycle (`0x0001 - 0x00FF`)

| ID | Name | Direction | Description |
|----|------|-----------|-------------|
| `0x0001` | `ClientHello` | C→S | Client identification and capability declaration |
| `0x0002` | `ServerHello` | S→C | Server identification, capabilities, session list |
| `0x0003` | `Heartbeat` | Bidirectional | Keepalive ping |
| `0x0004` | `HeartbeatAck` | Bidirectional | Keepalive pong (response to Heartbeat) |
| `0x0005` | `Disconnect` | Bidirectional | Graceful disconnect with reason |
| `0x0006` | `Error` | Bidirectional | Structured error report |

#### Session Management (`0x0100 - 0x01FF`)

| ID | Name | Direction | Description |
|----|------|-----------|-------------|
| `0x0100` | `SessionCreate` | C→S | Create a new session |
| `0x0101` | `SessionCreated` | S→C | Session creation confirmation |
| `0x0102` | `SessionAttach` | C→S | Attach to an existing session |
| `0x0103` | `SessionAttached` | S→C | Attach confirmation with session state |
| `0x0104` | `SessionDetach` | C→S | Detach from current session |
| `0x0105` | `SessionDetached` | S→C | Detach confirmation |
| `0x0106` | `SessionList` | C→S | List available sessions |
| `0x0107` | `SessionListResponse` | S→C | Session list |
| `0x0108` | `SessionDestroy` | C→S | Destroy a session |
| `0x0109` | `SessionDestroyed` | S→C | Destroy confirmation (broadcast to all attached clients) |
| `0x010A` | `SessionRenamed` | S→C | Session rename notification |

#### Tab & Pane Management (`0x0200 - 0x02FF`)

| ID | Name | Direction | Description |
|----|------|-----------|-------------|
| `0x0200` | `PaneCreate` | C→S | Create a new pane (optionally via split) |
| `0x0201` | `PaneCreated` | S→C | Pane creation confirmation with pane ID |
| `0x0202` | `PaneClose` | C→S | Close a pane |
| `0x0203` | `PaneClosed` | S→C | Pane close notification |
| `0x0204` | `PaneResize` | C→S | Resize a pane (cols x rows) |
| `0x0205` | `PaneResized` | S→C | Resize confirmation |
| `0x0206` | `PaneFocus` | C→S | Set active pane |
| `0x0207` | `PaneFocused` | S→C | Focus change notification |
| `0x0208` | `TabCreate` | C→S | Create a new tab |
| `0x0209` | `TabCreated` | S→C | Tab creation confirmation |
| `0x020A` | `TabClose` | C→S | Close a tab (and all its panes) |
| `0x020B` | `TabClosed` | S→C | Tab close notification |
| `0x020C` | `TabFocus` | C→S | Switch to a tab |
| `0x020D` | `TabFocused` | S→C | Tab focus notification |
| `0x020E` | `LayoutChanged` | S→C | Layout tree changed (split positions, pane arrangement) |

#### Input Forwarding (`0x0300 - 0x03FF`)

| ID | Name | Direction | Description |
|----|------|-----------|-------------|
| `0x0300` | `KeyInput` | C→S | Raw key event (HID keycode + modifiers + layout) |
| `0x0301` | `MouseInput` | C→S | Mouse event (position, button, modifiers) |
| `0x0302` | `PasteInput` | C→S | Clipboard paste (UTF-8 text) |
| `0x0303` | `ClipboardSync` | Bidirectional | Bidirectional clipboard sync |

#### Render State (`0x0400 - 0x04FF`)

| ID | Name | Direction | Description |
|----|------|-----------|-------------|
| `0x0400` | `FrameUpdate` | S→C | RenderState delta or full update |
| `0x0401` | `FrameAck` | C→S | Client acknowledges frame processing |
| `0x0402` | `ScrollRequest` | C→S | Scroll viewport (up/down/to position) |
| `0x0403` | `ScrollResponse` | S→C | Scrollback data for the requested viewport |
| `0x0404` | `SearchRequest` | C→S | Search in scrollback |
| `0x0405` | `SearchResponse` | S→C | Search results |
| `0x0406` | `SelectionUpdate` | C→S | Client selection change |

#### CJK & IME (`0x0500 - 0x05FF`)

| ID | Name | Direction | Description |
|----|------|-----------|-------------|
| `0x0500` | `PreeditStart` | C→S | IME composition begins |
| `0x0501` | `PreeditUpdate` | C→S | IME composition state update |
| `0x0502` | `PreeditEnd` | C→S | IME composition committed or cancelled |
| `0x0503` | `PreeditSync` | S→C | Server broadcasts preedit state to other clients |
| `0x0504` | `CjkConfig` | Bidirectional | CJK configuration sync (ambiguous width, etc.) |

#### Flow Control (`0x0600 - 0x06FF`)

| ID | Name | Direction | Description |
|----|------|-----------|-------------|
| `0x0600` | `PauseOutput` | S→C | Server requests client to pause (buffer full) |
| `0x0601` | `ResumeOutput` | S→C | Server signals client can resume |
| `0x0602` | `ClientBusy` | C→S | Client is behind on rendering; reduce update rate |
| `0x0603` | `ClientReady` | C→S | Client is caught up; resume full update rate |

#### Auxiliary (`0x0700 - 0x07FF`)

| ID | Name | Direction | Description |
|----|------|-----------|-------------|
| `0x0700` | `ServerNotification` | S→C | Server log/status notification |
| `0x0701` | `ClientNotification` | C→S | Client log/status notification |
| `0x0702` | `ConfigSync` | Bidirectional | Configuration key-value sync |

---

## 5. Connection Lifecycle State Machine

### 5.1 State Diagram

```
                    ┌─────────────┐
                    │ DISCONNECTED│
                    └──────┬──────┘
                           │ connect()
                           ▼
                    ┌─────────────┐
                    │ CONNECTING  │
                    └──────┬──────┘
                           │ TCP/socket connected
                           ▼
                    ┌─────────────┐
              ┌─────│ HANDSHAKING │
              │     └──────┬──────┘
              │            │ ClientHello ↔ ServerHello success
              │            ▼
              │     ┌─────────────┐
              │     │   READY     │◄──── SessionDetached
              │     └──────┬──────┘
              │            │ SessionAttach / SessionCreate
              │            ▼
              │     ┌─────────────┐
              │     │ OPERATING   │
              │     └──────┬──────┘
              │            │ Disconnect / error / timeout
              │            ▼
              │     ┌──────────────┐
              └────►│DISCONNECTING │
                    └──────┬───────┘
                           │ connection closed
                           ▼
                    ┌─────────────┐
                    │ DISCONNECTED│
                    └─────────────┘
```

### 5.2 State Descriptions

| State | Description | Allowed Messages |
|-------|-------------|------------------|
| `DISCONNECTED` | No active connection. Initial and terminal state. | None |
| `CONNECTING` | TCP/socket connection in progress. Transport-layer only. | None (transport handshake) |
| `HANDSHAKING` | Connected; exchanging `ClientHello` / `ServerHello`. | `ClientHello`, `ServerHello`, `Error`, `Disconnect` |
| `READY` | Handshake complete. Client is authenticated but not attached to a session. | Session management messages, `Heartbeat`, `Disconnect` |
| `OPERATING` | Attached to a session. Full protocol in effect. | All message types |
| `DISCONNECTING` | Graceful disconnect in progress. Draining pending messages. | `Disconnect`, `Error` |

### 5.3 State Transitions

| From | Event | To | Action |
|------|-------|----|--------|
| `DISCONNECTED` | `connect()` | `CONNECTING` | Initiate socket/TCP connection |
| `CONNECTING` | Transport connected | `HANDSHAKING` | Client sends `ClientHello` |
| `CONNECTING` | Timeout (5s) | `DISCONNECTED` | Log error, close |
| `HANDSHAKING` | `ServerHello` received, compatible | `READY` | Store negotiated capabilities |
| `HANDSHAKING` | `ServerHello` received, incompatible | `DISCONNECTING` | Send `Error`, close |
| `HANDSHAKING` | Timeout (5s) | `DISCONNECTING` | Send `Error`, close |
| `READY` | `SessionAttach` / `SessionCreate` success | `OPERATING` | Begin session interaction |
| `READY` | `Disconnect` received or sent | `DISCONNECTING` | Drain and close |
| `OPERATING` | `SessionDetach` | `READY` | Detach from session, remain connected |
| `OPERATING` | `Disconnect` received or sent | `DISCONNECTING` | Drain and close |
| `OPERATING` | Connection error / timeout | `DISCONNECTED` | Log error, clean up |
| `DISCONNECTING` | All pending messages sent | `DISCONNECTED` | Close connection |

### 5.4 Heartbeat and Timeout

- **Heartbeat interval**: 30 seconds (configurable)
- **Heartbeat timeout**: 90 seconds (3 missed heartbeats)
- In `OPERATING` state, the server sends `Heartbeat` messages if no other messages have been sent within the heartbeat interval
- The client responds with `HeartbeatAck`
- If no message (of any kind) is received within the timeout, the connection is considered dead

Over Unix sockets, heartbeats are a secondary safety net; the kernel detects peer process death via `EPIPE` / `SIGPIPE` much faster. Over TCP/TLS, heartbeats are essential for detecting silent connection drops.

---

## 6. Error Handling

### 6.1 Error Message Format

The `Error` message (`0x0006`) payload:

```
Offset  Size  Field            Description
──────  ────  ─────            ───────────
 0      4     error_code       Error code (little-endian u32)
 4      4     ref_sequence     Sequence number of the message that caused the error (0 if unsolicited)
 8      2     detail_len       Length of detail string in bytes (little-endian u16)
10      N     detail           UTF-8 error detail string (human-readable)
```

### 6.2 Error Code Ranges

| Range | Category | Description |
|-------|----------|-------------|
| `0x00000000` | Success | No error (never sent in an Error message) |
| `0x00000001 - 0x000000FF` | **Protocol errors** | Malformed messages, version mismatch, bad magic |
| `0x00000100 - 0x000001FF` | **Handshake errors** | Capability mismatch, auth failure |
| `0x00000200 - 0x000002FF` | **Session errors** | Session not found, already attached, permission denied |
| `0x00000300 - 0x000003FF` | **Pane errors** | Pane not found, cannot split, process exited |
| `0x00000400 - 0x000004FF` | **Input errors** | Invalid key, paste too large |
| `0x00000500 - 0x000005FF` | **CJK errors** | Invalid preedit state, unsupported composition |
| `0x00000600 - 0x000006FF` | **Resource errors** | Out of memory, too many sessions/panes, rate limited |
| `0xFFFFFFFF` | **Internal** | Unspecified server error |

### 6.3 Core Error Codes

| Code | Name | Description |
|------|------|-------------|
| `0x00000001` | `ERR_BAD_MAGIC` | Invalid magic bytes in header |
| `0x00000002` | `ERR_UNSUPPORTED_VERSION` | Protocol version not supported |
| `0x00000003` | `ERR_BAD_MSG_TYPE` | Unknown message type ID |
| `0x00000004` | `ERR_PAYLOAD_TOO_LARGE` | Payload exceeds maximum size |
| `0x00000005` | `ERR_INVALID_STATE` | Message not allowed in current connection state |
| `0x00000006` | `ERR_MALFORMED_PAYLOAD` | Payload fails to parse |
| `0x00000007` | `ERR_DECOMPRESSION_FAILED` | zstd decompression failed |
| `0x00000100` | `ERR_VERSION_MISMATCH` | No mutually supported protocol version |
| `0x00000101` | `ERR_AUTH_FAILED` | Authentication failed (UID mismatch, bad certificate) |
| `0x00000102` | `ERR_CAPABILITY_REQUIRED` | Required capability not supported by peer |
| `0x00000200` | `ERR_SESSION_NOT_FOUND` | Referenced session does not exist |
| `0x00000201` | `ERR_SESSION_ALREADY_ATTACHED` | Client already attached to a session |
| `0x00000202` | `ERR_SESSION_LIMIT` | Maximum number of sessions reached |
| `0x00000300` | `ERR_PANE_NOT_FOUND` | Referenced pane does not exist |
| `0x00000301` | `ERR_PANE_EXITED` | Pane's process has exited |
| `0x00000302` | `ERR_SPLIT_FAILED` | Cannot split pane (too small, etc.) |
| `0x00000600` | `ERR_RESOURCE_EXHAUSTED` | Server resource limit reached |
| `0x00000601` | `ERR_RATE_LIMITED` | Too many requests |

### 6.4 Recovery Strategies

| Error Category | Strategy |
|----------------|----------|
| Protocol errors (`0x01-0xFF`) | Fatal. Disconnect immediately. Indicates a bug or protocol mismatch. |
| Handshake errors (`0x100-0x1FF`) | Fatal. Disconnect. Client should report the error to the user. |
| Session errors (`0x200-0x2FF`) | Non-fatal. Client can retry or choose a different session. |
| Pane errors (`0x300-0x3FF`) | Non-fatal. Client can close the pane view and continue. |
| Input errors (`0x400-0x4FF`) | Non-fatal. Drop the input and continue. |
| CJK errors (`0x500-0x5FF`) | Non-fatal. Fall back to non-CJK input mode for the affected pane. |
| Resource errors (`0x600-0x6FF`) | Non-fatal. Client should back off and retry after a delay. |

---

## 7. Endianness and Encoding Conventions

| Item | Convention | Rationale |
|------|-----------|-----------|
| **Integer byte order** | Little-endian | Native for ARM64 (Apple Silicon) and x86_64. Zig `std.mem.writeInt(.little)`. No byte-swap cost on any target platform. |
| **String encoding** | UTF-8, length-prefixed (u16 or u32 byte length) | Universal encoding. No null terminators in payloads — length-prefixed is safer and supports embedded NULs. |
| **Boolean** | u8: `0x00` = false, `0x01` = true | Explicit, no ambiguity. Values other than 0 and 1 are protocol errors. |
| **Enums** | u8 or u16 depending on range | Smallest type that fits. Explicit numeric values (not relying on auto-increment). |
| **Optional fields** | Presence indicated by a preceding u8 flag (`0x00` = absent, `0x01` = present) | Consistent pattern for all optionals. Simpler than sentinel values. |
| **Timestamps** | u64, milliseconds since Unix epoch, little-endian | Used for heartbeat timing and debugging. Not used for protocol logic. |
| **Pane/Session/Tab IDs** | u32, assigned by server, monotonically increasing | Server-authoritative. Never reused during a daemon's lifetime. |

---

## 8. Comparison with Existing Protocols

### 8.1 vs. tmux

| Aspect | tmux | libitshell3 | Improvement |
|--------|------|-------------|-------------|
| **Framing** | OpenBSD `imsg` (14 bytes, coupled to `sendmsg`) | Custom 16-byte header with magic, version, sequence | Portable (no imsg dependency), magic bytes for stream alignment, sequence numbers for debugging |
| **Serialization** | Hand-rolled C structs, packed with `#pragma pack` | Explicit field layouts with little-endian encoding | Cross-language safe, no padding/alignment surprises |
| **Capability negotiation** | Protocol version in `peerid & 0xff`; features guessed from version | Explicit `ClientHello`/`ServerHello` with feature flag bitmasks | No version guessing. Capabilities are declared, not inferred. |
| **CJK support** | None | First-class: `PreeditStart/Update/End`, `PreeditSync`, `CjkConfig` | Enables IME composition across multiplexed sessions |
| **Input forwarding** | `send-keys` text command via control mode | Binary `KeyInput` message with HID keycode, modifiers, layout ID | Lower latency, richer key info (modifier disambiguation, layout awareness) |
| **Rendering** | Raw VT bytes per-pane (client re-parses) | Structured `FrameUpdate` with resolved styles, dirty tracking | No redundant VT parse; delta updates reduce bandwidth 10x for typical cases |
| **Error handling** | `MSG_EXIT` with optional text | Structured `Error` with error codes, ref sequence, detail | Programmatic error handling, not string parsing |
| **Flow control** | `%pause` / `%continue` (control mode only) | Binary `PauseOutput` / `ResumeOutput` / `ClientBusy` / `ClientReady` | Available in all modes, bidirectional |
| **Extensibility** | Fixed message type enum in C header | Ranged type IDs with reserved ranges for future categories | Can add new message categories without ID conflicts |

### 8.2 vs. zellij

| Aspect | zellij | libitshell3 | Improvement |
|--------|--------|-------------|-------------|
| **Serialization** | Protobuf via `prost` | Custom binary framing | Fewer dependencies; Protobuf is heavy for a system-level IPC protocol. Schema evolution handled by capability negotiation + reserved ranges instead. |
| **Rendering model** | Server sends pre-rendered ANSI strings (`Render(String)`) | Server sends structured `FrameUpdate` with cell data | Client can optimize rendering (GPU batching, font caching). No redundant ANSI parsing. |
| **CJK preedit** | Not supported (server renders everything) | Full preedit sync protocol | Multi-client IME composition visibility |
| **Threading model** | Multi-threaded (screen, PTY, plugin, writer threads) | Multi-threaded (similar) | Comparable; libitshell3 follows zellij's proven pattern |
| **Plugins** | WASM-based plugin system | Not in scope for v1 | Reduced complexity; plugins can be added later |
| **Client complexity** | Thin (receive ANSI, render via termios) | Moderate (receive cell data, GPU render via Metal) | More work per client, but enables hardware-accelerated rendering and client-specific optimizations |

### 8.3 vs. iTerm2 tmux -CC Integration

| Aspect | iTerm2 + tmux -CC | libitshell3 | Improvement |
|--------|-------------------|-------------|-------------|
| **Protocol** | Text-based `%`-prefixed notifications over PTY | Binary framing over Unix socket | Structured, typed, efficient. No text escaping overhead. |
| **Output encoding** | Octal-escaped terminal output in `%output` | Structured cell data in `FrameUpdate` | No escape/unescape overhead. Client renders directly. |
| **Input forwarding** | `send-keys` commands with character batching | `KeyInput` with HID keycode | Direct, no command overhead, preserves modifier information |
| **CJK preedit** | None (inherits tmux limitations) | Native preedit sync | Full IME composition support |
| **Session recovery** | FileDescriptorServer + Mach namespace tricks | Daemon with auto-reconnect + RenderState replay | Simpler, no macOS-specific tricks required. State resync via FrameUpdate with `dirty=full`. |

---

## 9. Implementation Notes

### 9.1 Zig Struct Definitions

The header can be represented in Zig as:

```zig
pub const FrameHeader = extern struct {
    magic: [2]u8 = .{ 0x49, 0x54 },  // "IT"
    version: u8 = 1,
    flags: FrameFlags,
    msg_type: u16 align(1),  // little-endian
    reserved: u16 = 0,
    payload_len: u32 align(1),  // little-endian
    sequence: u32 align(1),  // little-endian

    pub const SIZE: usize = 16;

    pub const FrameFlags = packed struct(u8) {
        compressed: bool = false,
        response: bool = false,
        err: bool = false,
        more_fragments: bool = false,
        _reserved: u4 = 0,
    };
};
```

### 9.2 Reader Loop Pseudocode

```
fn readMessage(stream) -> Message:
    header_buf = stream.readExact(16)
    if header_buf[0..2] != [0x49, 0x54]:
        return Error(ERR_BAD_MAGIC)
    header = parseHeader(header_buf)
    if header.version != PROTOCOL_VERSION:
        return Error(ERR_UNSUPPORTED_VERSION)
    if header.payload_len > MAX_PAYLOAD_SIZE:
        return Error(ERR_PAYLOAD_TOO_LARGE)
    payload = stream.readExact(header.payload_len)
    if header.flags.compressed:
        payload = zstd.decompress(payload)
    return dispatch(header.msg_type, header, payload)
```

### 9.3 Design Decisions Needing Validation

| Decision | Status | Notes |
|----------|--------|-------|
| 16-byte header with magic | **Proposed** | 2-byte magic may be insufficient for stream re-sync after corruption. 4-byte magic would be safer but wastes 2 bytes per message. Given `SOCK_STREAM` reliability, 2 bytes is likely sufficient. |
| zstd compression | **Proposed** | Zig has built-in zstd support (`std.compress.zstd`). Needs benchmarking to confirm it's worthwhile over Unix sockets. Likely only matters for TCP/TLS. |
| u32 sequence numbers | **Proposed** | At 1000 messages/second, wraps after ~49 days. Sufficient for a session. Alternative: u64 for effectively infinite range at +4 bytes per header. |
| Little-endian everywhere | **Decided** | All target platforms are little-endian. If a big-endian platform is ever needed, the protocol requires explicit endian conversion (standard practice). |
| No TLV (tag-length-value) for payload fields | **Proposed** | Fixed layouts are faster to parse but harder to extend. TLV is more flexible but slower. Decision: use fixed layouts for performance-critical messages (FrameUpdate, KeyInput), consider TLV for extensible messages (capabilities, config). |
