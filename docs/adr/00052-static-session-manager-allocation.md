# 00052. Static Allocation for SessionManager

- Date: 2026-03-26
- Status: Accepted

## Context

SessionManager contains `[64]?SessionEntry`, where each SessionEntry holds
`[16]?Pane` and each Pane embeds `[4096]u8` for CWD and `[256]u8` for title.
This totals ~4.5 MB per SessionManager instance.

When placed on the stack (as `var sm = SessionManager.init()` inside a
function), this caused SIGSEGV under kcov's ptrace instrumentation on Linux. The
default thread stack is 8 MB; kcov's instrumentation overhead pushed the 4.5 MB
struct past the limit, triggering a stack overflow.

The crash was initially masked on macOS (8 MB stack, no kcov pressure) but
represents a real production risk — any deep call chain from `main()` with
SessionManager on the stack could overflow.

Alternatives considered:

- **Heap-allocate SessionEntry individually**: Changes `[64]?SessionEntry` to
  `[64]?*SessionEntry`, requiring an allocator parameter on SessionManager. Adds
  allocation per session create/destroy. Cleaner memory usage (only allocate
  live sessions) but introduces allocator dependency into core types.
- **Reduce buffer sizes**: Shrink `cwd` from 4096 to 256. Saves space but
  truncates long paths — `PATH_MAX` on Unix is 4096 for a reason.
- **Heap-allocate SessionManager**: `allocator.create(SessionManager)`. Moves
  the problem from stack to heap but still allocates 4.5 MB upfront. Requires
  allocator plumbing in tests.

## Decision

Use **static allocation** (.bss segment) for SessionManager. The daemon process
has exactly one SessionManager for its entire lifetime — a file-scope `var` is
the natural fit.

For production (`daemon/main.zig`):

```zig
// File-scope static — 4.5 MB in .bss, not on main()'s stack
var sm: SessionManager = SessionManager.init();
```

For tests: a file-scope `var test_sm` with a `reset()` method called at the
start of each test for isolation:

```zig
var test_sm = SessionManager.init();

test "example" {
    test_sm.reset();
    // test uses test_sm...
}
```

`reset()` zeroes the sessions array and resets ID counters to 1.

## Consequences

**What gets easier:**

- Stack overflow eliminated — 4.5 MB lives in .bss regardless of call depth.
- No allocator dependency — SessionManager stays in core types with no
  `std.mem.Allocator` parameter.
- Zero allocation overhead — no heap alloc/free per session.
- kcov works — tests run under ptrace without stack pressure.
- Test isolation via `reset()` is explicit and deterministic.

**What gets harder:**

- Single instance per process — cannot create multiple SessionManagers (not
  needed for the daemon, but limits testability of multi-daemon scenarios).
- Static mutable state — `var` at file scope is effectively a global. Acceptable
  for a single-threaded daemon with one SessionManager.
- Tests share state — `reset()` must be called at the start of every test.
  Forgetting it causes test-order-dependent failures. Zig's test runner executes
  tests sequentially within a file, so this is manageable.

**New obligations:**

- Every test that uses the static SessionManager MUST call `reset()` first.
- If the project ever needs multiple SessionManager instances (e.g., for testing
  daemon restart), this decision must be revisited.
