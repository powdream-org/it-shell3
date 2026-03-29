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
// src/feature/widget.zig

pub const Widget = struct { ... };

// ── Tests ────────────────────────────────────────────────────────────────
test "Widget.init: returns default state" { ... }
test "Widget.update: clamps value to max" { ... }
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

- State transitions (e.g., "reset clears all pending state")
- Output correctness (e.g., "processed input produces expected output bytes")
- Ordering constraints (e.g., "consume result BEFORE next mutating call")
- Error handling (e.g., "unsupported option returns error")
- Edge cases defined in spec (e.g., "empty state returns empty result")
- Invariant enforcement (e.g., "teardown uses discard, not commit")

**What NOT to test** — the compiler already verifies these:

- Field existence (`@hasField`) — wrong name won't compile
- Type existence (`_ = s.field`) — no-op, compiler enforces at usage sites
- Constant values (`SOME_MAX == 64`) — enforced at usage sites
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

- `test "Config.init: applies default values"`
- `test "allocSlot: returns first free slot"`

### Spec compliance tests

```zig
test "spec: <topic> — <requirement description>" {
```

Examples:

- `test "spec: state transfer — flush before next mutating call"`
- `test "spec: teardown — uses discard not commit"`
- `test "spec: lifecycle — deactivate on last detach"`

## Test Discovery

### The problem

`std.testing.refAllDecls(@This())` discovers tests by recursively following
`pub` imports from the current file. However, it does **NOT** cross named module
boundaries — and there are two levels of named modules:

- **Inter-library modules**: Separate libraries with their own `build.zig`
  (e.g., a protocol library, an IME engine library, a core daemon library). Each
  library is a dependency declared in `build.zig.zon`. Tests in one library are
  invisible to another library's test runner.

- **Intra-library modules**: Named sub-modules within a single library's
  `build.zig` (e.g., a core types module, a server module, an input module
  within the same library). Created via `b.createModule()` and wired with
  `addImport()`. Tests in one sub-module are invisible to another sub-module's
  test runner.

In both cases, `@import("some_named_module")` creates a separate compilation
unit. `refAllDecls` follows `pub` declarations within the **current**
compilation unit only.

### The solution: per-module test steps

Each named module — at both levels — gets its own `addTest`. For inter-library
modules, each library's `build.zig` defines its own test step. For intra-library
modules, the parent library's `build.zig` creates a test step per sub-module.
The top-level `test` step depends on all of them:

```zig
// build.zig
const test_step = b.step("test", "Run all tests");
for (all_modules) |mod| {
    const t = b.addTest(.{ .root_module = mod.module });
    test_step.dependOn(&b.addRunArtifact(t).step);
}
```

### Per-module root.zig requirements

Each named module's `root.zig` MUST:

1. **Import all submodules** within that module via `pub const`:
   ```zig
   // <submodule>/root.zig
   pub const handler_a = @import("handler_a.zig");
   pub const handler_b = @import("handler_b.zig");
   pub const subsystem = @import("subsystem.zig");
   ```

2. **End with `refAllDecls`** to discover all inline tests:
   ```zig
   test {
       std.testing.refAllDecls(@This());
   }
   ```

### testing/ module root

`testing/root.zig` must import **all three subdirectories** explicitly:

```zig
// testing/root.zig
pub const helpers = @import("helpers.zig");

// Mocks
pub const mock_foo = @import("mocks/mock_foo.zig");
pub const mock_bar = @import("mocks/mock_bar.zig");

// Spec tests — must be explicitly imported for discovery
pub const feature_spec = @import("spec/feature_spec_test.zig");
pub const lifecycle_spec = @import("spec/lifecycle_spec_test.zig");

test {
    std.testing.refAllDecls(@This());
}
```

Spec test files in `testing/spec/` are NOT auto-discovered — they must be listed
in `testing/root.zig`. When adding a new spec test file, add its import here.

### Library root (src/root.zig)

The top-level `src/root.zig` imports named modules only. It does NOT use
`refAllDecls` — each module's own test step handles discovery:

```zig
// src/root.zig — library API surface only, NO refAllDecls
pub const core = @import("<module>_core");
pub const server = @import("<module>_server");
pub const testing_mod = @import("<module>_testing");
```

## Test-Only Imports

Imports used exclusively by tests MUST be inside the `test` block, not at the
file top level. Top-level imports are included in production builds even if
unused at runtime.

```zig
// BAD — test helper imported at file top level, included in production
const json_mod = @import("testing/helpers.zig");

test "round-trip" {
    const json = try json_mod.encode(allocator, value);
    // ...
}

// GOOD — import inside test block, excluded from production
test "round-trip" {
    const json_mod = @import("testing/helpers.zig");
    const json = try json_mod.encode(allocator, value);
    // ...
}
```

## What NOT to Test

- `unreachable` branches — UB by definition, not testable
- Platform-specific code that only runs on a different OS
- Trivial getters that return a field value — the field access is the test

Document exceptions with a comment explaining why the code is untestable.

## Mock Placement and Dependencies

### Dependency rules

- **mocks/**: Each mock depends ONLY on the module that defines the interface it
  mocks. Never depend on implementation modules. Example: a mock for an OS
  interface depends on the OS module; a mock for an engine interface depends on
  the module that defines the vtable.
- **helpers.zig**: Depends on interface/type modules only (the modules that
  define types and interfaces, not the modules that implement behavior).
- **spec/**: May import all named modules (test-only, verification purpose).
- **Production code**: NEVER imports the testing module. Only test blocks may.

### When a mock needs an implementation module's type

This signals a dependency problem. Follow this escalation:

**Step 1 — Check interface placement.** Is the type an interface or an
implementation detail? If it is an interface (e.g., a "write bytes to fd"
vtable), it likely belongs in a lower module (OS interfaces or core types). Move
the interface; the mock follows naturally.

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

**Mock needs two implementation modules.** A test verifies an end-to-end
pipeline spanning two implementation modules. The mock must simulate both
modules' behavior in a single test fixture. Moving either interface to a types
module would pull implementation concerns into the domain layer.

**Interface is genuinely cross-cutting.** A type contains both external protocol
state and internal session state. It belongs in neither module alone, but
splitting it creates a coordination problem. The owner must decide: split the
type, introduce a shared types module, or accept the current placement with a
documented exception.

**Two modules define interfaces referencing each other's types.** Module A's
interface takes a type from module B; module B's interface takes a type from
module A. Neither can be moved without pulling the other's type along. This is a
design-level circular dependency requiring owner restructuring.
