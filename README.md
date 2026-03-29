# it-shell3

A terminal ecosystem providing multiplexer session management with first-class
CJK input support, built on libghostty.

## Goals

- **Native CJK Input:** Server-side IME in pure Zig (wraps libhangul) —
  eliminates iOS async UITextInput and macOS NSTextInputClient issues.
- **Rich Key Handling:** Preserves complex key combinations (Shift+Enter,
  Ctrl+Semicolon) that are lost in standard terminal protocols.
- **Session Persistence:** Daemon manages PTY ownership and session state;
  sessions survive client disconnects.
- **Thin Client:** All heavy processing (VT emulation, IME, I/O mux) runs in the
  Zig daemon. The client only renders and captures events.

## Architecture

1. **Multiplexer Daemon (Server):**
   - High-performance VT emulation powered by `libghostty`.
   - Unicode/CJK composition via `libitshell3-ime`.
   - Session and window management via `libitshell3`.
2. **Client SDK (Zig):**
   - A standalone static library (.a) used by the app layer.
   - Abstracts the transport layer (Local Unix Socket vs. SSH Tunnel).
3. **App Layer (Client):**
   - Platform-specific UI layer (e.g., Swift for macOS).
   - Direct invocation of the Client SDK via C FFI.

```
Server (Daemon)                    Client (App)
┌─────────────────┐                ┌──────────────┐
│ PTY master FDs  │                │ UI Layer     │
│ Session state   │  Unix socket   │ (Swift/Metal)│
│ libitshell3-ime │◄──────────────►│              │
│ libghostty-vt   │  binary msgs   │ libghostty   │
│ I/O multiplexer │                │ surface      │
└─────────────────┘                └──────────────┘
```

**Protocol:** 16-byte fixed header (`magic 0x4954` + version + flags +
msg_type + length + sequence) with variable payload. Capability negotiation at
handshake.

### Client Connectivity Modes

The Client SDK handles connecting to a daemon based on the target environment.

**1. Local Mode (Direct Unix Socket)**

- **Scenario:** Daemon running on the local macOS host.
- **Mechanism:** Direct connection to the Unix Domain Socket.
- **Benefit:** Lowest possible latency with zero encryption overhead.

**2. Remote Mode (SSH + Unix Socket Bridge)**

- **Scenario:** Daemon running on a remote server.
- **Mechanism:** The SDK establishes a connection using `libssh2`, requests a
  StreamLocal Forwarding channel through the SSH session, bridging the remote
  Unix socket to the client.
- **Benefit:** Secure, firewall-friendly access using existing SSH
  infrastructure.

## Project Structure

```
it-shell3/
├── app/                        # Client UI applications
│   └── macos/                  #   macOS App (Swift/Metal) — planned
├── daemon/                     # Server daemon entry point
│   └── build.zig               #   Daemon build script
├── modules/
│   ├── libitshell3/            # Core: session/pane state, PTY, event loop
│   ├── libitshell3-protocol/   # Wire protocol: messages, serialization
│   ├── libitshell3-transport/  # Transport layer: Unix socket, SSH bridge
│   └── libitshell3-ime/        # Native IME engine (Korean 2-set via libhangul)
├── vendors/
│   ├── ghostty/                # Terminal engine (VT parser, Metal rendering)
│   └── libhangul/              # Korean Hangul composition (C, LGPL-2.1)
├── docs/                       # Design documents, conventions, insights
├── mise.toml                   # Task runner config
└── Dockerfile.kcov             # Linux container for kcov coverage
```

**Applications** (it-shell3 client, it-shell3-daemon) are not yet started.

## Roadmap

See [`ROADMAP.md`](docs/superpowers/plans/ROADMAP.md) for the current status and
full implementation plan.

## Build & Test

**Prerequisites:** [mise](https://mise.jdx.dev/), Docker (for coverage)

```bash
mise run test:macos                # All modules — Debug
mise run test:macos:release-safe   # All modules — ReleaseSafe
mise run test:coverage             # kcov in Docker (Linux)
mise run test:linux                # All modules in Docker — Debug
mise run build:docker:zig-kcov     # Build the kcov Docker image
```

Single-module test:

```bash
(cd modules/libitshell3 && zig build test --summary all)
```

### Why Docker for coverage?

kcov cannot parse macOS DWARF debug info — it only works with Linux ELF
binaries. `Dockerfile.kcov` builds a `zig-kcov` image so macOS developers can
produce ELF binaries and run coverage inside a Linux container.

## Dependencies

- [ghostty](https://github.com/ghostty-org/ghostty) — Terminal engine (vendored
  at `vendors/ghostty/`)
- [libhangul](https://github.com/libhangul/libhangul) — Korean Hangul
  composition (vendored at `vendors/libhangul/`, LGPL-2.1)
- [libssh2](https://github.com/allyourcodebase/libssh2) — SSH transport for
  remote daemon connections (planned, via `build.zig.zon`)

## Documentation

- `docs/modules/libitshell3/` — Daemon design (15 documents)
- `docs/modules/libitshell3/design/server-client-protocols/` — Protocol specs (6
  documents)
- `docs/modules/libitshell3-ime/` — IME design (7 documents)
- `docs/insights/` — Cross-cutting architectural insights
- `docs/conventions/` — Coding, naming, testing, commit conventions

## Automated Header Generation (Planned)

Functions and types intended for FFI are marked with `export` and `extern` in
the Client SDK. The `daemon/build.zig` is configured to emit a C header
automatically during the build process:

```zig
const lib = b.addStaticLibrary(.{
    .name = "itshell3-client",
    .root_source_file = b.path("../modules/libitshell3-client/src/root.zig"),
});

lib.emit_h = .emit; // Enables automatic header generation
```

## Build & Client SDK Integration (Planned)

The `daemon/build.zig` defines separate targets for the server and the
multi-architecture client SDK.

```bash
cd daemon

# Build all client targets
zig build client-libs

# Create XCFramework for Apple platforms
xcodebuild -create-xcframework \
  -library ../artifacts/lib/macos-arm64/libitshell3-client.a -headers zig-out/include/ \
  -library ../artifacts/lib/macos-x86_64/libitshell3-client.a -headers zig-out/include/ \
  -library ../artifacts/lib/ios-arm64/libitshell3-client.a -headers zig-out/include/ \
  -output ../artifacts/it-shell-sdk.xcframework
```

## Swift Integration (Planned)

The Swift application uses an `extern struct` to pass connectivity requirements
to the Zig SDK.

```swift
let config = itshell_config(
    type: .ssh,
    host: "dev.server.com",
    user: "heejoon.kang",
    socket_path: "/tmp/it-shell.sock"
)
itshell_connect(config)
```

## License

MIT — see [LICENSE](LICENSE).

Vendored dependencies carry their own licenses:

- ghostty — MIT (`vendors/ghostty/LICENSE`)
- libhangul — LGPL-2.1 (`vendors/libhangul/COPYING`)
