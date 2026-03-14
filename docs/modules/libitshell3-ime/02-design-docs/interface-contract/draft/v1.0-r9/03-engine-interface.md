# IME Interface Contract v0.9 — Engine Interface

> **Version**: v0.9
> **Date**: 2026-03-14
> **Part of the IME Interface Contract v0.9. See [01-overview.md](01-overview.md) for the document index.**
> **Changes from v0.8**: HangulImeEngine concrete struct extracted to behavior docs. Internal step sequence removed from setActiveInputMethod. Surface API references removed from MockImeEngine tests. Sections renumbered per-document sequential. See [Appendix K: Changes from v0.8](99-appendices.md#appendix-k-changes-from-v08).

## 1. ImeEngine (Interface for Dependency Injection)

```zig
/// Abstract interface for an IME engine. libitshell3's Session holds an ImeEngine
/// rather than a concrete type, enabling mock injection for tests.
///
/// Modeled after fcitx5's InputMethodEngine: a minimal interface where only
/// processKey() is required. activate/deactivate handle session-level focus changes.
pub const ImeEngine = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Process a key event. Returns committed text, preedit update,
        /// and/or a key to forward. This is the only required method.
        processKey: *const fn (ptr: *anyopaque, key: KeyEvent) ImeResult,

        /// Flush and commit any in-progress composition.
        /// Returns ImeResult with committed text (if composing) or empty.
        /// Also called internally by deactivate().
        flush: *const fn (ptr: *anyopaque) ImeResult,

        /// Discard in-progress composition without committing.
        /// No ImeResult returned — composition is silently discarded.
        reset: *const fn (ptr: *anyopaque) void,

        /// Query whether composition is in progress.
        isEmpty: *const fn (ptr: *anyopaque) bool,

        /// Signal the engine that it is becoming active.
        /// No-op for Korean (state is preserved in the buffer).
        /// Active input method is preserved across
        /// deactivate/activate cycles -- NOT reset to direct.
        /// When the daemon calls this is defined in daemon design docs.
        activate: *const fn (ptr: *anyopaque) void,

        /// Signal the engine that it is going idle.
        /// Engine MUST flush pending composition before returning.
        /// The returned ImeResult contains the flushed text.
        /// Calling flush() before deactivate() is redundant but harmless
        /// (deactivate on empty composition returns empty ImeResult).
        /// Active input method is NOT changed.
        /// When the daemon calls this is defined in daemon design docs.
        deactivate: *const fn (ptr: *anyopaque) ImeResult,

        // --- Input method management ---

        /// Get current active input method identifier.
        /// Returns a canonical string (e.g., "direct", "korean_2set").
        getActiveInputMethod: *const fn (ptr: *anyopaque) []const u8,

        /// Set active input method. Flushes pending composition atomically
        /// if switching away from a composing input method.
        /// If method matches the current active input method, this is a no-op
        /// (returns empty ImeResult, no flush).
        /// Called by libitshell3 when user presses the toggle key.
        /// forward_key in the returned ImeResult is always null --
        /// the toggle key is consumed by Phase 0.
        /// Returns error.UnsupportedInputMethod if the string is not recognized.
        setActiveInputMethod: *const fn (ptr: *anyopaque, method: []const u8) error{UnsupportedInputMethod}!ImeResult,
    };

    // Convenience wrappers
    pub fn processKey(self: ImeEngine, key: KeyEvent) ImeResult {
        return self.vtable.processKey(self.ptr, key);
    }

    pub fn flush(self: ImeEngine) ImeResult {
        return self.vtable.flush(self.ptr);
    }

    pub fn reset(self: ImeEngine) void {
        self.vtable.reset(self.ptr);
    }

    pub fn isEmpty(self: ImeEngine) bool {
        return self.vtable.isEmpty(self.ptr);
    }

    pub fn activate(self: ImeEngine) void {
        self.vtable.activate(self.ptr);
    }

    pub fn deactivate(self: ImeEngine) ImeResult {
        return self.vtable.deactivate(self.ptr);
    }

    pub fn getActiveInputMethod(self: ImeEngine) []const u8 {
        return self.vtable.getActiveInputMethod(self.ptr);
    }

    pub fn setActiveInputMethod(self: ImeEngine, method: []const u8) error{UnsupportedInputMethod}!ImeResult {
        return self.vtable.setActiveInputMethod(self.ptr, method);
    }
};
```

**Vtable design (8 methods):**

| Method | Purpose | Returns |
|--------|---------|---------|
| `processKey` | Core key processing | ImeResult |
| `flush` | Commit in-progress composition | ImeResult |
| `reset` | Discard composition (error recovery) | void |
| `isEmpty` | Query composition state | bool |
| `activate` | Session gained focus | void |
| `deactivate` | Session lost focus (flushes) | ImeResult |
| `getActiveInputMethod` | Query current input method | `[]const u8` |
| `setActiveInputMethod` | Switch input method (flushes atomically) | `error{UnsupportedInputMethod}!ImeResult` |

**Why vtable over comptime generics:**
- Comptime generics (`fn Session(comptime Ime: type) type`) would monomorphize all Session code per IME type, inflating binary size when multiple engines exist.
- vtable is a single pointer indirection — negligible cost at the call rates we see (< 100 calls/second for human typing).
- vtable works with C FFI (comptime generics don't export to C).

## 2. setActiveInputMethod Behavior

`setActiveInputMethod()` is the only input-method-switching method. It handles both language switches (e.g., `"korean_2set"` -> `"direct"`) and layout switches (e.g., `"korean_2set"` -> `"korean_3set_final"`) uniformly. Its behavior depends on whether the requested input method differs from the current one:

**Case 1: Switching to a different input method (e.g., `"korean_2set"` -> `"direct"`):**

The engine atomically flushes any in-progress composition and switches to the new input method. The returned `ImeResult`:
- If composition was active: `ImeResult{ .committed_text = flushed_text, .preedit_text = null, .forward_key = null, .preedit_changed = true }`.
- If composition was not active (engine was already empty): `ImeResult{ .committed_text = null, .preedit_text = null, .forward_key = null, .preedit_changed = false }`.

`preedit_changed` follows [Section 2](02-types.md#2-imeresult-output-from-ime)'s definition: it is `true` only when the preedit state actually transitions (here, non-null to null from flushing). When the engine was already empty, preedit remains null throughout (null to null) — no transition occurred, so `preedit_changed` is `false`.

For the internal step sequence (libhangul flush, mode update, keyboard selection), see [behavior/draft/v1.0-r1/10-hangul-engine-internals.md](../../../behavior/draft/v1.0-r1/10-hangul-engine-internals.md), Section 4.

**Case 2: "Switching" to the already-active input method (e.g., `"korean_2set"` -> `"korean_2set"`):**

Return `ImeResult{}` (all null/false). No flush, no state change.

**Case 3: Unsupported input method string:**

Return `error.UnsupportedInputMethod`. The server MUST only send input method strings from the canonical registry (see [behavior/draft/v1.0-r1/10-hangul-engine-internals.md](../../../behavior/draft/v1.0-r1/10-hangul-engine-internals.md), Section: Canonical Input Method Registry). Receiving an unrecognized string is a server bug.

**Rationale for no-op on same-method**: The user toggled to the same mode by mistake (or the framework called it redundantly). Flushing would be a surprising side effect — the user didn't intend to commit their in-progress composition. This matches fcitx5 (`InputMethodManager::setCurrentGroup()`) and ibus (`ibus_bus_set_global_engine()`), both of which treat same-engine switches as no-ops.

**Atomicity**: `setActiveInputMethod()` flushes and switches in a single call. The caller must NOT call `flush()` then `setActiveInputMethod()` separately — a key event arriving between those two calls could be processed in the wrong input method.

**forward_key is always null**: `setActiveInputMethod()` is called from Phase 0 in response to a toggle key that has already been consumed. There is no key to forward. If a toggle key (e.g., Right Alt) leaked through to ghostty, it would produce garbage escape sequences (`\e` prefix for Alt).

**String parameter ownership**: The `method` parameter is borrowed for the duration of the call. The engine copies the string into its own storage (or references a static string) — the caller does not need to keep the pointer alive after the call returns.

> **Discard-and-switch pattern**: `reset()` followed by `setActiveInputMethod()` is safe for discard-and-switch when the caller holds the per-session lock. After `reset()`, the engine is empty and `setActiveInputMethod()` performs a no-flush switch. This pattern implements the protocol's `commit_current=false` on InputMethodSwitch.

For the concrete `HangulImeEngine` implementation (struct fields, vtable implementations, libhangul keyboard ID mapping, canonical input method registry, processKey algorithm, and session persistence), see [behavior/draft/v1.0-r1/10-hangul-engine-internals.md](../../../behavior/draft/v1.0-r1/10-hangul-engine-internals.md).

## 3. MockImeEngine (For Testing)

```zig
pub const MockImeEngine = struct {
    /// Queue of results to return from processKey, in order.
    results: []const ImeResult,
    call_index: usize = 0,
    active_input_method: []const u8 = "direct",
    flush_result: ImeResult = .{},

    pub fn engine(self: *MockImeEngine) ImeEngine {
        return .{
            .ptr = @ptrCast(self),
            .vtable = &vtable,
        };
    }

    const vtable = ImeEngine.VTable{
        .processKey = processKeyImpl,
        .flush = flushImpl,
        .reset = resetImpl,
        .isEmpty = isEmptyImpl,
        .activate = noOp,
        .deactivate = deactivateNoOp,
        .getActiveInputMethod = getActiveInputMethodImpl,
        .setActiveInputMethod = setActiveInputMethodImpl,
    };

    // processKeyImpl returns results[call_index++]
    // flushImpl returns flush_result
    // etc.
};
```

This allows testing libitshell3's `handleKeyEvent` without libhangul:

```zig
test "committed text is forwarded to terminal" {
    var mock = MockImeEngine{
        .results = &.{
            .{ .committed_text = "한", .preedit_changed = true },
        },
    };
    var session = Session.initWithEngine(mock.engine());
    session.handleKeyEvent(focused_pane, .{ .hid_keycode = 0x15, .modifiers = .{}, .shift = false, .action = .press });
    // Assert committed text "한" was forwarded to the terminal
}
```
