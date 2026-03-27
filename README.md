# it-shell3

[![CI](https://github.com/powdream-org/it-shell3/actions/workflows/ci.yml/badge.svg)](https://github.com/powdream-org/it-shell3/actions/workflows/ci.yml)
[![Coverage](https://coveralls.io/repos/github/powdream-org/it-shell3/badge.svg?branch=main)](https://coveralls.io/github/powdream-org/it-shell3?branch=main)

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

## Project Structure

```
it-shell3/
├── modules/
│   ├── libitshell3/            # Core: session/pane state, PTY, event loop
│   ├── libitshell3-protocol/   # Wire protocol: messages, serialization
│   └── libitshell3-ime/        # Native IME engine (Korean 2-set via libhangul)
├── vendors/
│   ├── ghostty/                # Terminal engine (VT parser, Metal rendering)
│   └── libhangul/              # Korean Hangul composition (C, LGPL-2.1)
├── docs/                       # Design documents, conventions, insights
├── mise.toml                   # Task runner config
└── Dockerfile.kcov             # Linux container for kcov coverage
```

**Applications** (it-shell3 client, it-shell3-daemon) are not yet started.

## Current Status

| Module               | Status                                    |
| -------------------- | ----------------------------------------- |
| libitshell3-protocol | Implemented (22 source files), 135+ tests |
| libitshell3-ime      | Implemented (9 source files), 135+ tests  |
| libitshell3          | Implemented (6 sub-modules)               |

See [`ROADMAP.md`](docs/superpowers/plans/ROADMAP.md) for the full
implementation plan.

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

## License

MIT — see [LICENSE](LICENSE).

Vendored dependencies carry their own licenses:

- ghostty — MIT (`vendors/ghostty/LICENSE`)
- libhangul — LGPL-2.1 (`vendors/libhangul/COPYING`)
