# Protocol Overview and Message Framing

**Status**: Draft v0.2
**Date**: 2026-03-04
**Scope**: libitshell3 server-client wire protocol — transport, framing, message types, lifecycle, error handling
**Changes from v0.1**: Applied review resolutions — fixed preedit directions, removed Tab concept, fixed sequence number semantics, unified message type ranges, confirmed 16-byte header and u32 IDs as canonical

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

2. **Server-authoritative state.** The daemon owns terminal state (PTY, scrollback, preedit, cursor). Clients are thin renderers that receive state updates and forward raw input. This simplifies multi-client consistency. The server owns the native IME engine (libitshell3-ime) — clients never perform composition.

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
 8      4     payload_len    Payload length in bytes (little-endian u32, NOT including header)
12      4     sequence       Sequence number (little-endian u32)
```

**Total header size: 16 bytes** (naturally aligned for 4-byte fields)

**Important**: `payload_len` is the size of the payload only. Total bytes on the wire = 16 + payload_len. The 2-byte reserved field provides natural 4-byte alignment for `payload_len` and `sequence`, and room for future routing or flag fields.

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

Each connection direction (client-to-server, server-to-client) maintains its own sequence counter, starting at 1.

**Sequence 0 is never sent on the wire.** It is used only as a sentinel value in payload fields (e.g., `ref_sequence = 0` in Error messages means "no specific message triggered this error").

All message types — requests, responses, and notifications — use sequence numbers as follows:

| Message type | Sequence number | RESPONSE flag |
|--------------|-----------------|---------------|
| Request | Sender's next monotonic seq | 0 |
| Response | Echo the request's sequence number | 1 |
| Notification | Sender's next monotonic seq | 0 |
| Error response | Echo offending request's seq | 1 (RESPONSE + ERROR both set) |

Notifications are distinguished from requests by their message type (notification types such as `LayoutChanged`, `PaneMetadataChanged`, etc. are never used as request/response pairs).

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

Message type IDs are 16-bit unsigned integers (`u16`), allocated in ranges by functional category.

### 4.1 Allocation Ranges

| Range | Category | Specification |
|-------|----------|---------------|
| `0x0000` | Reserved | Never used |
| `0x0001 - 0x00FF` | **Handshake & Lifecycle** | Doc 02 |
| `0x0100 - 0x01FF` | **Session & Pane Management** | Doc 03 |
| `0x0200 - 0x02FF` | **Input Forwarding** | Doc 04 |
| `0x0300 - 0x03FF` | **Render State** | Doc 04 |
| `0x0400 - 0x04FF` | **CJK & IME** | Doc 05 |
| `0x0500 - 0x05FF` | **Flow Control & Backpressure** | Doc 06 |
| `0x0600 - 0x06FF` | **Clipboard** | Doc 06 |
| `0x0700 - 0x07FF` | **Persistence (snapshot/restore)** | Doc 06 |
| `0x0800 - 0x08FF` | **Notifications & Subscriptions** | Doc 06 |
| `0x0900 - 0x09FF` | **Heartbeat & Connection Health** | Doc 06 |
| `0x0A00 - 0x0AFF` | **Extension Negotiation** | Doc 06 |
| `0x0B00 - 0x0FFF` | **Reserved for future** | Future protocol extensions |
| `0xF000 - 0xFFFE` | **Vendor extensions** | Third-party extensions (not part of core protocol) |
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

#### Session & Pane Management (`0x0100 - 0x01FF`)

See doc 03 for detailed message specifications. Summary of key messages:

| ID | Name | Direction | Description |
|----|------|-----------|-------------|
| `0x0100` | `CreateSessionRequest` | C→S | Create a new session |
| `0x0101` | `CreateSessionResponse` | S→C | Session creation confirmation with session_id, pane_id |
| `0x0102` | `ListSessionsRequest` | C→S | List available sessions |
| `0x0103` | `ListSessionsResponse` | S→C | Session list |
| `0x0104` | `AttachSessionRequest` | C→S | Attach to an existing session |
| `0x0105` | `AttachSessionResponse` | S→C | Attach confirmation with layout and state |
| `0x0106` | `DetachSessionRequest` | C→S | Detach from current session |
| `0x0107` | `DetachSessionResponse` | S→C | Detach confirmation |
| `0x0108` | `DestroySessionRequest` | C→S | Destroy a session |
| `0x0109` | `DestroySessionResponse` | S→C | Destroy confirmation |
| `0x010A` | `RenameSessionRequest` | C→S | Rename a session |
| `0x010B` | `RenameSessionResponse` | S→C | Rename confirmation |
| `0x0140` | `CreatePaneRequest` | C→S | Create a standalone pane |
| `0x0142` | `SplitPaneRequest` | C→S | Split an existing pane |
| `0x0144` | `ClosePaneRequest` | C→S | Close a pane |
| `0x0146` | `FocusPaneRequest` | C→S | Set focused pane |
| `0x0148` | `NavigatePaneRequest` | C→S | Move focus in a direction |
| `0x014A` | `ResizePaneRequest` | C→S | Adjust split divider |
| `0x014C` | `EqualizeSplitsRequest` | C→S | Equalize all splits in a session |
| `0x014E` | `ZoomPaneRequest` | C→S | Toggle pane zoom |
| `0x0150` | `SwapPanesRequest` | C→S | Swap two panes in layout |
| `0x0152` | `LayoutGetRequest` | C→S | Query current layout tree |
| `0x0180` | `LayoutChanged` | S→C | Layout tree updated (notification) |
| `0x0181` | `PaneMetadataChanged` | S→C | Pane metadata updated (notification) |
| `0x0182` | `SessionListChanged` | S→C | Session list changed (notification) |
| `0x0190` | `WindowResize` | C→S | Client window resized |

**Note**: There is no Tab as a protocol entity in libitshell3. The protocol hierarchy is **Daemon > Session(s) > Pane tree (binary splits)**. Each Session has one layout tree. The client UI presents Sessions as tabs:

| UI action | Protocol message |
|-----------|-----------------|
| New tab | `CreateSessionRequest` (0x0100) |
| Close tab | `DestroySessionRequest` (0x0108) — closes the session and all its panes |
| Switch tab | Client-local: switch which Session's render state is displayed |
| Rename tab | `RenameSessionRequest` (0x010A) |

See doc 03 for full details.

#### Input Forwarding (`0x0200 - 0x02FF`)

See doc 04 for detailed message specifications.

| ID | Name | Direction | Description |
|----|------|-----------|-------------|
| `0x0200` | `KeyEvent` | C→S | Raw HID keycode + modifiers + layout ID |
| `0x0201` | `TextInput` | C→S | Direct UTF-8 text insertion (bypasses IME) |
| `0x0202` | `MouseButton` | C→S | Mouse button press/release |
| `0x0203` | `MouseMove` | C→S | Mouse motion (rate limited) |
| `0x0204` | `MouseScroll` | C→S | Scroll wheel / trackpad |
| `0x0205` | `PasteData` | C→S | Clipboard paste (chunked) |
| `0x0206` | `FocusEvent` | C→S | Window focus gained/lost |

#### Render State (`0x0300 - 0x03FF`)

See doc 04 for detailed message specifications.

| ID | Name | Direction | Description |
|----|------|-----------|-------------|
| `0x0300` | `FrameUpdate` | S→C | RenderState delta or full update (includes preedit section) |
| `0x0301` | `ScrollRequest` | C→S | Scroll viewport |
| `0x0302` | `ScrollPosition` | S→C | Current scroll position |
| `0x0303` | `SearchRequest` | C→S | Search in scrollback |
| `0x0304` | `SearchResult` | S→C | Search results |
| `0x0305` | `SearchCancel` | C→S | Cancel active search |

#### CJK & IME (`0x0400 - 0x04FF`)

See doc 05 for detailed message specifications. The server owns the native IME engine (libitshell3-ime). Clients send raw HID keycodes via KeyEvent; the server pushes composition state to all attached clients.

| ID | Name | Direction | Description |
|----|------|-----------|-------------|
| `0x0400` | `PreeditStart` | **S→C** | Server notifies that IME composition began |
| `0x0401` | `PreeditUpdate` | **S→C** | Server pushes current composition state to all clients |
| `0x0402` | `PreeditEnd` | **S→C** | Server notifies composition committed or cancelled |
| `0x0403` | `PreeditSync` | S→C | Full preedit snapshot for late-joining clients |
| `0x0404` | `InputMethodSwitch` | C→S | Client requests keyboard layout change |
| `0x0405` | `InputMethodAck` | S→C | Server confirms layout change |
| `0x0406` | `AmbiguousWidthConfig` | Bidirectional | Ambiguous-width character configuration |
| `0x04FF` | `IMEError` | S→C | Error response for CJK/IME operations |

**Preedit dual-channel design**: Preedit state is communicated through two channels:
1. **FrameUpdate preedit section** (in 0x0300): For rendering — where to draw the overlay. Coalesced at frame rate.
2. **Dedicated preedit messages** (0x0400-0x0402): For state tracking — composition state, ownership, conflict resolution. Not coalesced; full event sequence preserved.

Clients MUST use FrameUpdate's preedit section for rendering. Dedicated preedit messages provide metadata only.

#### Flow Control & Backpressure (`0x0500 - 0x05FF`)

See doc 06 for detailed message specifications.

#### Clipboard (`0x0600 - 0x06FF`)

See doc 06 for detailed message specifications.

#### Persistence (`0x0700 - 0x07FF`)

See doc 06 for detailed message specifications.

#### Notifications & Subscriptions (`0x0800 - 0x08FF`)

See doc 06 for detailed message specifications.

#### Heartbeat & Connection Health (`0x0900 - 0x09FF`)

See doc 06 for detailed message specifications.

#### Extension Negotiation (`0x0A00 - 0x0AFF`)

See doc 06 for detailed message specifications.

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
 4      4     ref_sequence     Sequence number of the message that caused the error
                               (0 if unsolicited — no specific message triggered this error)
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
| **Session/Pane IDs** | u32, assigned by server, monotonically increasing | Server-authoritative. Never reused during a daemon's lifetime. |

---

## 8. Comparison with Existing Protocols

### 8.1 vs. tmux

| Aspect | tmux | libitshell3 | Improvement |
|--------|------|-------------|-------------|
| **Framing** | OpenBSD `imsg` (14 bytes, coupled to `sendmsg`) | Custom 16-byte header with magic, version, sequence | Portable (no imsg dependency), magic bytes for stream alignment, sequence numbers for debugging |
| **Serialization** | Hand-rolled C structs, packed with `#pragma pack` | Explicit field layouts with little-endian encoding | Cross-language safe, no padding/alignment surprises |
| **Capability negotiation** | Protocol version in `peerid & 0xff`; features guessed from version | Explicit `ClientHello`/`ServerHello` with feature flag bitmasks | No version guessing. Capabilities are declared, not inferred. |
| **CJK support** | None | First-class: server-side IME with `PreeditStart/Update/End` (S→C), `PreeditSync` | Enables IME composition across multiplexed sessions |
| **Input forwarding** | `send-keys` text command via control mode | Binary `KeyEvent` message with HID keycode, modifiers, layout ID | Lower latency, richer key info (modifier disambiguation, layout awareness) |
| **Rendering** | Raw VT bytes per-pane (client re-parses) | Structured `FrameUpdate` with resolved styles, dirty tracking | No redundant VT parse; delta updates reduce bandwidth 10x for typical cases |
| **Error handling** | `MSG_EXIT` with optional text | Structured `Error` with error codes, ref sequence, detail | Programmatic error handling, not string parsing |
| **Flow control** | `%pause` / `%continue` (control mode only) | Binary `PausePane` / `ContinuePane` / flow control config | Available in all modes, bidirectional, configurable |
| **Extensibility** | Fixed message type enum in C header | Ranged type IDs with reserved ranges for future categories | Can add new message categories without ID conflicts |

### 8.2 vs. zellij

| Aspect | zellij | libitshell3 | Improvement |
|--------|--------|-------------|-------------|
| **Serialization** | Protobuf via `prost` | Custom binary framing | Fewer dependencies; Protobuf is heavy for a system-level IPC protocol. Schema evolution handled by capability negotiation + reserved ranges instead. |
| **Rendering model** | Server sends pre-rendered ANSI strings (`Render(String)`) | Server sends structured `FrameUpdate` with cell data | Client can optimize rendering (GPU batching, font caching). No redundant ANSI parsing. |
| **CJK preedit** | Not supported (server renders everything) | Full server-side IME with preedit sync protocol | Multi-client IME composition visibility |
| **Threading model** | Multi-threaded (screen, PTY, plugin, writer threads) | Multi-threaded (similar) | Comparable; libitshell3 follows zellij's proven pattern |
| **Plugins** | WASM-based plugin system | Not in scope for v1 | Reduced complexity; plugins can be added later |
| **Client complexity** | Thin (receive ANSI, render via termios) | Moderate (receive cell data, GPU render via Metal) | More work per client, but enables hardware-accelerated rendering and client-specific optimizations |

### 8.3 vs. iTerm2 tmux -CC Integration

| Aspect | iTerm2 + tmux -CC | libitshell3 | Improvement |
|--------|-------------------|-------------|-------------|
| **Protocol** | Text-based `%`-prefixed notifications over PTY | Binary framing over Unix socket | Structured, typed, efficient. No text escaping overhead. |
| **Output encoding** | Octal-escaped terminal output in `%output` | Structured cell data in `FrameUpdate` | No escape/unescape overhead. Client renders directly. |
| **Input forwarding** | `send-keys` commands with character batching | `KeyEvent` with HID keycode | Direct, no command overhead, preserves modifier information |
| **CJK preedit** | None (inherits tmux limitations) | Native server-side IME with preedit sync | Full IME composition support |
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
| 16-byte header with magic | **Decided** | 2-byte reserved field provides alignment and future extensibility. |
| zstd compression | **Proposed** | Zig has built-in zstd support (`std.compress.zstd`). Needs benchmarking to confirm it's worthwhile over Unix sockets. Likely only matters for TCP/TLS. |
| u32 sequence numbers | **Proposed** | At 1000 messages/second, wraps after ~49 days. Sufficient for a session. Alternative: u64 for effectively infinite range at +4 bytes per header. |
| Little-endian everywhere | **Decided** | All target platforms are little-endian. If a big-endian platform is ever needed, the protocol requires explicit endian conversion (standard practice). |
| u32 IDs (not UUID) | **Decided** | Wire-efficient (4 bytes vs 16). UUIDs used only in persistence snapshots for cross-restart identity. |
| No Tab protocol entity | **Decided** | Hierarchy is Daemon > Session > Pane tree. The client UI presents Sessions as tabs (new tab = CreateSession, close tab = DestroySession, switch tab = client-local display switch, rename tab = RenameSession). Tab functionality is fully preserved in the UI; only the intermediate Tab object between Session and Pane is removed from the protocol. |
| Preedit direction S→C | **Decided** | Server owns native IME. Clients send raw HID keycodes only. |
| No TLV (tag-length-value) for payload fields | **Proposed** | Fixed layouts are faster to parse but harder to extend. TLV is more flexible but slower. Decision: use fixed layouts for performance-critical messages (FrameUpdate, KeyEvent), consider TLV for extensible messages (capabilities, config). |
