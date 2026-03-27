# Zig Testing Conventions

Testing rules for all Zig source code in the it-shell3 project.

## Directory Structure

Every module follows the same layout regardless of size:

```
<module>/src/
├── [production code]              ← inline unit tests at bottom of files
└── testing/
    ├── helpers.zig                ← shared test fixtures
    ├── mocks/
    │   └── mock_*.zig             ← mock implementations
    └── spec/
        └── *_spec_test.zig        ← spec compliance tests
```

## Test Types

### Inline Unit Tests (implementer-owned)

Written at the bottom of each production source file. Verify function-level
behavior — the "does my code do what I intended" check.

```zig
// src/core/session.zig

pub const Session = struct { ... };

// ── Tests ────────────────────────────────────────────────────────────────
test "Session.init: defaults to direct input method" { ... }
test "Session.setPreedit: truncates to MAX_PREEDIT_BUF" { ... }
```

**Scope**: Function behavior, edge cases, error paths.

**Ownership**: Implementer. Changes when the implementation changes.

### Spec Compliance Tests (QA-owned)

Written in separate `_spec_test.zig` files under `testing/spec/`. Verify that
the implementation conforms to the design spec — the "does the code match the
spec" check.

**Derivation**: Tests MUST be derived from the **latest design spec**, not from
the implementation. The QA reviewer reads the spec independently and writes
tests that would catch a non-compliant implementation. A test that only confirms
"the code does what the code does" is invalid.

**What to test** — observable behavior only:

- State transitions (e.g., "flush sets current_preedit to null")
- Output correctness (e.g., "committed_text is written to PTY")
- Ordering constraints (e.g., "consume ImeResult BEFORE next engine call")
- Error handling (e.g., "unsupported input method returns error")
- Edge cases defined in spec (e.g., "empty engine flush returns empty result")
- Invariant enforcement (e.g., "pane close calls reset, not flush")

**What NOT to test** — the compiler already verifies these:

- Field existence (`@hasField`) — wrong name won't compile
- Type existence (`_ = s.field`) — no-op, compiler enforces at usage sites
- Constant values (`MAX_SESSION_NAME == 64`) — enforced at usage sites
- Struct layout mirroring — testing the compiler, not the spec

**Rule**: If removing a test would not catch any future behavioral bug, the test
should not exist.

**Ownership**: QA reviewer. Derived from the spec, not from the implementation.

## Why Two Types

1. **No file conflicts**: Implementer and QA work on different files, preventing
   concurrent-agent file loss.
2. **Independent verification**: Spec tests verify against the SPEC, not the
   implementation. Different source of truth.
3. **Clear ownership**: Spec changes → QA updates spec tests. Implementation
   changes → implementer updates inline tests.

## Test Naming

### Inline tests

```zig
test "FunctionOrType.method: description of behavior" {
```

Examples:

- `test "Session.init: defaults to direct input method"`
- `test "allocPaneSlot: returns first free slot"`

### Spec compliance tests

```zig
test "spec: <topic> — <requirement description>" {
```

Examples:

- `test "spec: ownership transfer — flush before next engine call"`
- `test "spec: pane close — reset NOT flush"`
- `test "spec: client tracker — last detach triggers deactivate"`

## Test Discovery

Each module's `root.zig` uses `std.testing.refAllDecls(@This())` to discover all
tests. The `testing/` root imports mocks, helpers, and spec test files.

Build.zig creates per-module test steps. The main `test` step depends on all
module test steps.

## What NOT to Test

- `unreachable` branches — UB by definition, not testable
- Platform-specific code that only runs on a different OS
- Trivial getters that return a field value — the field access is the test

Document exceptions with a comment explaining why the code is untestable.

## Mock Placement and Dependencies

### Dependency rules

- **mocks/**: Each mock depends ONLY on the module that defines the interface it
  mocks. `mock_os.zig` → `itshell3_os`, `mock_ime_engine.zig` → `itshell3_core`.
  Never depend on implementation modules (server, input).
- **helpers.zig**: Depends on `itshell3_core` + `itshell3_os` only.
- **spec/**: May import all named modules (test-only, verification purpose).
- **Production code**: NEVER imports `itshell3_testing`. Only test blocks may.

### When a mock needs an implementation module's type

This signals a dependency problem. Follow this escalation:

**Step 1 — Check interface placement.** Is the type an interface or an
implementation detail? If it is an interface (e.g., `PtyWriter` is "write bytes
to fd"), it likely belongs in a lower module (`os/interfaces.zig` or `core/`).
Move the interface; the mock follows naturally.

**Step 2 — Keep mock inline.** If the type genuinely belongs in the
implementation module and the mock is only needed by that module's own tests,
define the mock inline in the test block. Do not pull it into `testing/`.

**Step 3 — Escalate to owner.** If multiple modules need to mock the same
implementation-module type, and Steps 1-2 do not apply, STOP and escalate with:

- Which type needs mocking and where it is defined
- Which modules need the mock and why
- Why the interface cannot be moved to a lower module
- The dependency cycle that would result from naive placement

**Do NOT resolve dependency architecture decisions autonomously** — incorrect
placement compounds across the codebase and is expensive to fix later.

### Examples requiring owner escalation

**Mock needs two implementation modules.** A test verifies that the event loop
routes a key event through the input pipeline and writes to PTY via the server
consumer. The mock must simulate both `input/key_router` and
`server/ime_consumer` behavior. Moving either interface to core/ would pull
implementation concerns into the domain layer.

**Interface is genuinely cross-cutting.** `ClientEntry` contains both protocol
connection state (from `libitshell3-protocol`) and server-side session
attachment state. It belongs in neither module alone. The owner must decide:
split the type, introduce a shared types module, or accept the current placement
with a documented exception.

**Two modules define interfaces referencing each other's types.** Module A's
`InterfaceA` takes `TypeB` (from module B); module B's `InterfaceB` takes
`TypeA` (from module A). Neither can be moved without pulling the other's type
along. This is a design-level circular dependency requiring owner restructuring.
