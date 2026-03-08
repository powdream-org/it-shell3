# Testing Strategy

## Overview

libitshell3 is a Zig library with a clear boundary: bytes in, bytes out. It does not render anything or receive OS-level input events (those belong to the it-shell3 app layer). This makes ~85-90% of the library automatically testable using Zig's built-in `test` infrastructure with no external frameworks or GUI dependencies.

---

## Testing Tiers

### Tier 1: Pure Unit Tests (No OS Resources)

Fast, deterministic tests that can run anywhere (CI, cross-compilation, even WASM).

| Module | What to Test | Approach |
|--------|-------------|----------|
| **Protocol message encoding/decoding** | Serialize → deserialize → assert roundtrip equality | Pure functions, no I/O |
| **Wire framing** | Feed raw bytes → assert correctly parsed message boundaries, handle partial reads | Feed byte slices of various sizes |
| **Handshake capability negotiation** | Client offers caps → server selects → assert agreed caps match | Struct-level logic, no sockets |
| **Session/Tab/Pane state** | Create session → add tabs → add panes → close pane → assert tree shape | In-memory CRUD on data structures |
| **Layout tree operations** | Split → resize → equalize → close → swap → assert dimensions | Pure binary tree operations |
| **Layout serialization** | Build tree → serialize to JSON → deserialize → assert structurally equal | Roundtrip test |
| **Snapshot serialization** | Build full session state → serialize → deserialize → assert equal | JSON roundtrip |
| **Configuration parsing** | Config string/file → parsed config struct → assert values | String parsing |
| **Key event encoding** | KeyEvent struct → wire bytes → assert matches expected escape sequences | Pure encoding functions |

> **IME testing**: Korean Jamo composition and decomposition tests belong to libitshell3-ime's own test suite. See `docs/modules/libitshell3-ime/01-overview/`.

---

### Tier 2: OS Integration Tests (Real Sockets, PTYs, Processes)

Use real OS resources but don't need a GUI or display. Run in CI on any macOS/Linux runner.

| Module | What to Test | Approach |
|--------|-------------|----------|
| **PTY creation + I/O** | `openpty()` → fork shell → write → read → assert output | Real PTY, real fork |
| **PTY IUTF8 flag** | Create PTY → read `termios` → assert `IUTF8` bit set | `tcgetattr` check |
| **PTY resize** | Create PTY → `TIOCSWINSZ` → read back → assert dimensions | ioctl roundtrip |
| **Child process lifecycle** | Fork shell → kill → assert `SIGCHLD` reaped, pane state = exited | Signal handling |
| **Daemon socket lifecycle** | Start daemon → client connects → handshake → disconnect → assert clean shutdown | Real Unix socket |
| **Multi-client session** | Daemon → client A + client B attach → pane output → assert both receive it | Two socket connections |
| **Client detach/reattach** | Client attaches → detaches → reattaches → assert session state intact | Socket disconnect + reconnect |
| **Session snapshot + restore** | Create session → snapshot to file → stop → start → restore → assert layout matches | File I/O + state comparison |
| **Backpressure / flow control** | Flood pane with output → assert pause → drain → assert continue | Fast writer + slow reader |

---

### Tier 3: End-to-End Integration Tests

Full daemon-client scenarios running as separate processes. Validate the real binary artifacts.

| Scenario | What to Test |
|----------|-------------|
| **CLI attach/detach** | Start daemon → attach → run commands → detach → reattach → assert scrollback preserved |
| **Session listing** | Start daemon → create 3 sessions → list → assert all 3 listed |
| **Split layout round-trip** | Split right → split down → detach → reattach → assert 3-pane layout |
| **Crash recovery** | Start long process → kill client → reattach → assert process still running |
| **Daemon restart with persistence** | Create session → stop daemon → restart → attach → assert restored |
| **Cross-version compatibility** | Client v2 → daemon v1 → assert graceful capability fallback |

---

### Tier 4: Manual / GUI Tests (App Layer Only)

These belong to the **it-shell3 app**, not libitshell3. Listed here for completeness.

| What | Why Manual |
|------|-----------|
| libghostty Metal rendering | Needs GPU context and display |
| IME composition events | Needs actual input method system |
| Cmd+C/V clipboard behavior | Needs NSPasteboard |
| iOS client behavior | Needs iOS simulator or device |
| Visual layout correctness | Needs human eyes |

**None of these are part of libitshell3.** The library boundary is clean: it deals in bytes, messages, PTY fds, and state — never in pixels or input events.

---

## Test Organization

```
tests/
├── unit/
│   ├── protocol_test.zig          # Message encode/decode roundtrips
│   ├── layout_test.zig            # Split tree operations
│   ├── session_state_test.zig     # Session/tab/pane CRUD
│   ├── snapshot_test.zig          # Serialization roundtrips
│   ├── config_test.zig            # Configuration parsing
│   └── key_encoding_test.zig      # Key event → wire bytes
├── integration/
│   ├── pty_test.zig               # Real PTY creation, I/O, IUTF8
│   ├── daemon_test.zig            # Socket lifecycle, multi-client
│   ├── handshake_test.zig         # Full capability negotiation
│   ├── persistence_test.zig       # Snapshot + restore round-trip
│   └── flow_control_test.zig      # Backpressure pause/continue
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
