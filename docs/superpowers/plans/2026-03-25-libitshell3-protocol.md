# libitshell3-protocol Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use the `/implementation` skill
> to execute this plan. The implementation team is defined in
> `.claude/agents/impl-team/`.

**Goal:** Implement the wire protocol library shared by daemon and client —
message types, serialization, binary FrameUpdate encoding, streaming frame
reader/writer, Unix socket transport (server + client), connection lifecycle
state machine, and handshake orchestration.

**Architecture:** Zig library with libc dependency (for POSIX sockets). All
control messages use `std.json` for serialization. FrameUpdate uses custom
binary encoding (16-byte CellData, 9-byte RowHeader, RLE). Streaming frame
reader/writer works with generic Zig `Reader`/`Writer` interfaces. Header is
16-byte fixed format, little-endian throughout. Transport layer abstracts Unix
socket vs SSH tunnel (SSH is Phase 5, interface only for now). Connection state
machine (DISCONNECTED→HANDSHAKING→READY→OPERATING→DISCONNECTING) is shared
between server and client sides. UID authentication via `getpeereid()`.

**Tech Stack:** Zig 0.15+, `std.json`, `std.mem` (little-endian int ops),
`std.posix` (sockets, getpeereid), libc

**Spec:**
`docs/modules/libitshell3-protocol/02-design-docs/server-client-protocols/draft/v1.0-r12/`
(docs 01-06)

---

## Team Composition

| Role                | Agent Definition                                  | Model  |
| ------------------- | ------------------------------------------------- | ------ |
| Implementer         | `.claude/agents/impl-team/implementer.md`         | sonnet |
| QA Reviewer         | `.claude/agents/impl-team/qa-reviewer.md`         | sonnet |
| Principal Architect | `.claude/agents/impl-team/principal-architect.md` | opus   |

## Task Dependency Graph

```
Task 1 (scaffold)
  └──► Task 2 (header + flags)
         ├──► Task 3 (message_type + error + capability + json helpers)
         │      ├──► Task 4 (handshake messages)
         │      ├──► Task 5 (session messages)
         │      ├──► Task 6 (pane messages + notifications)
         │      ├──► Task 7 (input + render messages)
         │      ├──► Task 8 (preedit + auxiliary messages)
         │      └──► Task 9 (CellData + binary cell types)
         │               └──► Task 10 (FrameUpdate encoder/decoder)
         └──► Task 11 (frame reader + writer + sequence)
                ├──► Task 12 (socket path + transport interface)
                │      └──► Task 13 (connection state machine + UID auth)
                │             └──► Task 14 (handshake orchestration)
                │                    └──► Task 15 (migrate libitshell3 transport → protocol)
                └──► Task 16 (integration tests — depends on ALL)
```

Tasks 4-8 are independent of each other (all depend only on Task 3). Task 9
depends only on Task 3. Task 10 depends on Task 9. Task 11 depends on Task 2.
Tasks 12-14 form a chain (transport → state machine → handshake). Task 14 also
depends on Task 4 (handshake message types). Task 15 migrates existing
libitshell3 transport/connection code to depend on the new protocol module. Task
16 (integration tests) depends on all others.

---

## File Structure

```
modules/libitshell3-protocol/
├── build.zig
├── build.zig.zon
└── src/
    ├── root.zig              # Public exports + test entry
    ├── header.zig            # Header (16B), Flags, encode/decode
    ├── message_type.zig      # MessageType enum (all u16 codes)
    ├── error.zig             # StatusCode, ErrorCode enums, ErrorResponse
    ├── capability.zig        # Capability, RenderCapability enums
    ├── json.zig              # JSON helpers (encode/decode wrapping std.json)
    ├── handshake.zig         # ClientHello, ServerHello, Heartbeat, Disconnect
    ├── session.zig           # Session CRUD request/response types
    ├── pane.zig              # Pane CRUD + notifications + WindowResize
    ├── input.zig             # KeyEvent, TextInput, Mouse*, Paste, Focus, Scroll, Search
    ├── preedit.zig           # Preedit lifecycle + IMEError + AmbiguousWidth
    ├── auxiliary.zig         # Flow control, Clipboard, Persistence, Extensions, Subscriptions
    ├── cell.zig              # CellData (16B extern), PackedColor, RowHeader, side tables
    ├── frame_update.zig      # FrameUpdate binary encoder/decoder
    ├── reader.zig            # Streaming frame reader (header + payload)
    ├── writer.zig            # Frame writer + sequence tracker
    ├── socket_path.zig       # Socket path resolution ($ITSHELL3_SOCKET, XDG, TMPDIR)
    ├── transport.zig         # Transport interface + Unix socket impl (server + client)
    ├── auth.zig              # UID authentication (getpeereid)
    ├── connection.zig        # Connection state machine (shared server/client)
    └── handshake_io.zig      # Handshake orchestration (performServerHandshake / performClientHandshake)
```

20 source files. Each file has one clear responsibility.

---

### Task 1: Build Scaffold

**Files:**

- Create: `modules/libitshell3-protocol/build.zig`
- Create: `modules/libitshell3-protocol/build.zig.zon`
- Create: `modules/libitshell3-protocol/src/root.zig`

- [ ] **Step 1: Create build.zig.zon**

```zig
.{
    .name = .@"libitshell3-protocol",
    .version = "0.1.0",
    .fingerprint = 0xb7e44f08c74cdf5f,
    .paths = .{""},
    .dependencies = .{},
}
```

No external dependencies — this is a pure Zig library.

- [ ] **Step 2: Create build.zig**

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "itshell3-protocol",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_tests.step);
}
```

- [ ] **Step 3: Create src/root.zig with a smoke test**

```zig
pub const header = @import("header.zig");

test {
    @import("std").testing.refAllDecls(@This());
}

test "smoke: protocol library loads" {
    // Placeholder — replaced as modules are added
}
```

- [ ] **Step 4: Create a minimal src/header.zig stub**

```zig
pub const HEADER_SIZE: usize = 16;

test "header size is 16" {
    try @import("std").testing.expectEqual(@as(usize, 16), HEADER_SIZE);
}
```

- [ ] **Step 5: Verify build**

Run: `(cd modules/libitshell3-protocol && zig build test)` Expected: PASS (1
test)

- [ ] **Step 6: Commit**

```bash
git add modules/libitshell3-protocol/
git commit -m "feat(libitshell3-protocol): add build scaffold"
```

---

### Task 2: Header + Flags

**Files:**

- Modify: `modules/libitshell3-protocol/src/header.zig`
- Modify: `modules/libitshell3-protocol/src/root.zig`

**Spec ref:** Doc 01 §3.1-3.2 (Header format, Flags)

The 16-byte header is the foundation of every protocol message. All multi-byte
fields are little-endian.

```
Offset  Size  Field        Type
------  ----  -----        ----
0       2     magic        u8[2]     0x49 0x54 ("IT")
2       1     version      u8        1
3       1     flags        u8        bit flags
4       2     msg_type     u16 LE
6       2     reserved     u16 LE    must be 0
8       4     payload_len  u32 LE
12      4     sequence     u32 LE
```

- [ ] **Step 1: Implement Flags and Header**

```zig
const std = @import("std");

pub const HEADER_SIZE: usize = 16;
pub const MAGIC: [2]u8 = .{ 0x49, 0x54 }; // "IT"
pub const VERSION: u8 = 1;
pub const MAX_PAYLOAD_SIZE: u32 = 16 * 1024 * 1024; // 16 MiB

pub const Flags = packed struct(u8) {
    encoding: enum(u1) { json = 0, binary = 1 } = .json,
    response: bool = false,
    @"error": bool = false,
    more_fragments: bool = false,
    _reserved: u4 = 0,
};

pub const Header = struct {
    msg_type: u16,
    flags: Flags,
    payload_len: u32,
    sequence: u32,

    pub fn encode(self: Header, buf: *[HEADER_SIZE]u8) void {
        buf[0] = MAGIC[0];
        buf[1] = MAGIC[1];
        buf[2] = VERSION;
        buf[3] = @bitCast(self.flags);
        std.mem.writeInt(u16, buf[4..6], self.msg_type, .little);
        std.mem.writeInt(u16, buf[6..8], 0, .little); // reserved
        std.mem.writeInt(u32, buf[8..12], self.payload_len, .little);
        std.mem.writeInt(u32, buf[12..16], self.sequence, .little);
    }

    pub fn decode(buf: *const [HEADER_SIZE]u8) HeaderError!Header {
        if (buf[0] != MAGIC[0] or buf[1] != MAGIC[1])
            return error.BadMagic;
        if (buf[2] != VERSION)
            return error.UnsupportedVersion;
        const flags: Flags = @bitCast(buf[3]);
        if (flags._reserved != 0)
            return error.ReservedFlagsSet;
        const reserved = std.mem.readInt(u16, buf[6..8], .little);
        if (reserved != 0)
            return error.ReservedFieldNonZero;
        const payload_len = std.mem.readInt(u32, buf[8..12], .little);
        if (payload_len > MAX_PAYLOAD_SIZE)
            return error.PayloadTooLarge;
        return .{
            .msg_type = std.mem.readInt(u16, buf[4..6], .little),
            .flags = flags,
            .payload_len = payload_len,
            .sequence = std.mem.readInt(u32, buf[12..16], .little),
        };
    }
};

pub const HeaderError = error{
    BadMagic,
    UnsupportedVersion,
    ReservedFlagsSet,
    ReservedFieldNonZero,
    PayloadTooLarge,
};
```

- [ ] **Step 2: Write tests**

Test cases:

1. Encode then decode round-trip (identity)
2. All flag combinations (json/binary, response, error, fragments)
3. Bad magic → `error.BadMagic`
4. Wrong version → `error.UnsupportedVersion`
5. Reserved flags set → `error.ReservedFlagsSet`
6. Reserved field non-zero → `error.ReservedFieldNonZero`
7. Payload too large → `error.PayloadTooLarge`
8. Payload length exactly at limit (16 MiB) → OK
9. Sequence number 0 (valid — sentinel in payloads but valid in header)
10. Flags packed struct is exactly 1 byte

- [ ] **Step 3: Run tests**

Run: `(cd modules/libitshell3-protocol && zig build test)` Expected: All pass

- [ ] **Step 4: Commit**

```bash
git add modules/libitshell3-protocol/src/
git commit -m "feat(libitshell3-protocol): add 16-byte header encode/decode"
```

---

### Task 3: MessageType + Error Codes + Capability + JSON Helpers

**Files:**

- Create: `modules/libitshell3-protocol/src/message_type.zig`
- Create: `modules/libitshell3-protocol/src/error.zig`
- Create: `modules/libitshell3-protocol/src/capability.zig`
- Create: `modules/libitshell3-protocol/src/json.zig`
- Modify: `modules/libitshell3-protocol/src/root.zig`

**Spec ref:** Doc 01 §4.2 (message type table), §6.2-6.3 (error codes), Doc 02
(capabilities)

- [ ] **Step 1: Create message_type.zig — MessageType enum**

Define a `u16` enum with ALL message type codes from Doc 01 §4.2:

```zig
pub const MessageType = enum(u16) {
    // Handshake & Lifecycle (0x0001-0x00FF)
    client_hello = 0x0001,
    server_hello = 0x0002,
    heartbeat = 0x0003,
    heartbeat_ack = 0x0004,
    disconnect = 0x0005,
    @"error" = 0x00FF,

    // Session Management (0x0100-0x01FF)
    create_session_request = 0x0100,
    create_session_response = 0x0101,
    list_sessions_request = 0x0102,
    list_sessions_response = 0x0103,
    attach_session_request = 0x0104,
    attach_session_response = 0x0105,
    detach_session_request = 0x0106,
    detach_session_response = 0x0107,
    destroy_session_request = 0x0108,
    destroy_session_response = 0x0109,
    rename_session_request = 0x010A,
    rename_session_response = 0x010B,
    attach_or_create_request = 0x010C,
    attach_or_create_response = 0x010D,

    // Pane Management (0x0140-0x01FF)
    create_pane_request = 0x0140,
    create_pane_response = 0x0141,
    split_pane_request = 0x0142,
    split_pane_response = 0x0143,
    close_pane_request = 0x0144,
    close_pane_response = 0x0145,
    focus_pane_request = 0x0146,
    focus_pane_response = 0x0147,
    navigate_pane_request = 0x0148,
    navigate_pane_response = 0x0149,
    resize_pane_request = 0x014A,
    resize_pane_response = 0x014B,
    equalize_splits_request = 0x014C,
    equalize_splits_response = 0x014D,
    zoom_pane_request = 0x014E,
    zoom_pane_response = 0x014F,
    swap_panes_request = 0x0150,
    swap_panes_response = 0x0151,
    layout_get_request = 0x0152,
    layout_get_response = 0x0153,

    // Notifications (0x0180-0x019F)
    layout_changed = 0x0180,
    pane_metadata_changed = 0x0181,
    session_list_changed = 0x0182,
    client_attached = 0x0183,
    client_detached = 0x0184,
    client_health_changed = 0x0185,
    window_resize = 0x0190,
    window_resize_ack = 0x0191,

    // Input (0x0200-0x02FF)
    key_event = 0x0200,
    text_input = 0x0201,
    mouse_button = 0x0202,
    mouse_move = 0x0203,
    mouse_scroll = 0x0204,
    paste_data = 0x0205,
    focus_event = 0x0206,

    // RenderState (0x0300-0x03FF)
    frame_update = 0x0300,
    scroll_request = 0x0301,
    scroll_position = 0x0302,
    search_request = 0x0303,
    search_result = 0x0304,
    search_cancel = 0x0305,

    // CJK & IME (0x0400-0x04FF)
    preedit_start = 0x0400,
    preedit_update = 0x0401,
    preedit_end = 0x0402,
    preedit_sync = 0x0403,
    input_method_switch = 0x0404,
    input_method_ack = 0x0405,
    ambiguous_width_config = 0x0406,
    ime_error = 0x04FF,

    // Flow Control (0x0500-0x05FF)
    pause_pane = 0x0500,
    continue_pane = 0x0501,
    flow_control_config = 0x0502,
    flow_control_config_ack = 0x0503,
    output_queue_status = 0x0504,
    client_display_info = 0x0505,
    client_display_info_ack = 0x0506,

    // Clipboard (0x0600-0x06FF)
    clipboard_write = 0x0600,
    clipboard_read = 0x0601,
    clipboard_read_response = 0x0602,
    clipboard_changed = 0x0603,
    clipboard_write_from_client = 0x0604,

    // Persistence (0x0700-0x07FF)
    snapshot_request = 0x0700,
    snapshot_response = 0x0701,
    restore_session_request = 0x0702,
    restore_session_response = 0x0703,
    snapshot_list_request = 0x0704,
    snapshot_list_response = 0x0705,
    snapshot_auto_save_config = 0x0706,
    snapshot_auto_save_config_ack = 0x0707,

    // Notifications & Subscriptions (0x0800-0x08FF)
    pane_title_changed = 0x0800,
    process_exited = 0x0801,
    bell = 0x0802,
    renderer_health = 0x0803,
    pane_cwd_changed = 0x0804,
    activity_detected = 0x0805,
    silence_detected = 0x0806,
    subscribe = 0x0810,
    subscribe_ack = 0x0811,
    unsubscribe = 0x0812,
    unsubscribe_ack = 0x0813,

    // Extensions (0x0A00-0x0AFF)
    extension_list = 0x0A00,
    extension_list_ack = 0x0A01,
    extension_message = 0x0A02,
    _,

    /// Returns the expected encoding for this message type.
    pub fn expectedEncoding(self: MessageType) Encoding {
        return switch (self) {
            .frame_update => .binary,
            else => .json,
        };
    }

    pub const Encoding = enum { json, binary };
};
```

- [ ] **Step 2: Create error.zig — Status codes and error types**

```zig
/// Per-response status codes (doc 03 convention)
pub const StatusCode = enum(u32) {
    ok = 0,
    not_found = 1,
    already_exists = 2,
    too_small = 3,
    processes_running = 4,
    access_denied = 5,
    invalid_argument = 6,
    internal_error = 7,
    pane_limit_exceeded = 8,
    _,
};

/// Protocol-level error codes (doc 01 §6.2-6.3)
pub const ErrorCode = enum(u32) {
    // Protocol errors (0x01-0xFF)
    bad_magic = 0x00000001,
    unsupported_version = 0x00000002,
    bad_msg_type = 0x00000003,
    payload_too_large = 0x00000004,
    invalid_state = 0x00000005,
    malformed_payload = 0x00000006,
    protocol_error = 0x00000007,
    bad_encoding = 0x00000008,

    // Handshake errors (0x100-0x1FF)
    version_mismatch = 0x00000100,
    auth_failed = 0x00000101,
    capability_required = 0x00000102,

    // Session errors (0x200-0x2FF)
    session_not_found = 0x00000200,
    session_already_attached = 0x00000201,
    session_limit = 0x00000202,
    access_denied = 0x00000203,

    // Pane errors (0x300-0x3FF)
    pane_not_found = 0x00000300,
    pane_exited = 0x00000301,
    split_failed = 0x00000302,

    // Resource errors (0x600-0x6FF)
    resource_exhausted = 0x00000600,
    rate_limited = 0x00000601,

    internal = 0xFFFFFFFF,
    _,

    pub fn isFatal(self: ErrorCode) bool {
        const code = @intFromEnum(self);
        return code <= 0xFF or (code >= 0x100 and code <= 0x1FF);
    }
};

/// Error message payload (0x00FF)
pub const ErrorResponse = struct {
    error_code: u32,
    ref_sequence: u32 = 0,
    detail: []const u8 = "",
};
```

- [ ] **Step 3: Create capability.zig**

```zig
pub const Capability = enum {
    clipboard_sync,
    mouse,
    selection,
    search,
    fd_passing,
    preedit,
};

pub const RenderCapability = enum {
    cell_data,
    dirty_tracking,
    cursor_style,
};
```

- [ ] **Step 4: Create json.zig — JSON encode/decode helpers**

Wraps `std.json` with protocol-specific conventions (omit null optionals,
tolerate unknown fields for forward compatibility):

```zig
const std = @import("std");

pub const ParseError = std.json.ParseError(std.json.Scanner);
pub const StringifyError = std.json.StringifyError;

/// Decode a JSON payload into a struct of type T.
/// Tolerates unknown fields (forward compatibility).
pub fn decode(comptime T: type, allocator: std.mem.Allocator, payload: []const u8) ParseError!std.json.Parsed(T) {
    return std.json.parseFromSlice(T, allocator, payload, .{
        .ignore_unknown_fields = true,
    });
}

/// Encode a struct to JSON. Null optionals are omitted.
pub fn encode(allocator: std.mem.Allocator, value: anytype) StringifyError![]u8 {
    return std.json.stringifyAlloc(allocator, value, .{
        .emit_null_optional_fields = false,
    });
}
```

- [ ] **Step 5: Tests**

Test cases:

1. MessageType enum values match spec (spot-check: client_hello=0x0001,
   frame_update=0x0300, ime_error=0x04FF)
2. `expectedEncoding()` returns `.binary` for frame_update, `.json` for all
   others
3. ErrorCode.isFatal() — protocol/handshake codes are fatal, session/pane are
   not
4. JSON encode/decode round-trip for a simple struct with optional fields
5. JSON decode with unknown fields (ignored, no error)
6. JSON encode omits null optional fields

- [ ] **Step 6: Update root.zig exports + run tests**

- [ ] **Step 7: Commit**

```bash
git commit -m "feat(libitshell3-protocol): add message types, error codes, capabilities, JSON helpers"
```

---

### Task 4: Handshake Messages

**Files:**

- Create: `modules/libitshell3-protocol/src/handshake.zig`
- Modify: `modules/libitshell3-protocol/src/root.zig`

**Spec ref:** Doc 02 (Handshake & Capability Negotiation)

- [ ] **Step 1: Define all handshake message types**

Messages to implement in `handshake.zig`:

```zig
/// ClientHello (0x0001, C→S)
pub const ClientHello = struct {
    protocol_version_min: u32 = 1,
    protocol_version_max: u32 = 1,
    client_type: ClientType = .native,
    capabilities: []const []const u8 = &.{},
    render_capabilities: []const []const u8 = &.{},
    preferred_input_methods: []const InputMethodPref = &.{},
    client_name: []const u8 = "",
    client_version: []const u8 = "",
    terminal_type: []const u8 = "xterm-256color",
    cols: u16 = 80,
    rows: u16 = 24,
    pixel_width: ?u16 = null,
    pixel_height: ?u16 = null,

    pub const ClientType = enum { native, control, headless };

    pub const InputMethodPref = struct {
        method: []const u8,
    };
};

/// ServerHello (0x0002, S→C)
pub const ServerHello = struct {
    protocol_version: u32 = 1,
    client_id: u32,
    negotiated_caps: []const []const u8 = &.{},
    negotiated_render_caps: []const []const u8 = &.{},
    supported_input_methods: []const InputMethodInfo = &.{},
    server_pid: u32,
    server_name: []const u8 = "itshell3d",
    server_version: []const u8 = "",
    heartbeat_interval_ms: u32 = 30000,
    max_panes_per_session: u32 = 0,
    max_sessions: u32 = 0,
    coalescing_config: ?CoalescingConfig = null,
    sessions: []const SessionSummary = &.{},

    pub const InputMethodInfo = struct {
        method: []const u8,
        layouts: []const []const u8 = &.{},
    };

    pub const CoalescingConfig = struct {
        interactive_threshold_kbps: u32 = 1,
        active_interval_ms: u32 = 16,
        bulk_threshold_kbps: u32 = 100,
        bulk_interval_ms: u32 = 33,
        idle_timeout_ms: u32 = 500,
        preedit_fallback_ms: u32 = 200,
    };

    pub const SessionSummary = struct {
        session_id: u32,
        name: []const u8,
        attached_clients: u16 = 0,
        pane_count: u16 = 1,
        created_at: u64 = 0,
        last_activity: u64 = 0,
    };
};

/// Heartbeat (0x0003, bidirectional)
pub const Heartbeat = struct {
    ping_id: u32,
};

/// HeartbeatAck (0x0004, bidirectional)
pub const HeartbeatAck = struct {
    ping_id: u32,
};

/// Disconnect (0x0005, bidirectional)
pub const Disconnect = struct {
    reason: []const u8 = "",
    detail: []const u8 = "",
};
```

- [ ] **Step 2: Write JSON round-trip tests**

Test each message type: create → `json.encode()` → `json.decode()` → compare.
Test that optional fields (pixel_width, coalescing_config) are omitted when null
and restored when present.

- [ ] **Step 3: Run tests, commit**

```bash
git commit -m "feat(libitshell3-protocol): add handshake messages"
```

---

### Task 5: Session Messages

**Files:**

- Create: `modules/libitshell3-protocol/src/session.zig`
- Modify: `modules/libitshell3-protocol/src/root.zig`

**Spec ref:** Doc 03 §2 (Session Management)

- [ ] **Step 1: Define all session message types**

```zig
/// CreateSessionRequest (0x0100, C→S)
pub const CreateSessionRequest = struct {
    name: ?[]const u8 = null,
    shell: ?[]const u8 = null,
    cwd: ?[]const u8 = null,
    cols: ?u16 = null,
    rows: ?u16 = null,
};

/// CreateSessionResponse (0x0101, S→C)
pub const CreateSessionResponse = struct {
    status: u32 = 0,
    session_id: u32 = 0,
    pane_id: u32 = 0,
    @"error": ?[]const u8 = null,
};
```

Remaining types to implement following same pattern (see doc 03 for exact
fields):

- `ListSessionsRequest` (0x0102) — empty struct
- `ListSessionsResponse` (0x0103) — status + sessions array
- `AttachSessionRequest` (0x0104) — session_id, cols, rows, readonly,
  detach_others
- `AttachSessionResponse` (0x0105) — status, session_id, name, active_pane_id,
  active_input_method, active_keyboard_layout, resize_policy
- `DetachSessionRequest` (0x0106) — session_id
- `DetachSessionResponse` (0x0107) — status, reason
- `DestroySessionRequest` (0x0108) — session_id
- `DestroySessionResponse` (0x0109) — status
- `RenameSessionRequest` (0x010A) — session_id, new_name
- `RenameSessionResponse` (0x010B) — status
- `AttachOrCreateRequest` (0x010C) — name + attach/create fields
- `AttachOrCreateResponse` (0x010D) — status, action_taken, session_id, pane_id

- [ ] **Step 2: Write JSON round-trip tests for each type**
- [ ] **Step 3: Run tests, commit**

```bash
git commit -m "feat(libitshell3-protocol): add session messages"
```

---

### Task 6: Pane Messages + Notifications

**Files:**

- Create: `modules/libitshell3-protocol/src/pane.zig`
- Modify: `modules/libitshell3-protocol/src/root.zig`

**Spec ref:** Doc 03 §3-4 (Pane Operations, Notifications)

- [ ] **Step 1: Define pane request/response types**

Pattern (same for all pane ops):

```zig
pub const Direction = enum(u8) { right = 0, down = 1, left = 2, up = 3 };

pub const SplitPaneRequest = struct {
    session_id: u32,
    pane_id: u32,
    direction: u8 = 0,
    ratio: f32 = 0.5,
};

pub const SplitPaneResponse = struct {
    status: u32 = 0,
    new_pane_id: u32 = 0,
};
```

Complete list of pane types: CreatePaneRequest/Response,
SplitPaneRequest/Response, ClosePaneRequest/Response, FocusPaneRequest/Response,
NavigatePaneRequest/Response, ResizePaneRequest/Response,
EqualizeSplitsRequest/Response, ZoomPaneRequest/Response,
SwapPanesRequest/Response, LayoutGetRequest/Response, WindowResize,
WindowResizeAck.

- [ ] **Step 2: Define notification types**

```zig
/// LayoutChanged (0x0180, S→C)
pub const LayoutChanged = struct {
    session_id: u32,
    active_pane_id: u32,
    zoomed_pane_present: bool = false,
    zoomed_pane_id: u32 = 0,
    layout_tree: LayoutNode,
};

/// Recursive layout tree node — JSON serialized.
pub const LayoutNode = struct {
    type: NodeType,
    pane_id: ?u32 = null,
    cols: ?u16 = null,
    rows: ?u16 = null,
    x_off: ?u16 = null,
    y_off: ?u16 = null,
    preedit_active: ?bool = null,
    active_input_method: ?[]const u8 = null,
    active_keyboard_layout: ?[]const u8 = null,
    orientation: ?[]const u8 = null,
    ratio: ?f32 = null,
    first: ?*const LayoutNode = null,
    second: ?*const LayoutNode = null,

    pub const NodeType = enum { leaf, split };
};
```

Also: `PaneMetadataChanged`, `SessionListChanged`, `ClientAttached`,
`ClientDetached`, `ClientHealthChanged` (see doc 03 §4).

- [ ] **Step 3: Tests + commit**

```bash
git commit -m "feat(libitshell3-protocol): add pane messages and notifications"
```

---

### Task 7: Input + Render Messages

**Files:**

- Create: `modules/libitshell3-protocol/src/input.zig`
- Modify: `modules/libitshell3-protocol/src/root.zig`

**Spec ref:** Doc 04 §2-3 (Input, Scroll, Search)

- [ ] **Step 1: Define input message types**

```zig
/// KeyEvent (0x0200, C→S)
pub const KeyEvent = struct {
    keycode: u16,
    action: u8,         // 0=press, 1=release, 2=repeat
    modifiers: u8,      // bitflags: Shift=0, Ctrl=1, Alt=2, Super=3, CapsLock=4, NumLock=5
    input_method: []const u8 = "direct",
    pane_id: ?u32 = null,
};

/// Modifier bitflags
pub const Modifiers = struct {
    pub const shift: u8 = 1 << 0;
    pub const ctrl: u8 = 1 << 1;
    pub const alt: u8 = 1 << 2;
    pub const super: u8 = 1 << 3;
    pub const caps_lock: u8 = 1 << 4;
    pub const num_lock: u8 = 1 << 5;
};

/// Key action values
pub const Action = struct {
    pub const press: u8 = 0;
    pub const release: u8 = 1;
    pub const repeat: u8 = 2;
};
```

Remaining input types: `TextInput`, `MouseButton`, `MouseMove`, `MouseScroll`,
`PasteData`, `FocusEvent` (see doc 04 §2 for fields).

Render types: `ScrollRequest`, `ScrollPosition`, `SearchRequest`,
`SearchResult`, `SearchCancel` (doc 04 §3).

- [ ] **Step 2: Tests + commit**

```bash
git commit -m "feat(libitshell3-protocol): add input and render messages"
```

---

### Task 8: Preedit + Auxiliary Messages

**Files:**

- Create: `modules/libitshell3-protocol/src/preedit.zig`
- Create: `modules/libitshell3-protocol/src/auxiliary.zig`
- Modify: `modules/libitshell3-protocol/src/root.zig`

**Spec ref:** Doc 05 (Preedit), Doc 06 (Flow control, Clipboard, etc.)

- [ ] **Step 1: Define preedit message types**

```zig
/// PreeditStart (0x0400, S→C)
pub const PreeditStart = struct {
    pane_id: u32,
    client_id: u32,
    active_input_method: []const u8,
    preedit_session_id: u32,
};

/// PreeditUpdate (0x0401, S→C)
pub const PreeditUpdate = struct {
    pane_id: u32,
    preedit_session_id: u32,
    text: []const u8,
};

/// PreeditEnd (0x0402, S→C)
pub const PreeditEnd = struct {
    pane_id: u32,
    preedit_session_id: u32,
    reason: []const u8,           // "committed", "cancelled", "pane_closed", etc.
    committed_text: ?[]const u8 = null,
};
```

Also: `PreeditSync`, `InputMethodSwitch`, `InputMethodAck`,
`AmbiguousWidthConfig`, `IMEError` (doc 05).

- [ ] **Step 2: Define auxiliary message types**

In `auxiliary.zig`:

- Flow control: `PausePane`, `ContinuePane`, `FlowControlConfig`,
  `FlowControlConfigAck`, `OutputQueueStatus`, `ClientDisplayInfo`,
  `ClientDisplayInfoAck`
- Clipboard: `ClipboardWrite`, `ClipboardRead`, `ClipboardReadResponse`,
  `ClipboardChanged`, `ClipboardWriteFromClient`
- Persistence: `SnapshotRequest`, `SnapshotResponse`, `RestoreSessionRequest`,
  `RestoreSessionResponse`, `SnapshotListRequest`, `SnapshotListResponse`,
  `SnapshotAutoSaveConfig`, `SnapshotAutoSaveConfigAck`
- Subscriptions: `Subscribe`, `SubscribeAck`, `Unsubscribe`, `UnsubscribeAck`
- Notifications: `PaneTitleChanged`, `ProcessExited`, `Bell`, `RendererHealth`,
  `PaneCwdChanged`, `ActivityDetected`, `SilenceDetected`
- Extensions: `ExtensionList`, `ExtensionListAck`, `ExtensionMessage`

All are JSON. Follow the pattern from Task 4 (struct with matching spec fields).

- [ ] **Step 3: Tests + commit**

```bash
git commit -m "feat(libitshell3-protocol): add preedit and auxiliary messages"
```

---

### Task 9: CellData Binary Types

**Files:**

- Create: `modules/libitshell3-protocol/src/cell.zig`
- Modify: `modules/libitshell3-protocol/src/root.zig`

**Spec ref:** Doc 04 §4 (FrameUpdate binary format — CellData, RowHeader)

This is the most performance-critical part of the protocol. CellData is a
16-byte fixed-size `extern struct` for binary encoding. All fields are
little-endian.

- [ ] **Step 1: Define CellData and PackedColor**

```zig
const std = @import("std");

/// PackedColor (4 bytes)
/// Byte 0: tag (0x00=default, 0x01=palette, 0x02=rgb)
/// Bytes 1-3: data (palette index or R,G,B)
pub const PackedColor = extern struct {
    tag: u8,
    data: [3]u8,

    pub const default_color: PackedColor = .{ .tag = 0x00, .data = .{ 0, 0, 0 } };

    pub fn palette(index: u8) PackedColor {
        return .{ .tag = 0x01, .data = .{ index, 0, 0 } };
    }

    pub fn rgb(r: u8, g: u8, b: u8) PackedColor {
        return .{ .tag = 0x02, .data = .{ r, g, b } };
    }

    pub fn isDefault(self: PackedColor) bool {
        return self.tag == 0x00;
    }
};

/// CellData (16 bytes, extern struct for exact binary layout)
/// All fields little-endian on wire.
pub const CellData = extern struct {
    codepoint: u32,       // Unicode codepoint (0 = empty)
    wide: u8,             // 0=narrow, 1=wide, 2=spacer_tail, 3=spacer_head
    flags: u16,           // Style flags (see StyleFlags)
    content_tag: u8,      // 0=codepoint, 1=codepoint_grapheme, 2=bg_color_palette, 3=bg_color_rgb
    fg_color: PackedColor,
    bg_color: PackedColor,

    comptime {
        if (@sizeOf(CellData) != 16) @compileError("CellData must be 16 bytes");
    }

    pub const Wide = struct {
        pub const narrow: u8 = 0;
        pub const wide: u8 = 1;
        pub const spacer_tail: u8 = 2;
        pub const spacer_head: u8 = 3;
    };

    pub const ContentTag = struct {
        pub const codepoint: u8 = 0;
        pub const codepoint_grapheme: u8 = 1;
        pub const bg_color_palette: u8 = 2;
        pub const bg_color_rgb: u8 = 3;
    };
};

/// Style flags (u16 LE, doc 04 §4)
pub const StyleFlags = struct {
    pub const bold: u16 = 1 << 0;
    pub const italic: u16 = 1 << 1;
    pub const faint: u16 = 1 << 2;
    pub const blink: u16 = 1 << 3;
    pub const inverse: u16 = 1 << 4;
    pub const invisible: u16 = 1 << 5;
    pub const strikethrough: u16 = 1 << 6;
    pub const overline: u16 = 1 << 7;
    // Bits 8-10: underline style (0=none, 1=single, 2=double, 3=curly, 4=dotted, 5=dashed)
    pub const underline_mask: u16 = 0x0700;
    pub const underline_shift: u4 = 8;
};
```

- [ ] **Step 2: Define RowHeader**

```zig
/// RowHeader (9 bytes binary)
/// Cannot use extern struct — C ABI pads after row_flags (u8) to align
/// selection_start (u16), making it 10 bytes. Use manual encode/decode.
pub const RowHeader = struct {
    y: u16,              // Row index (0=top)
    row_flags: u8,       // Bit 0=selection, 1=rle_encoded, 2-3=semantic_prompt, 4=hyperlink
    selection_start: u16,
    selection_end: u16,
    num_cells: u16,      // Cell count (or run count if RLE)

    pub const SIZE: usize = 9;

    pub const RowFlags = struct {
        pub const selection: u8 = 1 << 0;
        pub const rle_encoded: u8 = 1 << 1;
        // Bits 2-3: semantic_prompt (0=none, 1=prompt, 2=prompt_continuation)
        pub const semantic_prompt_mask: u8 = 0x0C;
        pub const semantic_prompt_shift: u3 = 2;
        // Bit 4: hyperlink (row contains hyperlinked cells)
        pub const hyperlink: u8 = 1 << 4;
    };

    pub fn hasSelection(self: RowHeader) bool {
        return self.row_flags & RowFlags.selection != 0;
    }

    pub fn isRleEncoded(self: RowHeader) bool {
        return self.row_flags & RowFlags.rle_encoded != 0;
    }

    pub fn semanticPrompt(self: RowHeader) u2 {
        return @truncate((self.row_flags & RowFlags.semantic_prompt_mask) >> RowFlags.semantic_prompt_shift);
    }

    pub fn hasHyperlink(self: RowHeader) bool {
        return self.row_flags & RowFlags.hyperlink != 0;
    }
};
```

- [ ] **Step 3: Define GraphemeTable and UnderlineColorTable**

```zig
/// GraphemeTable entry — variable-length per row
pub const GraphemeEntry = struct {
    col_index: u16,
    extra_codepoints: []const u32,
};

/// UnderlineColorTable entry
pub const UnderlineColorEntry = struct {
    col_index: u16,
    underline_color: PackedColor,
};
```

- [ ] **Step 4: Implement encode/decode for CellData**

Since CellData is `extern struct`, encoding is just
`@as(*const [16]u8, @ptrCast(&cell))` on little-endian. But for correctness on
all platforms, provide explicit encode/decode using `std.mem.writeInt`:

```zig
pub fn encodeCellData(cell: CellData, out: *[16]u8) void {
    std.mem.writeInt(u32, out[0..4], cell.codepoint, .little);
    out[4] = cell.wide;
    std.mem.writeInt(u16, out[5..7], cell.flags, .little);
    out[7] = cell.content_tag;
    out[8] = cell.fg_color.tag;
    out[9] = cell.fg_color.data[0];
    out[10] = cell.fg_color.data[1];
    out[11] = cell.fg_color.data[2];
    out[12] = cell.bg_color.tag;
    out[13] = cell.bg_color.data[0];
    out[14] = cell.bg_color.data[1];
    out[15] = cell.bg_color.data[2];
}

pub fn decodeCellData(buf: *const [16]u8) CellData {
    return .{
        .codepoint = std.mem.readInt(u32, buf[0..4], .little),
        .wide = buf[4],
        .flags = std.mem.readInt(u16, buf[5..7], .little),
        .content_tag = buf[7],
        .fg_color = .{ .tag = buf[8], .data = .{ buf[9], buf[10], buf[11] } },
        .bg_color = .{ .tag = buf[12], .data = .{ buf[13], buf[14], buf[15] } },
    };
}
```

Similarly for `encodeRowHeader` / `decodeRowHeader` (9 bytes),
`encodeGraphemeTable` / `decodeGraphemeTable`, etc.

- [ ] **Step 5: Implement RLE encoding/decoding**

```zig
/// RLE run: 2 bytes run_length + 16 bytes CellData = 18 bytes
pub const RLE_RUN_SIZE: usize = 18;

pub fn encodeRleRun(run_length: u16, cell: CellData, out: *[RLE_RUN_SIZE]u8) void {
    std.mem.writeInt(u16, out[0..2], run_length, .little);
    encodeCellData(cell, out[2..18]);
}

pub fn decodeRleRun(buf: *const [RLE_RUN_SIZE]u8) struct { run_length: u16, cell: CellData } {
    return .{
        .run_length = std.mem.readInt(u16, buf[0..2], .little),
        .cell = decodeCellData(buf[2..18]),
    };
}
```

- [ ] **Step 6: Tests**

Test cases:

1. CellData comptime size check = 16 bytes
2. RowHeader comptime size check = 9 bytes
3. PackedColor constructors (default, palette, rgb)
4. CellData encode → decode round-trip (narrow cell, wide cell, with styles)
5. CellData with all style flags set
6. RowHeader encode → decode round-trip (with/without selection, RLE,
   semantic_prompt, hyperlink RLE)
7. RLE run encode → decode
8. GraphemeTable encode → decode (0 entries, 1 entry, multiple entries)
9. UnderlineColorTable encode → decode
10. CJK wide char: CellData with wide=1, followed by spacer_tail=2

- [ ] **Step 7: Commit**

```bash
git commit -m "feat(libitshell3-protocol): add CellData and binary cell types"
```

---

### Task 10: FrameUpdate Encoder/Decoder

**Files:**

- Create: `modules/libitshell3-protocol/src/frame_update.zig`
- Modify: `modules/libitshell3-protocol/src/root.zig`

**Spec ref:** Doc 04 §4 (FrameUpdate structure, frame header, sections)

FrameUpdate is the only hybrid binary+JSON message. Structure:

```
[16-byte protocol header (ENCODING=1)]
[20-byte binary frame header]
[DirtyRows section (if section_flags bit 4)]
[JSON metadata blob (if section_flags bit 5)]
```

- [ ] **Step 1: Define FrameHeader (20 bytes binary)**

```zig
pub const FRAME_HEADER_SIZE: usize = 20;

pub const FrameType = enum(u8) {
    p_frame = 0, // Partial (delta)
    i_frame = 1, // Keyframe (full)
};

pub const Screen = enum(u8) {
    primary = 0,
    alternate = 1,
};

pub const SectionFlags = struct {
    pub const dirty_rows: u16 = 1 << 4;
    pub const json_metadata: u16 = 1 << 7;
};

pub const FrameHeader = struct {
    session_id: u32,
    pane_id: u32,
    frame_sequence: u64,
    frame_type: FrameType,
    screen: Screen,
    section_flags: u16,

    pub fn encode(self: FrameHeader, buf: *[FRAME_HEADER_SIZE]u8) void {
        std.mem.writeInt(u32, buf[0..4], self.session_id, .little);
        std.mem.writeInt(u32, buf[4..8], self.pane_id, .little);
        std.mem.writeInt(u64, buf[8..16], self.frame_sequence, .little);
        buf[16] = @intFromEnum(self.frame_type);
        buf[17] = @intFromEnum(self.screen);
        std.mem.writeInt(u16, buf[18..20], self.section_flags, .little);
    }

    pub fn decode(buf: *const [FRAME_HEADER_SIZE]u8) FrameHeader {
        return .{
            .session_id = std.mem.readInt(u32, buf[0..4], .little),
            .pane_id = std.mem.readInt(u32, buf[4..8], .little),
            .frame_sequence = std.mem.readInt(u64, buf[8..16], .little),
            .frame_type = @enumFromInt(buf[16]),
            .screen = @enumFromInt(buf[17]),
            .section_flags = std.mem.readInt(u16, buf[18..20], .little),
        };
    }
};
```

- [ ] **Step 2: Implement DirtyRows encoder**

Writes: `num_dirty_rows (u16)` then per row: `RowHeader (9B)` + cells (16B each
or 18B RLE runs) + `GraphemeTable` + `UnderlineColorTable`.

```zig
pub const DirtyRow = struct {
    header: cell.RowHeader,
    cells: []const cell.CellData,        // Individual cells (if not RLE)
    grapheme_entries: []const cell.GraphemeEntry = &.{},
    underline_color_entries: []const cell.UnderlineColorEntry = &.{},
};

/// Encode dirty rows into a buffer. Returns bytes written.
pub fn encodeDirtyRows(rows: []const DirtyRow, writer: anytype) !void {
    // Write num_dirty_rows
    var count_buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &count_buf, @intCast(rows.len), .little);
    try writer.writeAll(&count_buf);

    for (rows) |row| {
        // Encode row header
        var rh_buf: [cell.RowHeader.SIZE]u8 = undefined;
        cell.encodeRowHeader(row.header, &rh_buf);
        try writer.writeAll(&rh_buf);

        // Encode cells
        for (row.cells) |c| {
            var cell_buf: [16]u8 = undefined;
            cell.encodeCellData(c, &cell_buf);
            try writer.writeAll(&cell_buf);
        }

        // Encode grapheme table
        // ... (num_entries u16 + entries)

        // Encode underline color table
        // ... (num_entries u16 + entries)
    }
}
```

- [ ] **Step 3: Implement DirtyRows decoder**

Read from buffer, produce `[]DirtyRow`.

- [ ] **Step 4: JSON metadata blob type**

```zig
pub const FrameMetadata = struct {
    cursor: ?CursorInfo = null,
    colors: ?ColorInfo = null,
    cursor_keypad_app_mode: ?bool = null,
    mouse_tracking_mode: ?u8 = null,
    mouse_button_reporting: ?bool = null,
    mouse_any_event_reporting: ?bool = null,

    pub const CursorInfo = struct {
        x: u16 = 0,
        y: u16 = 0,
        visible: bool = true,
        style: u8 = 0,
        blinking: bool = true,
    };

    pub const ColorInfo = struct {
        fg: ?cell.PackedColorJson = null,
        bg: ?cell.PackedColorJson = null,
        palette: ?[]const [3]u8 = null, // 256 entries, I-frame only
    };
};
```

- [ ] **Step 5: Full FrameUpdate encode/decode**

Combines: FrameHeader + DirtyRows + JSON metadata into single payload buffer.

- [ ] **Step 6: Tests**

Test cases:

1. FrameHeader encode → decode round-trip
2. Empty P-frame (no dirty rows, JSON metadata only)
3. I-frame with 1 dirty row (3 cells)
4. I-frame with multiple dirty rows
5. P-frame with RLE-encoded row
6. Wide char row (wide=1 + spacer_tail=2 pair)
7. Row with grapheme entries
8. Frame with all sections (dirty rows + JSON metadata)
9. Frame metadata JSON round-trip

- [ ] **Step 7: Commit**

```bash
git commit -m "feat(libitshell3-protocol): add FrameUpdate binary encoder/decoder"
```

---

### Task 11: Frame Reader + Writer + Sequence Tracker

**Files:**

- Create: `modules/libitshell3-protocol/src/reader.zig`
- Create: `modules/libitshell3-protocol/src/writer.zig`
- Modify: `modules/libitshell3-protocol/src/root.zig`

**Spec ref:** Doc 01 §3.3 (wire format), §3.4 (sequence numbers)

- [ ] **Step 1: Implement frame reader**

```zig
const std = @import("std");
const header_mod = @import("header.zig");

pub const Frame = struct {
    header: header_mod.Header,
    payload: []const u8,
};

pub const ReadError = header_mod.HeaderError || error{
    EndOfStream,
    ConnectionReset,
};

/// Read one complete frame from a stream.
/// `payload_buf` must be large enough for the payload (up to 16 MiB).
/// Returns the frame with payload slice into `payload_buf`.
pub fn readFrame(reader: anytype, payload_buf: []u8) (ReadError || @TypeOf(reader).Error)!Frame {
    var hdr_buf: [header_mod.HEADER_SIZE]u8 = undefined;
    reader.readNoEof(&hdr_buf) catch |err| switch (err) {
        error.EndOfStream => return error.EndOfStream,
        else => return @errorCast(err),
    };
    const hdr = try header_mod.Header.decode(&hdr_buf);
    if (hdr.payload_len > payload_buf.len)
        return error.PayloadTooLarge;
    const payload = payload_buf[0..hdr.payload_len];
    if (payload.len > 0) {
        reader.readNoEof(payload) catch |err| switch (err) {
            error.EndOfStream => return error.EndOfStream,
            else => return @errorCast(err),
        };
    }
    return .{ .header = hdr, .payload = payload };
}
```

- [ ] **Step 2: Implement frame writer**

```zig
const header_mod = @import("header.zig");

/// Write a complete frame (header + payload) to a writer.
pub fn writeFrame(writer: anytype, hdr: header_mod.Header, payload: []const u8) @TypeOf(writer).Error!void {
    var hdr_buf: [header_mod.HEADER_SIZE]u8 = undefined;
    hdr.encode(&hdr_buf);
    try writer.writeAll(&hdr_buf);
    if (payload.len > 0) {
        try writer.writeAll(payload);
    }
}
```

- [ ] **Step 3: Implement SequenceTracker**

```zig
/// Monotonically increasing sequence counter per direction.
/// Starts at 1. Wraps from 0xFFFFFFFF back to 1 (skipping 0).
pub const SequenceTracker = struct {
    next: u32 = 1,

    pub fn advance(self: *SequenceTracker) u32 {
        const seq = self.next;
        self.next = if (self.next == 0xFFFFFFFF) 1 else self.next + 1;
        return seq;
    }
};
```

- [ ] **Step 4: Tests**

Test cases:

1. Write frame → read frame round-trip (JSON message)
2. Write frame → read frame round-trip (binary message, empty payload)
3. Write frame → read frame round-trip (large payload near 16 MiB)
4. Multiple frames written back-to-back, all read correctly
5. Read from stream with bad magic → error
6. Read from stream that ends mid-header → EndOfStream
7. Read from stream that ends mid-payload → EndOfStream
8. SequenceTracker starts at 1
9. SequenceTracker wraps from 0xFFFFFFFF → 1 (skipping 0)
10. Sequence 0 is never produced by advance()

- [ ] **Step 5: Commit**

```bash
git commit -m "feat(libitshell3-protocol): add frame reader, writer, and sequence tracker"
```

---

### Task 12: Socket Path Resolution + Transport Interface

**Files:**

- Create: `modules/libitshell3-protocol/src/socket_path.zig`
- Create: `modules/libitshell3-protocol/src/transport.zig`
- Modify: `modules/libitshell3-protocol/src/root.zig`

**Spec ref:** Doc 01 §2.1 (Unix Domain Socket), §2.2 (SSH Tunneling)

- [ ] **Step 1: Implement socket path resolution**

```zig
// socket_path.zig
const std = @import("std");

pub const MAX_SOCKET_PATH: usize = 104; // macOS sockaddr_un limit

/// Resolve the socket path for a given server-id.
/// Priority: $ITSHELL3_SOCKET > $XDG_RUNTIME_DIR > $TMPDIR > /tmp
pub fn resolve(
    buf: *[MAX_SOCKET_PATH]u8,
    server_id: []const u8,
) error{PathTooLong}![]const u8 {
    // 1. Check $ITSHELL3_SOCKET
    if (std.posix.getenv("ITSHELL3_SOCKET")) |path| {
        if (path.len >= MAX_SOCKET_PATH) return error.PathTooLong;
        @memcpy(buf[0..path.len], path);
        return buf[0..path.len];
    }

    const uid = std.os.linux.getuid(); // or std.c.getuid() on macOS

    // 2. $XDG_RUNTIME_DIR/itshell3/<server_id>.sock
    if (std.posix.getenv("XDG_RUNTIME_DIR")) |xdg| {
        return formatPath(buf, xdg, "itshell3", server_id, null);
    }

    // 3. $TMPDIR/itshell3-<uid>/<server_id>.sock
    if (std.posix.getenv("TMPDIR")) |tmpdir| {
        return formatPath(buf, tmpdir, null, server_id, uid);
    }

    // 4. /tmp/itshell3-<uid>/<server_id>.sock
    return formatPath(buf, "/tmp", null, server_id, uid);
}

fn formatPath(
    buf: *[MAX_SOCKET_PATH]u8,
    base: []const u8,
    subdir: ?[]const u8,
    server_id: []const u8,
    uid: ?u32,
) error{PathTooLong}![]const u8 {
    // Build path: base/itshell3[-uid]/server_id.sock
    // ... (use std.fmt.bufPrint)
}

/// Ensure the socket directory exists with 0700 permissions.
pub fn ensureDirectory(path: []const u8) !void {
    const dir = std.fs.path.dirname(path) orelse return;
    std.posix.mkdir(dir, 0o700) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}
```

- [ ] **Step 2: Define transport interface**

```zig
// transport.zig — abstracts connection I/O for testability
const std = @import("std");

/// Transport provides a bidirectional byte stream.
/// Implemented by UnixTransport (real) and BufferTransport (testing).
pub const Transport = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        read: *const fn (ptr: *anyopaque, buf: []u8) ReadError!usize,
        write: *const fn (ptr: *anyopaque, data: []const u8) WriteError!void,
        close: *const fn (ptr: *anyopaque) void,
        fd: *const fn (ptr: *anyopaque) std.posix.fd_t,
    };

    pub const ReadError = error{ EndOfStream, ConnectionReset, Unexpected };
    pub const WriteError = error{ BrokenPipe, ConnectionReset, Unexpected };

    pub fn read(self: Transport, buf: []u8) ReadError!usize {
        return self.vtable.read(self.ptr, buf);
    }
    pub fn write(self: Transport, data: []const u8) WriteError!void {
        return self.vtable.write(self.ptr, data);
    }
    pub fn close(self: Transport) void {
        self.vtable.close(self.ptr);
    }
    pub fn fd(self: Transport) std.posix.fd_t {
        return self.vtable.fd(self.ptr);
    }
};

/// Real Unix socket transport.
pub const UnixTransport = struct {
    socket_fd: std.posix.fd_t,
    // ... vtable implementation wrapping posix read/write/close
};

/// Server-side: bind + listen + accept.
pub fn listen(socket_path: []const u8) !Listener {
    // Probe for stale socket, unlink if stale, bind, listen
    // Set SO_SNDBUF/SO_RCVBUF to 256 KiB
    // chmod 0600
}

/// Client-side: connect to existing socket.
pub fn connect(socket_path: []const u8) !UnixTransport {
    // Create AF_UNIX SOCK_STREAM, connect to path
}

pub const Listener = struct {
    listen_fd: std.posix.fd_t,
    socket_path_storage: [socket_path_mod.MAX_SOCKET_PATH]u8,
    socket_path_len: usize,

    pub fn accept(self: *Listener) !UnixTransport {
        // posix.accept, wrap in UnixTransport
    }

    pub fn deinit(self: *Listener) void {
        std.posix.close(self.listen_fd);
        // unlink socket file
    }
};

/// Mock transport for tests (backed by fixed buffers or pipe pair).
pub const BufferTransport = struct {
    // Read from one buffer, write to another — for testing
};
```

- [ ] **Step 3: Tests**

Test cases:

1. Socket path resolution: $ITSHELL3_SOCKET overrides all
2. Socket path resolution: XDG_RUNTIME_DIR fallback
3. Socket path resolution: TMPDIR fallback
4. Socket path resolution: /tmp fallback with UID
5. Path too long → error
6. BufferTransport: write then read round-trip
7. UnixTransport: real socket pair (socketpair) read/write
8. Listener: bind + accept (real socket, pipe-like isolation)
9. connect: connect to listening socket
10. Stale socket probe + cleanup on listen

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(libitshell3-protocol): add socket path resolution and transport layer"
```

---

### Task 13: Connection State Machine + UID Authentication

**Files:**

- Create: `modules/libitshell3-protocol/src/connection.zig`
- Create: `modules/libitshell3-protocol/src/auth.zig`
- Modify: `modules/libitshell3-protocol/src/root.zig`

**Spec ref:** Doc 01 §5.1-5.3 (Connection lifecycle state machine), §12.1 (Unix
socket authentication)

- [ ] **Step 1: Implement connection state machine**

```zig
// connection.zig
const std = @import("std");
const header_mod = @import("header.zig");
const message_type_mod = @import("message_type.zig");
const transport_mod = @import("transport.zig");
const reader_mod = @import("reader.zig");
const writer_mod = @import("writer.zig");

pub const ConnectionState = enum {
    disconnected,
    connecting,
    handshaking,
    ready,
    operating,
    disconnecting,
};

pub const Connection = struct {
    transport: transport_mod.Transport,
    state: ConnectionState,
    client_id: ?u32,                    // Assigned by server in ServerHello
    attached_session_id: ?u32,          // Set when OPERATING
    send_seq: writer_mod.SequenceTracker,
    recv_seq_last: u32,                 // Last received sequence number
    negotiated_caps: NegotiatedCaps,

    pub const NegotiatedCaps = struct {
        clipboard_sync: bool = false,
        mouse: bool = false,
        selection: bool = false,
        search: bool = false,
        fd_passing: bool = false,
        preedit: bool = false,
    };

    pub fn init(transport: transport_mod.Transport) Connection {
        return .{
            .transport = transport,
            .state = .handshaking,
            .client_id = null,
            .attached_session_id = null,
            .send_seq = .{},
            .recv_seq_last = 0,
            .negotiated_caps = .{},
        };
    }

    /// Validate that a message type is allowed in the current state.
    pub fn validateMessageType(self: *const Connection, msg_type: message_type_mod.MessageType) error{InvalidState}!void {
        switch (self.state) {
            .handshaking => switch (msg_type) {
                .client_hello, .server_hello, .@"error", .disconnect => {},
                else => return error.InvalidState,
            },
            .ready => switch (msg_type) {
                .create_session_request, .create_session_response,
                .list_sessions_request, .list_sessions_response,
                .attach_session_request, .attach_session_response,
                .attach_or_create_request, .attach_or_create_response,
                .heartbeat, .heartbeat_ack,
                .disconnect, .@"error",
                .client_display_info, .client_display_info_ack,
                => {},
                else => return error.InvalidState,
            },
            .operating => {}, // All message types allowed
            .disconnecting => switch (msg_type) {
                .disconnect, .@"error" => {},
                else => return error.InvalidState,
            },
            .disconnected, .connecting => return error.InvalidState,
        }
    }

    /// Transition: handshaking → ready (after successful handshake)
    pub fn completeHandshake(self: *Connection, client_id: u32, caps: NegotiatedCaps) error{InvalidTransition}!void {
        if (self.state != .handshaking) return error.InvalidTransition;
        self.state = .ready;
        self.client_id = client_id;
        self.negotiated_caps = caps;
    }

    /// Transition: ready → operating (after session attach/create)
    pub fn attachSession(self: *Connection, session_id: u32) error{InvalidTransition}!void {
        if (self.state != .ready) return error.InvalidTransition;
        self.state = .operating;
        self.attached_session_id = session_id;
    }

    /// Transition: operating → ready (detach or session destroyed)
    pub fn detachSession(self: *Connection) error{InvalidTransition}!void {
        if (self.state != .operating) return error.InvalidTransition;
        self.state = .ready;
        self.attached_session_id = null;
    }

    /// Transition: ready|operating → disconnecting
    pub fn beginDisconnect(self: *Connection) error{InvalidTransition}!void {
        switch (self.state) {
            .ready, .operating => self.state = .disconnecting,
            else => return error.InvalidTransition,
        }
    }

    /// Transition: disconnecting → disconnected
    pub fn completeDisconnect(self: *Connection) void {
        self.transport.close();
        self.state = .disconnected;
    }
};
```

- [ ] **Step 2: Implement UID authentication**

```zig
// auth.zig
const std = @import("std");

pub const AuthError = error{
    UidMismatch,
    GetPeerCredFailed,
};

/// Verify that the peer on `fd` has the same UID as this process.
/// Uses getpeereid() on macOS/BSD, SO_PEERCRED on Linux.
pub fn verifyPeerUid(fd: std.posix.fd_t) AuthError!u32 {
    if (@import("builtin").os.tag == .macos or @import("builtin").os.tag == .freebsd) {
        var euid: std.posix.uid_t = undefined;
        var egid: std.posix.gid_t = undefined;
        const rc = std.c.getpeereid(fd, &euid, &egid);
        if (rc != 0) return error.GetPeerCredFailed;
        const my_uid = std.c.getuid();
        if (euid != my_uid) return error.UidMismatch;
        return euid;
    } else {
        // Linux: SO_PEERCRED
        // ... getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &ucred)
    }
}
```

- [ ] **Step 3: Tests**

Test cases:

1. Connection init → state is `handshaking`
2. completeHandshake: handshaking → ready, client_id set
3. completeHandshake from ready → error
4. attachSession: ready → operating, session_id set
5. attachSession from handshaking → error
6. detachSession: operating → ready, session_id cleared
7. beginDisconnect from operating → disconnecting
8. beginDisconnect from ready → disconnecting
9. beginDisconnect from handshaking → error
10. validateMessageType: handshaking allows only hello/error/disconnect
11. validateMessageType: ready allows session management + heartbeat
12. validateMessageType: operating allows everything
13. validateMessageType: disconnecting allows only disconnect/error
14. verifyPeerUid: same UID succeeds (real socketpair test)
15. verifyPeerUid: function returns without crash on valid fd

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(libitshell3-protocol): add connection state machine and UID auth"
```

---

### Task 14: Handshake Orchestration

**Files:**

- Create: `modules/libitshell3-protocol/src/handshake_io.zig`
- Modify: `modules/libitshell3-protocol/src/root.zig`

**Spec ref:** Doc 02 §1-4 (Handshake sequence, capability negotiation)

Provides high-level handshake functions used by both server and client.

- [ ] **Step 1: Implement server-side handshake**

```zig
// handshake_io.zig
const std = @import("std");
const header_mod = @import("header.zig");
const json_mod = @import("json.zig");
const handshake_mod = @import("handshake.zig");
const connection_mod = @import("connection.zig");
const reader_mod = @import("reader.zig");
const writer_mod = @import("writer.zig");
const message_type_mod = @import("message_type.zig");
const auth_mod = @import("auth.zig");

pub const HandshakeError = error{
    VersionMismatch,
    AuthFailed,
    Timeout,
    MalformedPayload,
    UnexpectedMessage,
} || auth_mod.AuthError || reader_mod.ReadError || writer_mod.WriteError;

pub const ServerHandshakeResult = struct {
    client_hello: handshake_mod.ClientHello,
    client_id: u32,
    negotiated_caps: connection_mod.Connection.NegotiatedCaps,
};

/// Server side: read ClientHello, verify UID, negotiate caps, send ServerHello.
/// Transitions connection from handshaking → ready.
pub fn performServerHandshake(
    conn: *connection_mod.Connection,
    allocator: std.mem.Allocator,
    server_config: ServerConfig,
    payload_buf: []u8,
) HandshakeError!ServerHandshakeResult {
    // 1. Authenticate UID
    const peer_uid = try auth_mod.verifyPeerUid(conn.transport.fd());
    _ = peer_uid; // UID verified (same-UID only)

    // 2. Read ClientHello
    const frame = try reader_mod.readFrame(conn.transport.reader(), payload_buf);
    if (frame.header.msg_type != @intFromEnum(message_type_mod.MessageType.client_hello))
        return error.UnexpectedMessage;

    const parsed = json_mod.decode(handshake_mod.ClientHello, allocator, frame.payload)
        catch return error.MalformedPayload;
    defer parsed.deinit();
    const client_hello = parsed.value;

    // 3. Negotiate version
    if (server_config.protocol_version < client_hello.protocol_version_min or
        server_config.protocol_version > client_hello.protocol_version_max)
        return error.VersionMismatch;

    // 4. Negotiate capabilities (intersection)
    const caps = negotiateCapabilities(client_hello.capabilities, server_config.supported_caps);

    // 5. Send ServerHello
    const server_hello = buildServerHello(server_config, caps, client_hello);
    const json_payload = try json_mod.encode(allocator, server_hello);
    defer allocator.free(json_payload);

    const hdr = header_mod.Header{
        .msg_type = @intFromEnum(message_type_mod.MessageType.server_hello),
        .flags = .{ .response = true },
        .payload_len = @intCast(json_payload.len),
        .sequence = frame.header.sequence, // echo client's sequence
    };
    try writer_mod.writeFrame(conn.transport.writer(), hdr, json_payload);

    // 6. Transition state
    try conn.completeHandshake(server_config.next_client_id, caps);

    return .{
        .client_hello = client_hello,
        .client_id = server_config.next_client_id,
        .negotiated_caps = caps,
    };
}

pub const ServerConfig = struct {
    protocol_version: u32 = 1,
    next_client_id: u32,
    server_pid: u32,
    server_name: []const u8 = "itshell3d",
    server_version: []const u8 = "",
    supported_caps: []const []const u8 = &.{},
    supported_input_methods: []const handshake_mod.ServerHello.InputMethodInfo = &.{},
};

fn negotiateCapabilities(
    client_caps: []const []const u8,
    server_caps: []const []const u8,
) connection_mod.Connection.NegotiatedCaps {
    // Intersection of client and server capability lists
    // ...
}
```

- [ ] **Step 2: Implement client-side handshake**

```zig
pub const ClientHandshakeResult = struct {
    server_hello: handshake_mod.ServerHello,
    client_id: u32,
    negotiated_caps: connection_mod.Connection.NegotiatedCaps,
};

/// Client side: send ClientHello, read ServerHello, negotiate.
/// Transitions connection from handshaking → ready.
pub fn performClientHandshake(
    conn: *connection_mod.Connection,
    allocator: std.mem.Allocator,
    client_hello: handshake_mod.ClientHello,
    payload_buf: []u8,
) HandshakeError!ClientHandshakeResult {
    // 1. Send ClientHello
    const json_payload = try json_mod.encode(allocator, client_hello);
    defer allocator.free(json_payload);

    const seq = conn.send_seq.advance();
    const hdr = header_mod.Header{
        .msg_type = @intFromEnum(message_type_mod.MessageType.client_hello),
        .flags = .{},
        .payload_len = @intCast(json_payload.len),
        .sequence = seq,
    };
    try writer_mod.writeFrame(conn.transport.writer(), hdr, json_payload);

    // 2. Read ServerHello
    const frame = try reader_mod.readFrame(conn.transport.reader(), payload_buf);
    if (frame.header.msg_type != @intFromEnum(message_type_mod.MessageType.server_hello))
        return error.UnexpectedMessage;

    const parsed = json_mod.decode(handshake_mod.ServerHello, allocator, frame.payload)
        catch return error.MalformedPayload;
    defer parsed.deinit();
    const server_hello = parsed.value;

    // 3. Build negotiated caps from server response
    const caps = buildCapsFromServerHello(server_hello);

    // 4. Transition state
    try conn.completeHandshake(server_hello.client_id, caps);

    return .{
        .server_hello = server_hello,
        .client_id = server_hello.client_id,
        .negotiated_caps = caps,
    };
}
```

- [ ] **Step 3: Tests**

Test cases (using BufferTransport or socketpair):

1. Server handshake: valid ClientHello → ServerHello sent, state → ready
2. Client handshake: send ClientHello → receive ServerHello, state → ready
3. Full round-trip: client handshake ↔ server handshake over socketpair
4. Version mismatch: client sends version 2, server supports 1 → error
5. Capability negotiation: intersection of client + server caps
6. Malformed ClientHello → error.MalformedPayload
7. Unexpected message type → error.UnexpectedMessage
8. After handshake: connection.client_id is set
9. After handshake: connection.negotiated_caps reflects intersection

- [ ] **Step 4: Commit**

```bash
git commit -m "feat(libitshell3-protocol): add handshake orchestration"
```

---

### Task 15: Migrate libitshell3 Transport → Protocol

**Files:**

- Modify: `modules/libitshell3/build.zig` — add `libitshell3-protocol`
  dependency
- Modify: `modules/libitshell3/build.zig.zon` — add protocol dependency
- Delete: `modules/libitshell3/src/os/socket.zig`
- Delete: `modules/libitshell3/src/server/listener.zig`
- Delete: `modules/libitshell3/src/server/client.zig`
- Modify: `modules/libitshell3/src/os/interfaces.zig` — remove SocketOps
- Modify: `modules/libitshell3/src/os/root.zig` — remove socket re-exports
- Modify: `modules/libitshell3/src/root.zig` — add protocol re-export
- Modify: `modules/libitshell3/src/server/event_loop.zig` — use protocol types
- Modify: `modules/libitshell3/src/server/handlers/*.zig` — use protocol types
- Modify: `modules/libitshell3/src/testing/mock_os.zig` — remove MockSocketOps
- Modify: `modules/libitshell3/src/testing/helpers.zig` — use protocol transport

**Purpose:** The protocol library now owns transport, connection state, and
handshake. libitshell3 should depend on it rather than maintaining its own
socket/listener/client code.

- [ ] **Step 1: Add libitshell3-protocol as a dependency**

In `modules/libitshell3/build.zig.zon`:

```zig
.dependencies = .{
    .ghostty = .{ .path = "../../vendors/ghostty" },
    .@"itshell3-protocol" = .{ .path = "../libitshell3-protocol" },
},
```

In `modules/libitshell3/build.zig`, add a named import:

```zig
.{ .name = "itshell3_protocol", .module = b.dependency("itshell3-protocol", .{
    .target = target,
    .optimize = optimize,
}).module("itshell3-protocol") },
```

Verify: `(cd modules/libitshell3 && zig build)` compiles.

- [ ] **Step 2: Replace SocketOps with protocol Transport**

Update `os/interfaces.zig`:

- Remove `SocketOps` vtable definition (replaced by
  `protocol.transport.Transport`)
- Keep `PtyOps`, `EventLoopOps`, `SignalOps` (these are NOT in the protocol)

Update `os/root.zig`:

- Remove `socket` and `SocketOps` re-exports

- [ ] **Step 3: Replace server/listener.zig with protocol Listener**

Update `server/event_loop.zig` and `server/handlers/client_accept.zig`:

- Import `@import("itshell3_protocol")` instead of `../os/interfaces.zig`
- Use `protocol.transport.Listener` instead of `server.Listener`
- Use `protocol.transport.Transport` instead of raw fd for client connections

Delete `server/listener.zig`.

- [ ] **Step 4: Replace server/client.zig with protocol Connection**

Update all code that uses `ClientState`:

- Replace `ClientState` with `protocol.connection.Connection`
- The state machine is now richer (includes sequence tracking, caps, etc.)
- `client.zig`'s state transitions map directly to `Connection` methods

Delete `server/client.zig`.

- [ ] **Step 5: Delete os/socket.zig**

The real Unix socket operations are now in `protocol/transport.zig`. Delete
`os/socket.zig`.

- [ ] **Step 6: Update MockSocketOps → use protocol BufferTransport**

In `testing/mock_os.zig`:

- Remove `MockSocketOps` (no longer needed — protocol has `BufferTransport`)
- Update test helpers to use `protocol.transport.BufferTransport`

In `testing/helpers.zig`:

- Remove `tempSocketPath` helper if it's socket-specific
- Update integration test setup to use protocol transport

- [ ] **Step 7: Verify both modules build and all tests pass**

```bash
(cd modules/libitshell3-protocol && zig build test)
(cd modules/libitshell3 && zig build test)
```

All existing libitshell3 tests must still pass. Some test counts may decrease
(socket-specific tests moved to protocol) but no logic should be lost.

- [ ] **Step 8: Commit**

```bash
git add modules/libitshell3/ modules/libitshell3-protocol/
git commit -m "refactor(libitshell3): migrate transport/connection to libitshell3-protocol"
```

---

### Task 16: Integration Tests

**Files:**

- Modify: `modules/libitshell3-protocol/src/root.zig` (add integration test
  imports)

**Purpose:** Verify end-to-end message lifecycle: create message struct →
JSON/binary encode → wrap in frame → write to stream → read frame → decode
payload → verify matches original.

- [ ] **Step 1: Handshake round-trip integration test**

Create → JSON encode → create header → write frame → read frame → decode JSON →
verify ClientHello/ServerHello fields match.

- [ ] **Step 2: Session/pane message round-trip**

Test CreateSessionRequest and LayoutChanged through the full pipeline.

- [ ] **Step 3: FrameUpdate binary integration test**

Create a FrameUpdate with:

- FrameHeader (I-frame, primary screen)
- 2 dirty rows (one regular, one RLE-encoded)
- JSON metadata (cursor + palette)

Write as binary payload in a frame, read back, decode, verify all fields.

- [ ] **Step 4: Multi-message stream test**

Write 5 different message types to a buffer, read them all back in order. Verify
sequence numbers are maintained correctly.

- [ ] **Step 5: Error response round-trip**

Verify Error (0x00FF) message encodes/decodes with RESPONSE + ERROR flags.

- [ ] **Step 6: Full connection lifecycle integration test**

Over a real socketpair:

1. Server: listen → accept → performServerHandshake
2. Client: connect → performClientHandshake
3. Client sends CreateSessionRequest
4. Server validates state (READY allows it)
5. Server sends CreateSessionResponse
6. Both sides transition to OPERATING
7. Client sends KeyEvent (only allowed in OPERATING)
8. Client sends Disconnect, both sides transition to DISCONNECTING →
   DISCONNECTED

- [ ] **Step 7: Cross-module integration test**

Verify libitshell3's event loop works with protocol transport:

1. Create a protocol Listener
2. libitshell3 event loop registers listener fd
3. Client connects via protocol transport
4. Event loop fires client_accept handler
5. Handler creates protocol Connection

- [ ] **Step 8: Run full test suite for both modules, commit**

```bash
(cd modules/libitshell3-protocol && zig build test)
(cd modules/libitshell3 && zig build test)
git commit -m "feat(libitshell3-protocol): add integration tests"
```

---

## Deferred Scope

These are NOT in this plan — they will be addressed in later plans:

1. **Fragmentation** (Doc 01 §3.6) — reassembly of >1 MiB messages. Deferred
   until large scrollback queries are implemented.
2. **Ring buffer integration** — Plan 4 (per-pane ring, per-client cursors).
3. **SSH tunneling** (Doc 01 §2.2) — Phase 5. The Transport interface is defined
   (Task 12) but only UnixTransport is implemented.
