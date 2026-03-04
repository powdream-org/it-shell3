# Testing Strategy

## Overview

libitshell3 is a Zig library with a clear boundary: bytes in, bytes out. It does not render anything or receive OS-level input events (those belong to the it-shell3 app layer). This makes ~85-90% of the library automatically testable using Zig's built-in `test` infrastructure with no external frameworks or GUI dependencies.

---

## Testing Tiers

### Tier 1: Pure Unit Tests (No OS Resources)

These are fast, deterministic, and can run anywhere (CI, cross-compilation, even WASM).

| Module | What to Test | Approach |
|--------|-------------|----------|
| **Protocol message encoding/decoding** | Serialize a message → deserialize → assert roundtrip equality | Pure functions, no I/O |
| **Wire framing** | Feed raw bytes → assert correctly parsed message boundaries, handle partial reads, oversized messages | Feed byte slices of various sizes |
| **Handshake capability negotiation** | Client offers caps → server selects → assert agreed caps match expectations | Struct-level logic, no sockets |
| **Session/Tab/Pane state** | Create session → add tabs → add panes → close pane → assert tree shape | In-memory CRUD on data structures |
| **Layout tree operations** | Split → resize → equalize → close → swap → assert dimensions and topology | Pure binary tree operations |
| **Layout serialization** | Build tree → serialize to JSON → deserialize → assert structurally equal | Roundtrip test |
| **CJK preedit state machine** | Feed IME events (start, update, end, cancel) → assert state transitions | Enum state machine |
| **Korean Jamo decomposition** | `한` + backspace → `하`, `하` + backspace → `ㅎ`, `ㅎ` + backspace → empty | Unicode string functions |
| **Ambiguous width resolution** | Codepoint → width(1 or 2) given config | Lookup table + config flag |
| **Snapshot serialization** | Build full session state → serialize → deserialize → assert equal | JSON roundtrip |
| **Configuration parsing** | Config string/file → parsed config struct → assert values | String parsing |
| **Key event encoding** | KeyEvent struct → wire bytes → assert matches expected escape sequences | Pure encoding functions |
| **Command parsing** | Command string → parsed command struct → assert fields | String parsing |

**Zig example:**

```zig
const testing = @import("std").testing;
const protocol = @import("protocol/Message.zig");

test "message roundtrip - preedit update" {
    const original = protocol.Message{
        .preedit_update = .{
            .pane_id = 42,
            .text = "한",
            .cursor_x = 10,
            .cursor_y = 5,
        },
    };

    var buf: [512]u8 = undefined;
    const encoded_len = original.encode(&buf);
    const decoded = try protocol.Message.decode(buf[0..encoded_len]);

    try testing.expectEqual(original.preedit_update.pane_id, decoded.preedit_update.pane_id);
    try testing.expectEqualStrings(original.preedit_update.text, decoded.preedit_update.text);
    try testing.expectEqual(original.preedit_update.cursor_x, decoded.preedit_update.cursor_x);
    try testing.expectEqual(original.preedit_update.cursor_y, decoded.preedit_update.cursor_y);
}

test "layout tree - split and close" {
    const Layout = @import("daemon/Layout.zig");
    var tree = Layout.init(.{ .pane_id = 1 });

    // Split pane 1 horizontally → creates pane 2
    const pane2 = try tree.split(1, .horizontal);
    try testing.expectEqual(tree.root.nodeType(), .split);
    try testing.expectEqual(tree.paneCount(), 2);

    // Close pane 2 → tree collapses back to single pane
    try tree.close(pane2);
    try testing.expectEqual(tree.root.nodeType(), .leaf);
    try testing.expectEqual(tree.paneCount(), 1);
}

test "jamo decomposition - backspace through 한" {
    const jamo = @import("unicode/CjkState.zig");

    // 한 (U+D55C) = ㅎ + ㅏ + ㄴ
    var state = jamo.PreeditState.init("한");

    // Backspace removes final consonant ㄴ → 하
    state.backspace();
    try testing.expectEqualStrings("하", state.text());

    // Backspace removes vowel ㅏ → ㅎ
    state.backspace();
    try testing.expectEqualStrings("ㅎ", state.text());

    // Backspace removes initial consonant → empty
    state.backspace();
    try testing.expectEqualStrings("", state.text());
    try testing.expect(!state.isActive());
}
```

---

### Tier 2: OS Integration Tests (Real Sockets, PTYs, Processes)

These use real OS resources but don't need a GUI or display. They run in CI on any macOS/Linux runner.

| Module | What to Test | Approach |
|--------|-------------|----------|
| **PTY creation + I/O** | `openpty()` → fork shell → write `echo hello\n` → read → assert `hello` in output | Real PTY, real fork |
| **PTY IUTF8 flag** | Create PTY → read `termios` → assert `IUTF8` bit set | `tcgetattr` check |
| **PTY resize** | Create PTY → `TIOCSWINSZ` → read back → assert dimensions match | ioctl roundtrip |
| **Child process lifecycle** | Fork shell → kill → assert `SIGCHLD` reaped, pane state = exited | Signal handling |
| **Daemon socket lifecycle** | Start daemon in-process → client connects → handshake → disconnect → assert clean shutdown | `socketpair` or real Unix socket |
| **Multi-client session** | Daemon → client A attaches → client B attaches → pane output → assert both receive it | Two socket connections |
| **Client detach/reattach** | Client attaches → detaches → daemon keeps session → client reattaches → assert session state intact | Socket disconnect + reconnect |
| **Command/response over socket** | Client sends command → daemon responds between begin/end → client callback fires | Full protocol round-trip |
| **FD passing** | Send PTY fd via `sendmsg` SCM_RIGHTS → receive via `recvmsg` → write to received fd → assert PTY slave receives data | cmsg ancillary data |
| **Daemon fork-to-background** | Start daemon → assert it daemonizes → connect from "client" → assert working | `fork` + `setsid` |
| **Session snapshot + restore** | Create session with 3 panes → snapshot to file → stop daemon → start new daemon → restore → assert layout matches | File I/O + state comparison |
| **Scrollback persistence** | Write 5000 lines to pane → snapshot → restore → assert last N lines preserved (within limit) | PTY output + file I/O |
| **Concurrent preedit from two clients** | Client A starts preedit → client B starts preedit on same pane → assert last-writer-wins or error | Two connections, interleaved messages |
| **Backpressure / flow control** | Flood pane with output → assert pause sent to slow client → drain → assert continue sent | Fast writer + slow reader |

**Zig example:**

```zig
const std = @import("std");
const testing = std.testing;
const posix = std.posix;
const Pty = @import("pty/Pty.zig");

test "pty - spawn shell and read output" {
    var pty = try Pty.open(.{ .ws_col = 80, .ws_row = 24 });
    defer pty.deinit();

    const pid = try posix.fork();
    if (pid == 0) {
        // Child: attach to slave, exec shell
        pty.childPreExec();
        const argv = [_:null]?[*:0]const u8{ "/bin/sh", "-c", "echo test_output", null };
        _ = posix.execvpeZ("/bin/sh", &argv, std.c.environ);
        unreachable;
    }

    // Parent: read from master
    var buf: [4096]u8 = undefined;
    const n = try posix.read(pty.master, &buf);
    const output = buf[0..n];

    try testing.expect(std.mem.indexOf(u8, output, "test_output") != null);

    // Reap child
    _ = posix.waitpid(pid, 0);
}

test "pty - IUTF8 flag is set" {
    var pty = try Pty.open(.{ .ws_col = 80, .ws_row = 24 });
    defer pty.deinit();

    var attrs: posix.termios = undefined;
    try posix.tcgetattr(pty.slave, &attrs);
    try testing.expect(attrs.c_iflag & posix.IUTF8 != 0);
}

test "daemon - client connect and handshake" {
    const Daemon = @import("daemon/Daemon.zig");
    const Client = @import("client/Client.zig");

    // Use a temp socket path
    const socket_path = "/tmp/itshell3-test.sock";
    defer posix.unlink(socket_path) catch {};

    // Start daemon in a separate thread
    var daemon = try Daemon.init(.{ .socket_path = socket_path });
    const daemon_thread = try std.Thread.spawn(.{}, Daemon.run, .{&daemon});

    // Give daemon time to bind
    std.time.sleep(50 * std.time.ns_per_ms);

    // Client connects
    var client = try Client.init(socket_path);
    defer client.deinit();

    const info = try client.handshake();
    try testing.expectEqual(@as(u8, 1), info.protocol_version);
    try testing.expect(info.cjk_capabilities & 0x01 != 0); // CJK_CAP_PREEDIT

    // Shutdown
    daemon.stop();
    daemon_thread.join();
}

test "multi-client - both receive pane output" {
    // Setup daemon with one pane running `echo hello`
    // Connect client A and client B
    // Assert both receive "hello" in their output callbacks
    // (full implementation omitted for brevity)
}
```

---

### Tier 3: End-to-End Integration Tests

Full daemon-client scenarios running as separate processes. These validate the real binary artifacts.

| Scenario | What to Test |
|----------|-------------|
| **CLI attach/detach** | Start daemon binary → attach client binary → run commands → detach → reattach → assert scrollback preserved |
| **Session listing** | Start daemon → create 3 sessions → run `itshell3 list-sessions` → assert all 3 listed |
| **Split layout round-trip** | Attach → split right → split down → detach → reattach → assert 3-pane layout restored |
| **Crash recovery** | Attach → start long-running process → kill client → reattach → assert process still running |
| **Daemon restart with persistence** | Create session → stop daemon gracefully → restart daemon → attach → assert session restored from snapshot |
| **CJK preedit over wire** | Client A sends preedit-start → preedit-update "ㅎ" → "하" → "한" → preedit-end → assert daemon state matches at each step |
| **Cross-version compatibility** | Client v2 connects to daemon v1 → assert graceful capability fallback (no CJK if server doesn't support it) |

**Test runner approach:**

```bash
#!/usr/bin/env bash
# e2e/test_attach_detach.sh

SOCKET="/tmp/itshell3-e2e-$$.sock"
DAEMON="./zig-out/bin/itshell3-daemon"
CLIENT="./zig-out/bin/itshell3-client"

# Start daemon
$DAEMON --socket "$SOCKET" --foreground &
DAEMON_PID=$!
sleep 0.1

# Attach, run command, capture output
OUTPUT=$($CLIENT --socket "$SOCKET" attach --session test --exec "echo e2e_marker" 2>&1)

# Assert
if echo "$OUTPUT" | grep -q "e2e_marker"; then
    echo "PASS: attach and command execution"
else
    echo "FAIL: expected e2e_marker in output"
    kill $DAEMON_PID
    exit 1
fi

# Detach and reattach
$CLIENT --socket "$SOCKET" detach
$CLIENT --socket "$SOCKET" attach --session test --exec "echo reattached" 2>&1 | grep -q "reattached"

# Cleanup
kill $DAEMON_PID
rm -f "$SOCKET"
echo "PASS: detach and reattach"
```

---

### Tier 4: Manual / GUI Tests (App Layer Only)

These belong to the **it-shell3 app**, not libitshell3. Listed here for completeness.

| What | Why Manual |
|------|-----------|
| libghostty Metal rendering | Needs GPU context and display |
| IME composition events (Korean, Japanese, Chinese) | Needs macOS input method system |
| Shift+Enter in AI agent context | Needs NSEvent from a real window |
| Cmd+C/V clipboard behavior | Needs NSPasteboard and pasteboard server |
| AI agent process detection | Needs actual agent process running |
| iOS client behavior | Needs iOS simulator or device |
| Visual layout correctness | Needs human eyes on split dividers, proportions |

**None of these are part of libitshell3.** The library boundary is clean: it deals in bytes, messages, PTY fds, and state — never in pixels or input events.

---

## Test Organization

```
tests/
├── unit/
│   ├── protocol_test.zig          # Message encode/decode roundtrips
│   ├── layout_test.zig            # Split tree operations
│   ├── session_state_test.zig     # Session/tab/pane CRUD
│   ├── preedit_state_test.zig     # CJK preedit state machine
│   ├── jamo_test.zig              # Korean Jamo decomposition
│   ├── snapshot_test.zig          # Serialization roundtrips
│   ├── config_test.zig            # Configuration parsing
│   ├── key_encoding_test.zig      # Key event → wire bytes
│   └── command_parse_test.zig     # Command string parsing
├── integration/
│   ├── pty_test.zig               # Real PTY creation, I/O, IUTF8
│   ├── daemon_test.zig            # Socket lifecycle, multi-client
│   ├── handshake_test.zig         # Full capability negotiation
│   ├── fd_passing_test.zig        # SCM_RIGHTS over Unix socket
│   ├── persistence_test.zig       # Snapshot + restore round-trip
│   ├── flow_control_test.zig      # Backpressure pause/continue
│   └── preedit_sync_test.zig      # Multi-client preedit scenario
└── e2e/
    ├── test_attach_detach.sh      # CLI-level attach/detach
    ├── test_session_list.sh       # Session enumeration
    ├── test_split_layout.sh       # Layout persistence
    ├── test_crash_recovery.sh     # Client crash + reattach
    └── test_daemon_restart.sh     # Daemon restart + restore
```

---

## CI Pipeline

```yaml
# .github/workflows/test.yml
name: Test
on: [push, pull_request]

jobs:
  unit:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
        with: { submodules: recursive }
      - name: Run unit tests
        run: zig build test -Dtest-filter="unit"

  integration:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
        with: { submodules: recursive }
      - name: Run integration tests
        run: zig build test -Dtest-filter="integration"

  e2e:
    runs-on: macos-latest
    needs: [unit, integration]
    steps:
      - uses: actions/checkout@v4
        with: { submodules: recursive }
      - name: Build
        run: zig build
      - name: Run e2e tests
        run: |
          for test in e2e/test_*.sh; do
            echo "--- Running $test ---"
            bash "$test"
          done

  # Future: linux job when Linux support is added
  # unit-linux:
  #   runs-on: ubuntu-latest
  #   ...
```

---

## Coverage Estimate

| Tier | % of libitshell3 | Automation | CI-Ready |
|------|-----------------|------------|----------|
| Tier 1: Unit | ~55% | Fully automatic | Yes |
| Tier 2: OS Integration | ~30% | Fully automatic (needs POSIX) | Yes (macOS runner) |
| Tier 3: E2E | ~10% | Scripted, automatic | Yes |
| Tier 4: Manual/GUI | ~5% | Manual | No (app layer) |
| **Total automated** | **~95%** | | |

The ~5% that requires manual testing belongs to the it-shell3 app layer (Swift/AppKit), not to libitshell3 itself. The library is designed so that its entire public API surface is testable without a display or GUI.
