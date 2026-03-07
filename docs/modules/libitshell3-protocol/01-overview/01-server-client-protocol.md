# Server-Client Protocol Analysis

## Overview

This document analyzes the server-client protocol designs from three reference implementations (tmux, zellij, cmux) and the three standalone protocol specification documents to inform it-shell3's protocol design.

## Reference Documents

- `~/dev/git/references/TMUX_CLIENT_PROTOCOL_ANALYSIS.md` — Complete tmux client protocol spec (700 lines)
- `~/dev/git/references/tmux-server-protocol-analysis.md` — Complete tmux server protocol spec (818 lines)
- `~/dev/git/references/design-cjk-protocol-extensions.md` — CJK protocol extension design (810 lines)

---

## 1. tmux Protocol (Protocol Version 8)

### Transport Layer

- **Socket Type**: `AF_UNIX`, `SOCK_STREAM` (reliable, ordered byte stream)
- **Socket Path**: `~/.config/tmux/default` (or `$TMUX_TMPDIR/<uid>/default`)
- **Permissions**: Socket inherits umask; ACL possible via server flag

### Message Framing

tmux uses OpenBSD's `imsg/imsgbuf` library for message framing:

```c
struct imsg_hdr {
    uint32_t type;     // Message type enum
    uint16_t flags;    // IMSG_HEADER_SIZE marker
    uint16_t peerid;   // Low byte = protocol version (8)
    uint32_t pid;      // Sender PID
    uint32_t uid;      // Sender UID (for auth)
    uint16_t len;      // Total message length (header + data)
};
```

- Every message includes the protocol version in `peerid & 0xff`
- Messages are read/written via `imsg_read()` / `imsg_compose()` / `imsg_flush()`
- The library handles partial reads/writes and buffering

### Client Identification Sequence

After connecting, the client sends exactly 11 identification messages **in this order**:

| Order | Message | Value |
|-------|---------|-------|
| 1 | `MSG_IDENTIFY_FLAGS` (100) | Client flags bitfield |
| 2 | `MSG_IDENTIFY_TERM` (101) | `$TERM` value |
| 3 | `MSG_IDENTIFY_TTYNAME` (102) | TTY device path |
| 4 | `MSG_IDENTIFY_CWD` (103) | Working directory |
| 5 | `MSG_IDENTIFY_STDIN` (104) | stdin FD (via cmsg) |
| 6 | `MSG_IDENTIFY_ENVIRON` (105) | Environment variables (one per msg) |
| 7 | `MSG_IDENTIFY_CLIENTPID` (106) | Client PID |
| 8 | `MSG_IDENTIFY_TERMINFO` (107) | Terminal capabilities |
| 9 | `MSG_IDENTIFY_FEATURES` (108) | Extended terminal features |
| 10 | `MSG_IDENTIFY_LONGFLAGS` (109) | Extended flags (string) |
| 11 | `MSG_IDENTIFY_DONE` (110) | End of identification |

**FD Passing**: stdin and stdout file descriptors are passed via `sendmsg(2)` cmsg ancillary data. This allows the server to directly control the client's terminal.

### Client Flags

```c
#define IDENTIFY_UTF8           0x1    // Client supports UTF-8
#define IDENTIFY_256COLOURS     0x2    // Client supports 256 colors
#define IDENTIFY_CONTROL        0x4    // Control mode (-C)
#define IDENTIFY_TERMINALFEATURES 0x8  // Features detection available
#define IDENTIFY_SIXEL          0x10   // Sixel graphics support
#define IDENTIFY_CONTROL_NOTIFY 0x20   // Control mode with notifications (-CC)
```

### Command Messages

```c
// Client -> Server
MSG_COMMAND (200): {
    int argc;                  // Argument count
    // Followed by packed null-terminated strings:
    // "command\0arg1\0arg2\0"
}

// Server -> Client responses
MSG_READY   (201): Server is ready
MSG_EXIT    (202): Client should exit (with optional message)
MSG_SHELL   (204): Default shell path
MSG_VERSION (12):  Server version string
MSG_FLAGS   (205): Updated flags
```

### Control Mode Protocol

When a client connects with `IDENTIFY_CONTROL` flag (tmux -C or -CC):

- Terminal output is replaced with structured text notifications
- All notifications are prefixed with `%`

**Key control mode notifications:**

```
%output <pane-id> <base64-encoded-data>     # Terminal output
%pane-mode-changed <pane-id>                # Mode change (copy, etc.)
%window-pane-changed <window-id> <pane-id>  # Active pane changed
%session-changed $<session-id> <name>       # Session switched
%layout-change <window-id> <layout-string>  # Window layout changed
%window-add <window-id>                     # Window created
%window-close <window-id>                   # Window destroyed
%exit [reason]                              # Server disconnect
%pause <pane-id>                            # Backpressure: pause output
%continue <pane-id>                         # Backpressure: resume output
```

**Backpressure mechanism:**
- `CONTROL_MAXIMUM_AGE` = 300 seconds
- Per-pane output queuing with age tracking
- `%pause` sent when queue overflows; `%continue` when drained

### File I/O Messages

```
MSG_READ_OPEN   (300): Open file for reading
MSG_READ        (301): Read data chunk
MSG_READ_DONE   (302): Read complete
MSG_READ_CANCEL (303): Cancel read
MSG_WRITE_OPEN  (306): Open file for writing
MSG_WRITE       (307): Write data chunk
MSG_WRITE_READY (308): Ready for next chunk
MSG_WRITE_CLOSE (309): Close write
```

---

## 2. Zellij Protocol

### Transport Layer

- **Library**: `interprocess` crate (cross-platform local IPC)
- **Platform**: Uses platform-native local sockets (Unix domain sockets on macOS/Linux)
- **Serialization**: Protobuf via `prost` crate

### Client-to-Server Messages (16 types)

Defined in `zellij-utils/src/client_server_contract/client_to_server.proto` and `zellij-utils/src/ipc.rs`:

```rust
pub enum ClientToServerMsg {
    // Session lifecycle
    FirstClientConnected,          // Initial client
    AttachClient(ClientAttributes, Options, Option<usize>, Option<PluginIds>),
    DetachSession(Vec<ClientId>),
    ClientExited,

    // Input
    TerminalResize(Size),          // Terminal size changed
    Key(Vec<KeyWithModifier>, Vec<u8>, bool),  // Key event with raw bytes + kitty flag
    Action(Action, Option<u32>, Option<ClientId>),  // Named action

    // Queries
    ListClientsMetadata,
    CliPipeInput(PipeMessage),
    ConnStatus,
    TerminalPixelDimensions(TerminalPixelDimensions),
}
```

### Server-to-Client Messages (13 types)

```rust
pub enum ServerToClientMsg {
    // Rendering
    Render(String),                // Full screen content as terminal output string

    // Lifecycle
    Connected,
    Exit(ExitReason),
    SwitchSession(ConnectToSession),
    UnblockInputThread,

    // Status
    Log(Vec<String>),
    LogError(Vec<String>),
    CliPipeOutput(PipeMessage),
    QueryTerminalSize,
    SessionId(u64),
}
```

### Internal Message Bus (Multi-Thread Architecture)

Zellij's server uses separate threads communicating via typed channels:

```
┌─────────────────────────────────────────────────┐
│                  Server Thread                   │
│  (route.rs: routes ClientToServerMsg)            │
├─────────────┬──────────────┬────────────────────┤
│             │              │                     │
▼             ▼              ▼                     ▼
Screen Thread  PTY Thread    Plugin Thread    PTY Writer Thread
(rendering,    (pty mgmt,    (WASM plugins,   (write to PTY
 tabs, panes)  spawn/close)  lifecycle)        FDs, resize)
```

Each thread has a typed `SenderWithContext` for its instruction enum:
- `ScreenInstruction` — Tab/pane/layout operations
- `PtyInstruction` — Spawn, close, re-run terminals
- `PluginInstruction` — Plugin lifecycle, events
- `PtyWriteInstruction` — Write bytes to PTY FDs
- `BackgroundJob` — Session serialization, crash reports

### Key Design Difference from tmux

| Aspect | tmux | zellij |
|--------|------|--------|
| Rendering | Server sends raw terminal data per-pane | Server sends pre-rendered full screen string |
| Transport | imsg binary framing | Protobuf serialization |
| Threading | Single event-loop (libevent) | Multi-threaded with typed channels |
| Plugins | None | WASM-based plugin system |
| Protocol | Binary, compact | Protobuf, extensible |

---

## 3. cmux Control Interface

### Transport

- **Socket**: Unix domain socket at `/tmp/cmux.sock`
- **Format**: Text-based command protocol
- **Direction**: External tool → cmux app (one-way commands)

### Command Protocol (v1 → v2 Evolution)

**v1 (Simple Commands):**
```
focus_window
split_horizontal
split_vertical
send_keys <text>
```

**v2 (Namespaced Methods):**
```
workspace.select <uuid>
pane.focus <uuid>
window.create
browser.open <url>
```

### Handle Reference System

cmux maintains UUID-based handles for:
- Windows
- Workspaces
- Panes (terminal or browser)
- Surfaces (ghostty terminal instances)

### Focus Safety Policy

Socket commands must not steal macOS app focus unless they are explicit focus-intent commands. This prevents scripted operations from disrupting the user's current context.

---

## 4. CJK Protocol Extensions (Design Document)

**Source**: `~/dev/git/references/design-cjk-protocol-extensions.md`

This is the most critical reference for it-shell3's CJK requirements.

### New Message Types

| ID | Message | Purpose |
|----|---------|---------|
| 114 | `MSG_IDENTIFY_CJK_CAPS` | CJK capability negotiation |
| 115 | (Reserved) | Future CJK extensions |
| 311 | `MSG_PREEDIT_START` | IME composition begins |
| 312 | `MSG_PREEDIT_UPDATE` | IME composition state update |
| 313 | `MSG_PREEDIT_END` | IME composition ends |
| 314 | `MSG_CJK_CONFIG` | CJK configuration sync |

### Capability Negotiation

```c
// Sent during identification phase (after MSG_IDENTIFY_LONGFLAGS)
MSG_IDENTIFY_CJK_CAPS (114): {
    uint32_t cjk_capabilities;  // Bitflags:
    // CJK_CAP_PREEDIT        = 0x01  // IME preedit sync
    // CJK_CAP_AMBIGUOUS_WIDTH = 0x02  // Ambiguous width config
    // CJK_CAP_DOUBLE_WIDTH   = 0x04  // Double-width chars
    // CJK_CAP_CONTROL_MODE   = 0x08  // Control mode extensions
}
```

### Preedit Message Flow

```
┌──────────┐                    ┌──────────┐
│  Client   │                    │  Server   │
│  (macOS)  │                    │  (Daemon) │
└─────┬─────┘                    └─────┬─────┘
      │                                │
      │  User starts typing Korean     │
      │  "한" = ㅎ → 하 → 한           │
      │                                │
      ├─── MSG_PREEDIT_START ─────────>│
      │    {pane_id, cursor_pos}       │
      │                                │
      ├─── MSG_PREEDIT_UPDATE ────────>│  User types ㅎ
      │    {pane_id, "ㅎ", cursor_pos} │
      │                                │
      ├─── MSG_PREEDIT_UPDATE ────────>│  User types ㅏ → 하
      │    {pane_id, "하", cursor_pos} │
      │                                │
      ├─── MSG_PREEDIT_UPDATE ────────>│  User types ㄴ → 한
      │    {pane_id, "한", cursor_pos} │
      │                                │
      ├─── MSG_PREEDIT_END ───────────>│  User presses space
      │    {pane_id, "한"}             │
      │                                │
```

### Korean Backspace Behavior (Jamo Decomposition)

Critical: Backspace during Korean composition decomposes characters:
- `한` → backspace → `하` (remove ㄴ)
- `하` → backspace → `ㅎ` (remove ㅏ)
- `ㅎ` → backspace → (empty, composition ends)

This requires the server to understand Jamo decomposition to correctly render the preedit state for non-primary clients.

### Control Mode Extensions

```
%preedit-begin <pane-id> <cursor-x> <cursor-y>
%preedit-update <pane-id> <base64-text> <cursor-x> <cursor-y>
%preedit-end <pane-id> [<base64-committed-text>]
%cjk-config <key> <value>
```

### Rendering Strategy Comparison

| Strategy | Description | Recommendation |
|----------|-------------|----------------|
| Client-only | Only rendering client shows preedit | Too limited |
| **Server-aware (Full Sync)** | Server tracks preedit state, syncs to all clients | **Recommended** |
| Hybrid | Client renders locally, server stores metadata | Compromise |

**Strategy 2 (Server-Aware Full Sync) is recommended** because:
- All attached clients see consistent IME state
- Server can correctly handle scrollback with active preedit
- Enables session handoff between devices mid-composition

### Graceful Fallback Matrix

| Client | Server | Behavior |
|--------|--------|----------|
| Enhanced | Enhanced | Full CJK preedit sync |
| Enhanced | Vanilla | Client-local preedit only |
| Vanilla | Enhanced | Standard terminal input |
| Vanilla | Vanilla | Standard terminal input |

---

## Implications for it-shell3 Protocol Design

### Recommended Approach

1. **Transport**: Unix domain socket (`AF_UNIX, SOCK_STREAM`)
   - Proven by tmux (decades of reliability)
   - Supports FD passing for advanced use cases
   - Fast (no network overhead)

2. **Serialization**: Consider Protobuf or FlatBuffers
   - More extensible than tmux's hand-rolled binary format
   - Schema evolution without breaking compatibility
   - Better for CJK extension messages (variable-length UTF-8 data)

3. **Control Mode**: Text-based structured protocol for programmatic clients
   - Enables iTerm2-style native integration
   - Enables iOS client without binary protocol parsing

4. **CJK Extensions**: Implement from design doc
   - Capability negotiation during handshake
   - Preedit sync messages with full Jamo decomposition support
   - Ambiguous-width configuration sync

5. **Architecture**: Dedicated threads/tasks for:
   - Client connection management
   - PTY I/O (per-pane)
   - Screen rendering / state tracking
   - CJK preedit state management
