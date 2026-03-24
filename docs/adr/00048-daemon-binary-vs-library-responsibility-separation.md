# 00048. Daemon Binary vs Library Responsibility Separation

- Date: 2026-03-24
- Status: Accepted

## Context

The it-shell3 daemon involves three layers that collaborate at runtime:

1. **`daemon/`** — The executable binary (`daemon/main.zig`), bundled inside the
   client app at `it-shell3.app/Contents/Helpers/it-shell3-daemon`.
2. **`modules/libitshell3/`** — The core domain library: session/pane state,
   event loop, ghostty integration, IME routing, runtime handlers.
3. **`modules/libitshell3-protocol/`** — The shared wire protocol library: Layer
   1-3 (codec, framing, connection state machine) and Layer 4 (transport:
   `Listener`, `Connection`, socket lifecycle).

The r7 daemon design docs (doc01 §1, doc02 §1, doc03 §1) describe a 7-step
startup sequence that mixes concerns across these layers: CLI argument parsing
(binary), socket bind via `transport.Listener.init()` (protocol library), kqueue
creation (library), session creation (library), and LaunchAgent registration
(binary, platform-specific). Without an explicit responsibility boundary, the
code structure risks coupling OS integration concerns (signals, LaunchAgent, CLI
args) into the reusable library, or pulling domain logic (session management,
event handling) into the binary.

The key question: who owns startup/shutdown orchestration, socket management,
domain logic, and the event loop?

## Decision

**Three-layer responsibility separation with the binary as orchestrator:**

| Responsibility                                 | Owner                                                        | Rationale                                                                 |
| ---------------------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------- |
| CLI argument parsing                           | `daemon/main.zig`                                            | Binary-specific; the library has no concept of CLI args                   |
| Signal handler registration (`sigprocmask`)    | `daemon/main.zig`                                            | OS process-level concern; must happen before any FDs are created          |
| LaunchAgent registration/detection             | `daemon/main.zig`                                            | Platform-specific OS integration (comptime-gated)                         |
| Socket create/bind/listen/accept               | `libitshell3-protocol` Layer 4 (`transport.Listener`)        | Shared between daemon and client; socket lifecycle is a transport concern |
| Stale socket detection and cleanup             | `libitshell3-protocol` Layer 4 (`transport.Listener.init()`) | Transport-level concern; uses `transport.connect()` probe internally      |
| kqueue creation and event loop                 | `libitshell3` (`server/event_loop.zig`)                      | Domain logic; the event loop dispatches to domain handlers                |
| Session/pane creation and management           | `libitshell3` (`server/`, `core/`)                           | Core domain logic                                                         |
| Event handlers (SIGCHLD, PTY, client messages) | `libitshell3` (`server/handlers/`)                           | Domain logic operating on domain state                                    |
| ghostty Terminal lifecycle                     | `libitshell3` (`ghostty/`)                                   | Integration with vendored dependency                                      |
| Graceful shutdown logic (drain, cleanup)       | `libitshell3` (library provides the logic)                   | Domain state teardown; binary triggers it                                 |

**The daemon binary orchestrates the startup sequence** by calling into the two
libraries in the correct order (as specified in doc03 §1.1), but does not
contain domain logic. The binary is thin: parse args → call
`transport.Listener.init()` → call library init (kqueue, default session) →
enter event loop → on shutdown signal, call library shutdown → exit.

**Session persistence (snapshot/restore) is deferred to post-v1** (ADR 00036).
The daemon starts fresh every time — no session restoration from disk.

## Consequences

- `daemon/main.zig` is small (~100-200 lines): arg parsing, signal setup,
  LaunchAgent integration, and the orchestration sequence that calls library
  APIs. No domain logic leaks into the binary.
- `libitshell3` has no dependency on `daemon/` — it is a reusable library.
  Testing the library does not require building the daemon binary.
- `libitshell3-protocol` Layer 4 is shared between daemon and client — both use
  `transport.Listener` (server) or `transport.connect()` (client) for socket
  management. Socket lifecycle code is not duplicated.
- The event loop lives in the library (`server/event_loop.zig`), not the binary.
  The binary calls an `enterEventLoop()` or equivalent entry point and blocks
  until shutdown.
- LaunchAgent code is `comptime`-gated in the binary, not the library. The
  library is platform-agnostic; the binary handles platform-specific startup
  modes (LaunchAgent vs foreground vs SSH fork+exec).
- The `server/` module in `libitshell3` does NOT contain `main.zig` — that name
  is reserved for the daemon binary's entry point at `daemon/main.zig`.
