# 00053. Daemon-Embedded Debug Subsystem

- Date: 2026-03-26
- Status: Accepted

## Context

it-shell3-daemon is a headless Unix socket server with no UI. Observing internal
state — session hierarchy, pane lifecycle, frame delivery, IME composition — is
difficult without dedicated tooling. This is especially critical because:

1. **AI agent debugging**: Without structured, machine-readable diagnostics, AI
   agents resort to guessing instead of evidence-based debugging.
2. **End-user bug reports**: Users need a way to capture daemon behavior for
   issue reproduction without requiring a debug build.
3. **Client-free testing**: During development, verifying daemon behavior
   currently requires a fully implemented client app. The ability to inject
   inputs (key events, mouse events, session/pane operations) and inspect
   results (screen dumps) directly enables testing without a client.

Three placement options were considered:

- **Inside libitshell3** (`modules/libitshell3/src/debug/`): The debug module
  needs access to SessionManager, Pane, and event loop internals. These types
  are already `pub` (required for cross-file imports within libitshell3), so
  access is identical regardless of placement. However, debug tooling is
  operational infrastructure, not library functionality — placing it in
  libitshell3 conflates concerns.

- **Separate module** (`modules/libitshell3-debug/`): Clean separation, but no
  practical benefit over daemon placement. Zig has no package-private visibility
  — the accessible symbol set is the same `pub` surface either way. Adds a build
  target and dependency edge for no gain.

- **Inside daemon binary** (`daemon/src/debug/`): Debug is daemon-specific
  operational tooling. The daemon already imports both libitshell3 and
  libitshell3-protocol, giving natural access to all required types. No library
  API surface pollution.

## Decision

Place the debug subsystem in `daemon/src/debug/` as part of the daemon binary,
not as a library module.

**Architecture:**

- **Activation**: TCP listener on `localhost`, port specified via
  `IT_SHELL3_DEBUG_PORT` environment variable. If unset, the debug subsystem is
  entirely inactive (no listener, no overhead).
- **Protocol**: Stateless request-response over TCP. Plain text commands in,
  plain text or JSONL responses out. Each connection handles one command then
  closes (like HTTP without the headers).
- **Logging**: Tag-based filtering (`lifecycle`, `request`, `response`,
  `notification`, `input`, `ime`, `frame`, `frame:verbose`, `flow`, `error`).
  Log output goes to a file (set via `set-log-file` command), not to the TCP
  connection. Tags support a `:verbose` modifier for detailed output.
- **Three command categories**:
  - _Logging_: `set-log-file`, `subscribe`, `unsubscribe`, `list-tags`
  - _Inspection_: `dump-sessions`, `dump-clients`, `dump-pane`, `dump-screen`,
    `stats`
  - _Control_: `create-session`, `split-pane`, `inject-key`,
    `inject-mouse-{move,click,scroll}`, `switch-ime`, and other daemon
    operations via text commands
- **Security**: localhost-only bind + env var opt-in. No additional
  authentication (YAGNI — same-machine, same-user access only).

**Internal modules:**

- `listener.zig` — TCP accept, read line, dispatch, write response, close
- `command_parser.zig` — text → Command union parsing
- `inspector.zig` — read-only state queries (dump-\*, stats)
- `controller.zig` — state-mutating commands (reuses existing handler logic)
- `log_emitter.zig` — tag set management, JSONL serialization, file I/O
- `format.zig` — CellData→JSON, HID→name, MessageType→name helpers

**Future CLI extension**: The control command set naturally evolves into a CLI
management tool (`it-shell3-ctl`). When needed, command definitions can be
extracted into a shared module; the text protocol makes this low-cost. This
extraction is deferred per YAGNI.

## Consequences

**What gets easier:**

- AI agents can debug daemon behavior with structured commands (`dump-screen`,
  `inject-key`) and machine-readable JSONL logs.
- End users can capture diagnostics in release builds by setting one environment
  variable.
- Daemon features can be tested without a client app — inject inputs and verify
  screen output directly.
- Log emit points are 1-line calls with a bit-check fast path when tags are
  disabled.

**What gets harder:**

- Event handlers gain log emit calls (one line each), slightly increasing code
  in hot paths. Mitigated by bit-check guard (cost ≈ 0 when logging disabled).
- Debug command set must be maintained alongside protocol changes (new message
  types need format.zig updates for human-readable names).

**New obligations:**

- When adding new message types or HID codes, update `format.zig` with
  human-readable name mappings.
- When adding new event handlers, add corresponding `log_emitter.emit()` calls.
- The `controller.zig` module must reuse existing handler logic, not duplicate
  it — control commands are thin dispatch wrappers.
