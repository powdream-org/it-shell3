# Daemon Debug Subsystem

- **Date**: 2026-03-26
- **Scope**: TCP-based debug interface for logging, inspection, and control of
  the it-shell3-daemon process

## 1. Overview

The daemon debug subsystem provides a text-based TCP interface for observing and
controlling the daemon without a client app. It serves three audiences:
developers, AI agents, and end users filing bug reports.

**ADR**: `docs/adr/00053-daemon-embedded-debug-subsystem.md`

### 1.1 Design Goals

- **Machine-readable**: JSONL log output parseable by AI agents and scripts
- **Human-friendly**: Plain text commands typeable via `nc` or `echo | nc`
- **Zero overhead when disabled**: No TCP listener, no log emit cost
- **Release-build compatible**: Works in all build modes
- **Client-free testing**: Inject inputs and inspect screen state directly

### 1.2 Non-Goals

- Log viewer / TUI dashboard (YAGNI)
- Remote debugging without SSH tunnel
- Authentication beyond localhost + env var gating
- Application-layer encryption on the debug port

## 2. Architecture

```
+-- daemon process ----------------------------------------+
|                                                          |
|  +-- event loop (kqueue/epoll) ------------------------+ |
|  |                                                     | |
|  |  Unix socket     PTY fds     Signals                | |
|  |  (clients)       (panes)     (SIGCHLD)              | |
|  |                                                     | |
|  |  TCP debug port                                     | |
|  |  (if IT_SHELL3_DEBUG_PORT is set)                   | |
|  |                                                     | |
|  |  +----------------+  +--------------+               | |
|  |  | CommandParser  |  | LogEmitter   |               | |
|  |  | text->dispatch |  | event->file  |               | |
|  |  +-------+--------+  +--------------+               | |
|  |          |                                          | |
|  |  +-------v--------+  +--------------+               | |
|  |  | Inspector      |  | Controller   |               | |
|  |  | dump/stats     |  | create/      |               | |
|  |  | (read-only)    |  | inject/etc   |               | |
|  |  +----------------+  +--------------+               | |
|  |                                                     | |
|  +-----------------------------------------------------+ |
|                                                          |
+----------------------------------------------------------+
```

### 2.1 Activation

```bash
# Enabled — TCP listener on localhost:9090
IT_SHELL3_DEBUG_PORT=9090 it-shell3-daemon --socket-path /tmp/it-shell3.sock

# Disabled (default) — no listener, no overhead
it-shell3-daemon --socket-path /tmp/it-shell3.sock
```

### 2.2 Connection Model

Single-command request-response. Each TCP connection handles exactly one
command:

1. Accept
2. Read one line (command, max 8 KiB)
3. Parse and execute
4. Write response (plain text or JSONL lines, terminated by `done`)
5. Close

No persistent connections. No concurrent command execution — the event loop
processes one debug command per iteration, synchronously.

**Daemon-side state**: Logging commands (`set-log-file`, `subscribe`) mutate
daemon-wide state that persists across connections. The connection itself is
stateless (no per-connection tracking), but the daemon remembers the active log
file and subscribed tags until `stop-logging` is called or the daemon exits.

### 2.3 Security

- Bind to `127.0.0.1` only (no `0.0.0.0`)
- Environment variable opt-in — no env var, no listener
- Log files created with mode `0600`
- Remote access via SSH tunnel (`ssh -L 9090:localhost:9090`)
- No additional authentication (YAGNI for localhost same-user access)

## 3. Command Reference

### 3.1 Response Format

- **Success**: `ok` or `ok key:value` (single-line)
- **Error**: `error: <message>` (single-line)
- **Multi-line**: JSONL (one JSON object per line) terminated by `done`

### 3.2 Logging Commands

| Command               | Response                   | Description                                                                                                                           |
| --------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `list-tags`           | Tag list with descriptions | Available log tags and their meaning                                                                                                  |
| `set-log-file <path>` | `ok`                       | Set log output file. Replaces previous file if any                                                                                    |
| `subscribe <tags>`    | `ok`                       | Activate tags (comma-separated, cumulative). Supports `:verbose`. Subscribing an already-active tag is a no-op (`ok`)                 |
| `unsubscribe <tags>`  | `ok`                       | Deactivate tags (comma-separated). Unsubscribing `error` returns `error: cannot unsubscribe error tag`                                |
| `list-subscriptions`  | Active tag list            | Currently subscribed tags                                                                                                             |
| `stop-logging`        | `ok`                       | Close log file and clear all subscriptions (except `error`). After this, `error` tag events are discarded until a new log file is set |

### 3.3 Inspection Commands

| Command                                    | Response       | Description                                                 |
| ------------------------------------------ | -------------- | ----------------------------------------------------------- |
| `dump-sessions`                            | JSONL + `done` | All sessions with pane list and attached client count       |
| `dump-session <id>`                        | JSONL + `done` | Session detail: pane tree, split ratios                     |
| `dump-clients`                             | JSONL + `done` | Client list with attached session and capabilities          |
| `dump-pane <pane_id>`                      | JSONL + `done` | Pane state: pid, pty_fd, running, pty_eof, dimensions, etc. |
| `dump-screen <pane_id>`                    | JSONL + `done` | Full screen: one JSON line per row (text + cells)           |
| `dump-screen <pane_id> rows:<start>-<end>` | JSONL + `done` | Specific row range (clamped to actual screen dimensions)    |
| `stats`                                    | JSONL + `done` | Event loop statistics                                       |
| `list-hid-keys`                            | Key name list  | All available HID key names for `inject-key`                |

### 3.4 Control Commands

| Command                                           | Response              | Description                                |
| ------------------------------------------------- | --------------------- | ------------------------------------------ |
| `create-session [name]`                           | `ok session_id:<id>`  | Create a new session                       |
| `destroy-session <id>`                            | `ok`                  | Destroy session and all its panes          |
| `split-pane <pane_id> horizontal\|vertical`       | `ok new_pane_id:<id>` | Split a pane                               |
| `close-pane <pane_id>`                            | `ok`                  | Close a pane                               |
| `focus-pane <pane_id>`                            | `ok`                  | Set focused pane                           |
| `navigate-pane <pane_id> up\|down\|left\|right`   | `ok focused:<id>`     | Navigate to adjacent pane                  |
| `resize-pane <pane_id> <cols> <rows>`             | `ok`                  | Resize a pane                              |
| `inject-key <pane_id> <key_spec>`                 | `ok`                  | Press + release (see §3.5)                 |
| `inject-key-press <pane_id> <key_spec>`           | `ok`                  | Key press only                             |
| `inject-key-release <pane_id> <key_spec>`         | `ok`                  | Key release only                           |
| `inject-key-repeat <pane_id> <key_spec> <count>`  | `ok`                  | Repeat event N times (no auto-release)     |
| `inject-key-hold <pane_id> <key_spec> <count>`    | `ok`                  | Press + repeat×N + release                 |
| `inject-text <pane_id> <text>`                    | `ok`                  | Inject text string (see §3.6 for escaping) |
| `inject-mouse-click <pane_id> <x> <y> <button>`   | `ok`                  | Mouse press + release (see §3.5)           |
| `inject-mouse-press <pane_id> <x> <y> <button>`   | `ok`                  | Mouse press only                           |
| `inject-mouse-release <pane_id> <x> <y> <button>` | `ok`                  | Mouse release only                         |
| `inject-mouse-move <pane_id> <x> <y>`             | `ok`                  | Mouse move                                 |
| `inject-mouse-scroll <pane_id> up\|down [lines]`  | `ok`                  | Mouse scroll                               |
| `inject-paste <pane_id> <text>`                   | `ok`                  | Inject paste event (see §3.6 for escaping) |
| `switch-ime <session_id> <input_method>`          | `ok`                  | Switch input method (e.g. `ko-2set`)       |

### 3.5 Key and Mouse Specification

**Key spec format:** `[modifier+...]key_name`

Modifiers and key name are joined by `+` into a single token. The last
`+`-separated component is always the key name; all preceding components are
modifiers.

**Modifier names:**

| Canonical | Aliases          |
| --------- | ---------------- |
| `shift`   | —                |
| `ctrl`    | —                |
| `alt`     | `opt`, `option`  |
| `super`   | `cmd`, `command` |

Aliases are accepted in commands. Log output always uses canonical names.

**Mouse button:** `left`, `right`, `middle`

**Key command examples:**

```
inject-key 1 key_a                       → 'a' (press + release)
inject-key 1 shift+key_a                 → 'A'
inject-key 1 key_return                  → Enter
inject-key 1 ctrl+key_c                  → Ctrl+C (SIGINT)
inject-key 1 ctrl+key_z                  → Ctrl+Z (SIGTSTP)
inject-key 1 ctrl+key_l                  → Ctrl+L (clear)
inject-key 1 key_tab                     → Tab
inject-key 1 key_backspace               → Backspace
inject-key 1 key_up                      → Arrow up
inject-key 1 ctrl+shift+key_d            → Ctrl+Shift+D
inject-key 1 cmd+key_c                   → Super+C (macOS Command+C)
inject-key 1 opt+key_a                   → Alt+A (macOS Option+A)
inject-key-press 1 key_a                 → press only
inject-key-release 1 key_a               → release only
inject-key-repeat 1 key_a 5              → repeat event ×5 (no release)
inject-key-repeat 1 ctrl+key_a 5         → Ctrl+A repeat ×5
inject-key-hold 1 shift+key_j 10         → press + repeat×10 + release
```

HID key names follow ghostty's `Key` enum (lowercase, `key_` prefix). Use
`list-hid-keys` to see all available key names.

### 3.6 Text Argument Escaping

Commands that accept free-form text (`inject-text`, `inject-paste`) use the
following escaping rules:

- The text argument starts after the pane_id and extends to end of line
- Escape sequences: `\\` (literal backslash), `\n` (newline), `\t` (tab), `\xHH`
  (hex byte)
- No quoting required — the entire remainder of the line after pane_id is the
  text argument

Examples:

```
inject-text 1 hello world        → sends "hello world"
inject-text 1 line1\nline2       → sends "line1" + newline + "line2"
inject-text 1 path\\to\\file     → sends "path\to\file"
inject-text 1 \x1b[31mred\x1b[0m → sends ANSI red escape sequence
```

**Max command line length**: 8 KiB. Commands exceeding this are rejected with
`error: command too long`.

## 4. Log Format

Log output is JSONL written to a file (not to the TCP connection). One JSON
object per line.

### 4.1 Common Fields

Every log line contains:

```json
{"ts":"2026-03-26T14:30:01.123Z","tag":"...","seq":1042, ...}
```

| Field | Type   | Description                                  |
| ----- | ------ | -------------------------------------------- |
| `ts`  | string | ISO 8601 wall-clock timestamp                |
| `tag` | string | Log tag that emitted this entry              |
| `seq` | u64    | Monotonically increasing log sequence number |

### 4.2 Tags

| Tag             | Content                                                                            |
| --------------- | ---------------------------------------------------------------------------------- |
| `lifecycle`     | Daemon start/stop, session/pane create/destroy, client connect/disconnect          |
| `request`       | Incoming requests from clients (includes `client_id`, `msg_type`, `msg_type_code`) |
| `response`      | Outgoing responses to clients (includes `client_id`)                               |
| `notification`  | Outgoing notifications (LayoutChanged, PaneMetadataChanged, etc.)                  |
| `input`         | Key, mouse, paste events (includes HID name + hex code)                            |
| `ime`           | Preedit start/update/end, input method switch                                      |
| `frame`         | FrameUpdate metadata: pane_id, frame_seq, frame_type, dirty_row_count, byte_size   |
| `frame:verbose` | FrameUpdate cell data: per-row text + cells array                                  |
| `flow`          | PausePane, ContinuePane, backpressure events                                       |
| `error`         | All errors (always active, cannot be unsubscribed)                                 |

### 4.3 Tag Examples

```json
{"ts":"...","tag":"lifecycle","seq":1,"event":"daemon_start","pid":12345,"socket":"/tmp/it-shell3.sock","debug_port":9090}

{"ts":"...","tag":"lifecycle","seq":2,"event":"session_created","session_id":1,"name":"default"}

{"ts":"...","tag":"lifecycle","seq":5,"event":"client_connected","client_id":1}

{"ts":"...","tag":"request","seq":10,"client_id":1,"msg_type":"CreateSession","msg_type_code":"0x0100","payload":{"name":"dev"}}

{"ts":"...","tag":"response","seq":11,"client_id":1,"msg_type":"CreateSession","msg_type_code":"0x0100","payload":{"session_id":2}}

{"ts":"...","tag":"input","seq":20,"client_id":1,"pane_id":3,"msg_type":"KeyEvent","hid":"key_a","hid_code":"0x04","modifiers":[]}

{"ts":"...","tag":"ime","seq":25,"session_id":1,"event":"preedit_update","text":"한","cursor_pos":1}

{"ts":"...","tag":"frame","seq":30,"pane_id":3,"frame_seq":142,"frame_type":"P-frame","screen":"primary","dirty_rows":3,"bytes":960}

{"ts":"...","tag":"frame:verbose","seq":31,"pane_id":3,"frame_seq":142,"row":10,"text":"안녕하세요","cells":[{"col":0,"cp":"U+D55C","char":"한","wide":"wide","fg":"default","bg":"default","flags":[],"content":"codepoint"},{"col":1,"cp":0,"wide":"spacer_tail"},{"col":2,"cp":"U+AE00","char":"글","wide":"wide","fg":"rgb(255,128,0)","bg":"palette(4)","flags":["bold","italic"],"content":"codepoint"}],"graphemes":[],"underline_colors":[]}

{"ts":"...","tag":"flow","seq":40,"event":"pause_pane","pane_id":3,"reason":"backpressure"}

{"ts":"...","tag":"error","seq":50,"event":"pty_write_failed","pane_id":3,"errno":32,"message":"Broken pipe"}
```

### 4.4 Human-Readable Name Mapping

Binary values are always accompanied by a human-readable name:

- **Message types**: `msg_type:"CreateSession"` + `msg_type_code:"0x0100"`
- **HID key codes**: `hid:"key_a"` + `hid_code:"0x04"`
- **Frame types**: `frame_type:"P-frame"` (not `0`)
- **Wide values**: `wide:"wide"` / `"narrow"` / `"spacer_tail"` /
  `"spacer_head"`
- **Colors**: `fg:"default"` / `"rgb(255,128,0)"` / `"palette(4)"`
- **Style flags**: `flags:["bold","italic"]` (array of names, not bitmask)

### 4.5 dump-screen Row Format

Each row in `dump-screen` response:

```json
{"row":0,"text":"$ ls -la","row_flags":[],"cells":[...],"graphemes":[],"underline_colors":[]}
```

| Field              | Description                                                                       |
| ------------------ | --------------------------------------------------------------------------------- |
| `row`              | Row index (0 = top)                                                               |
| `text`             | Plain text content (no ANSI escapes, spacer_tail skipped)                         |
| `row_flags`        | Array of flag names: `"selection"`, `"rle"`, `"semantic_prompt:N"`, `"hyperlink"` |
| `cells`            | Array of cell objects (see below)                                                 |
| `graphemes`        | Grapheme entries if present: `[{"col":5,"extra":["U+0302"]}]`                     |
| `underline_colors` | Underline color entries if present: `[{"col":2,"color":"rgb(255,0,0)"}]`          |

Cell object:

```json
{
  "col": 0,
  "cp": "U+0041",
  "char": "A",
  "wide": "narrow",
  "fg": "rgb(255,255,255)",
  "bg": "default",
  "flags": ["bold"],
  "content": "codepoint"
}
```

Spacer tail cells are abbreviated:

```json
{ "col": 1, "cp": 0, "wide": "spacer_tail" }
```

## 5. Event Loop Integration

### 5.1 udata Allocation

| Range | Purpose                         |
| ----- | ------------------------------- |
| 0     | Unix socket listener (existing) |
| 1..98 | PTY fds (existing)              |
| 99    | Debug TCP listener (new)        |
| 100+  | Client connections (existing)   |

### 5.2 Processing Model

The debug TCP listener is registered as a READ event source in kqueue/epoll.
When a connection arrives:

1. `accept()` the connection
2. `read()` one line from the socket
3. Parse command via `CommandParser`
4. Execute synchronously (Inspector or Controller)
5. `write()` response
6. `close()` the connection

All within a single event handler invocation. No async state, no connection
tracking.

### 5.3 LogEmitter Integration

**Global optional pointer**: When `IT_SHELL3_DEBUG_PORT` is not set,
`log_emitter` is `null`. All emit calls reduce to a single null check (~1ns)
with zero argument construction overhead.

```zig
// Daemon global
var log_emitter: ?*LogEmitter = null;

// Convenience wrapper — inlined at call site
inline fn logEmit(tag: Tag, data: anytype) void {
    if (log_emitter) |le| le.emit(tag, data);
}
```

**Two-level fast path:**

1. `log_emitter == null` → null check, return (debug port not set)
2. `active_tags & tag == 0` → bit check, return (tag not subscribed)

Both levels are `inline`, so the compiler eliminates argument construction in
the not-taken path via dead code elimination.

```zig
// LogEmitter.emit — only reached when log_emitter != null
pub inline fn emit(self: *LogEmitter, tag: Tag, data: anytype) void {
    if (self.active_tags & @intFromEnum(tag) == 0) return;
    self.emitSlow(tag, data);
}
```

**Call site usage:**

```zig
fn handleCreateSession(client: *Client, msg: Message) void {
    logEmit(.request, .{
        .client_id = client.id,
        .msg_type = msg.header.msg_type,
        .payload = msg.payload,
    });

    // ... existing handler logic ...

    logEmit(.response, .{
        .client_id = client.id,
        .msg_type = msg.header.msg_type,
        .payload = response_payload,
    });
}
```

## 6. Code Placement

```
daemon/src/
├── main.zig              # reads IT_SHELL3_DEBUG_PORT, inits debug listener
└── debug/
    ├── listener.zig      # TCP accept, read, dispatch, respond, close
    ├── command_parser.zig # text line → Command union
    ├── inspector.zig     # dump-sessions, dump-screen, stats (read-only)
    ├── controller.zig    # create-session, inject-key, etc. (calls existing handlers)
    ├── log_emitter.zig   # tag bitset, JSONL serialization, buffered file writer
    └── format.zig        # CellData→JSON, HID→name, MessageType→name helpers
```

**Dependency direction:**

- `debug/` → `libitshell3` (SessionManager, Pane, EventLoop types)
- `debug/` → `libitshell3-protocol` (MessageType, CellData, FrameHeader types)
- `libitshell3` does NOT depend on `debug/`
- `libitshell3-protocol` does NOT depend on `debug/`

## 7. Typical Usage Scenarios

### 7.1 AI Agent Debugging Session

```bash
# 1. Discover available state
echo "dump-sessions" | nc localhost 9090

# 2. Start logging
echo "set-log-file /tmp/debug.log" | nc localhost 9090
echo "subscribe input,ime,frame" | nc localhost 9090

# 3. Inject input and observe
echo "inject-key 1 key_a" | nc localhost 9090
echo "dump-screen 1" | nc localhost 9090

# 4. Check logs
tail -f /tmp/debug.log | grep ime
```

### 7.2 Developer Debugging

```bash
# Quick state check
echo "dump-sessions" | nc localhost 9090
echo "dump-pane 3" | nc localhost 9090

# Watch all request/response traffic
echo "set-log-file /tmp/traffic.log" | nc localhost 9090
echo "subscribe request,response" | nc localhost 9090
tail -f /tmp/traffic.log

# Reproduce a bug without client
echo "create-session test" | nc localhost 9090
echo "inject-text 2 'ls -la'" | nc localhost 9090
echo "inject-key 2 key_return" | nc localhost 9090
echo "dump-screen 2" | nc localhost 9090
```

### 7.3 End-User Bug Report

```bash
# Start daemon with debug port
IT_SHELL3_DEBUG_PORT=9090 it-shell3-daemon --socket-path /tmp/it-shell3.sock

# Capture traffic
echo "set-log-file ~/debug-capture.log" | nc localhost 9090
echo "subscribe lifecycle,request,response,error" | nc localhost 9090

# ... reproduce the bug ...

# Stop and attach log to bug report
echo "stop-logging" | nc localhost 9090
```

## 8. Future Extensions

- **`it-shell3-ctl` CLI tool**: Thin TCP client wrapping the debug command set.
  Extract command definitions into a shared module when needed. Deferred per
  YAGNI.
- **`:verbose` modifier on other tags**: e.g. `request:verbose` for full JSON
  payload dump. Add when needed.
- **Log rotation**: `set-log-file` with size limit or rotation policy. Add when
  log files grow too large in practice.
