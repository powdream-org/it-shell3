# libitshell3

Core Zig library for the it-shell3 daemon: session/pane state, PTY layer,
ghostty integration, IME integration, and RenderState export/import. Exports C
API for Swift/other consumers.

## Module Structure

```
src/
├── core/       — Domain types (Session, Pane, SplitTree, ImeEngine vtable)
├── os/         — OS interface vtables (PTY, kqueue, signals) + real/mock impls
├── ghostty/    — ghostty helper functions (terminal, render_state, key_encode)
├── input/      — Key routing pipeline (Phase 0 shortcuts, Phase 1 IME)
├── server/     — Event loop, handlers, IME consumer/lifecycle/procedures
├── testing/    — Mock implementations (MockImeEngine, MockPtyWriter, MockOs)
└── root.zig    — Library root (re-exports all modules for test discovery)
```

## Named Imports

All inter-module references MUST use named imports, not relative paths. This
eliminates `../../` chains and makes module boundaries explicit.

**Available named imports** (defined in `build.zig`):

| Import name         | Root file              | Use for                           |
| ------------------- | ---------------------- | --------------------------------- |
| `itshell3_core`     | `src/core/root.zig`    | Domain types, Session, Pane, IME  |
| `itshell3_os`       | `src/os/root.zig`      | OS interfaces and implementations |
| `itshell3_server`   | `src/server/root.zig`  | Event loop, handlers, IME server  |
| `itshell3_input`    | `src/input/root.zig`   | Key routing, wire decomposition   |
| `itshell3_testing`  | `src/testing/root.zig` | Mocks and test helpers            |
| `itshell3_protocol` | (external dep)         | Wire protocol library             |
| `ghostty`           | (external dep)         | ghostty VT engine                 |

**Rule**: Use `@import("itshell3_core")` instead of
`@import("../../core/types.zig")`. Within the same module (e.g.,
`core/session.zig` importing `core/types.zig`), relative sibling imports are
fine.

**Example**:

```zig
// GOOD — named import for cross-module reference
const core = @import("itshell3_core");
const Session = core.Session;

// GOOD — relative import within the same module
const types = @import("types.zig");

// BAD — relative path crossing module boundary
const types = @import("../../core/types.zig");
```

## Build & Test

```bash
mise run test:macos                # macOS Debug tests
mise run test:macos:release-safe   # macOS ReleaseSafe tests
mise run test:coverage             # kcov in Docker
```

## Conventions

Follow all conventions from the project root `AGENTS.md`, plus:

- **Zig naming**: See `docs/conventions/zig-naming.md`
- **Zig documentation**: See `docs/conventions/zig-documentation.md`
- **Zig testing**: See `docs/conventions/zig-testing.md`
- **Buffer fields**: Fixed-size inline buffers per ADR 00058 with `MAX_*`
  constants and `_length` suffixes
- **Static allocation**: SessionManager in `.bss` per ADR 00052
