# IME Interface Contract v0.6 — Engine Interface

> **Version**: v0.6
> **Date**: 2026-03-05
> **Part of the IME Interface Contract v0.6. See [01-overview.md](01-overview.md) for the document index.**

### 3.5 ImeEngine (Interface for Dependency Injection)

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
        /// Used when: intra-session pane focus change, language switch.
        /// Also called internally by deactivate().
        flush: *const fn (ptr: *anyopaque) ImeResult,

        /// Discard in-progress composition without committing.
        /// Used when: session close, error recovery.
        reset: *const fn (ptr: *anyopaque) void,

        /// Query whether composition is in progress.
        isEmpty: *const fn (ptr: *anyopaque) bool,

        /// Session gained focus (e.g., user switched to this tab).
        /// No-op for Korean (state is preserved in the buffer).
        /// Active input method is preserved across
        /// deactivate/activate cycles -- NOT reset to direct.
        activate: *const fn (ptr: *anyopaque) void,

        /// Session lost focus (e.g., user switched to another tab,
        /// app lost OS focus). Engine MUST flush pending composition
        /// before returning. The returned ImeResult contains the flushed text.
        /// Calling flush() before deactivate() is redundant but harmless
        /// (deactivate on empty composition returns empty ImeResult).
        /// Active input method is NOT changed.
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

### 3.6 setActiveInputMethod Behavior

`setActiveInputMethod()` is the only input-method-switching method. It handles both language switches (e.g., `"korean_2set"` -> `"direct"`) and layout switches (e.g., `"korean_2set"` -> `"korean_3set_final"`) uniformly. Its behavior depends on whether the requested input method differs from the current one:

**Case 1: Switching to a different input method (e.g., `"korean_2set"` -> `"direct"`):**

1. Call `hangul_ic_flush()` internally to commit any in-progress composition.
2. Read the flushed string from libhangul.
3. Set `active_input_method = new_method`.
4. Update internal engine mode and libhangul keyboard if needed.
5. Return `ImeResult`:
   - If composition was active (flushed text is non-empty): `ImeResult{ .committed_text = flushed_text, .preedit_text = null, .forward_key = null, .preedit_changed = true, .composition_state = null }`.
   - If composition was not active (engine was already empty): `ImeResult{ .committed_text = null, .preedit_text = null, .forward_key = null, .preedit_changed = false, .composition_state = null }`.

`preedit_changed` follows Section 3.2's definition: it is `true` only when the preedit state actually transitions (here, non-null to null from flushing). When the engine was already empty, preedit remains null throughout (null to null) — no transition occurred, so `preedit_changed` is `false`.

**Case 2: "Switching" to the already-active input method (e.g., `"korean_2set"` -> `"korean_2set"`):**

Return `ImeResult{}` (all null/false). No flush, no state change.

**Case 3: Unsupported input method string:**

Return `error.UnsupportedInputMethod`. The server MUST only send input method strings from the canonical registry (Section 3.7). Receiving an unrecognized string is a server bug.

**Rationale for no-op on same-method**: The user toggled to the same mode by mistake (or the framework called it redundantly). Flushing would be a surprising side effect — the user didn't intend to commit their in-progress composition. This matches fcitx5 (`InputMethodManager::setCurrentGroup()`) and ibus (`ibus_bus_set_global_engine()`), both of which treat same-engine switches as no-ops.

**Atomicity**: `setActiveInputMethod()` flushes and switches in a single call. The caller must NOT call `flush()` then `setActiveInputMethod()` separately — a key event arriving between those two calls could be processed in the wrong input method.

**forward_key is always null**: `setActiveInputMethod()` is called from Phase 0 in response to a toggle key that has already been consumed. There is no key to forward. If a toggle key (e.g., Right Alt) leaked through to ghostty, it would produce garbage escape sequences (`\e` prefix for Alt).

**libhangul cleanup**: `hangul_ic_flush()` alone is sufficient — no need to call `hangul_ic_reset()` after flush. Verified in libhangul source: `hangul_ic_flush()` calls `hangul_buffer_clear()` which zeroes all jamo fields (`choseong`, `jungseong`, `jongseong`) and clears the stack. After flush, `hangul_ic_is_empty()` returns true.

**String parameter ownership**: The `method` parameter is borrowed for the duration of the call. The engine copies the string into its own storage (or references a static string) — the caller does not need to keep the pointer alive after the call returns.

> **Discard-and-switch pattern**: `reset()` followed by `setActiveInputMethod()` is safe for discard-and-switch when the caller holds the per-session lock. After `reset()`, the engine is empty and `setActiveInputMethod()` performs a no-flush switch. This pattern implements the protocol's `commit_current=false` on InputMethodSwitch.

### 3.7 HangulImeEngine (Concrete Implementation)

```zig
/// Concrete IME engine wrapping libhangul for Korean + direct mode passthrough.
pub const HangulImeEngine = struct {
    hic: *c.HangulInputContext,
    active_input_method: []const u8,  // e.g., "korean_2set" — the canonical protocol string
    engine_mode: EngineMode,          // cached for hot path — derived from active_input_method

    // Internal fixed-size buffers for ImeResult slices
    committed_buf: [256]u8 = undefined,
    preedit_buf: [64]u8 = undefined,
    committed_len: usize = 0,
    preedit_len: usize = 0,

    // Previous preedit for dirty tracking
    prev_preedit_len: usize = 0,

    /// Engine-internal mode for hot path dispatch. NOT part of the public API.
    const EngineMode = enum { direct, composing };

    pub fn init(allocator: Allocator, input_method: []const u8) !HangulImeEngine;
    pub fn deinit(self: *HangulImeEngine) void;

    /// Returns an ImeEngine interface pointing to this instance.
    pub fn engine(self: *HangulImeEngine) ImeEngine;

    // VTable implementation functions (not public API)
    fn processKeyImpl(ptr: *anyopaque, key: KeyEvent) ImeResult;
    fn flushImpl(ptr: *anyopaque) ImeResult;
    fn resetImpl(ptr: *anyopaque) void;
    fn isEmptyImpl(ptr: *anyopaque) bool;
    fn activateImpl(ptr: *anyopaque) void;
    fn deactivateImpl(ptr: *anyopaque) ImeResult;
    fn getActiveInputMethodImpl(ptr: *anyopaque) []const u8;
    fn setActiveInputMethodImpl(ptr: *anyopaque, method: []const u8) error{UnsupportedInputMethod}!ImeResult;

    /// Map canonical input method string to libhangul keyboard ID.
    /// Returns null for "direct" or unrecognized strings.
    /// This is the ONLY place where protocol strings meet engine-native IDs.
    fn libhangulKeyboardId(input_method: []const u8) ?[]const u8 {
        const map = .{
            .{ "korean_2set", "2" },
            .{ "korean_2set_old", "2y" },
            .{ "korean_3set_dubeol", "32" },
            .{ "korean_3set_390", "39" },
            .{ "korean_3set_final", "3f" },
            .{ "korean_3set_noshift", "3s" },
            .{ "korean_3set_old", "3y" },
            .{ "korean_romaja", "ro" },
            .{ "korean_ahnmatae", "ahn" },
        };
        for (map) |entry| {
            if (std.mem.eql(u8, input_method, entry[0])) return entry[1];
        }
        return null;
    }

    fn deriveMode(input_method: []const u8) EngineMode {
        if (std.mem.startsWith(u8, input_method, "korean_")) return .composing;
        return .direct;
    }
};
```

**Canonical input method registry** — the authoritative mapping from protocol strings to libhangul keyboard IDs. Protocol docs reference this table, never duplicate it.

| Canonical string | libhangul keyboard ID | Description |
|---|---|---|
| `"direct"` | N/A | No composition — direct passthrough |
| `"korean_2set"` | `"2"` | Dubeolsik (standard, most common in Korea) |
| `"korean_2set_old"` | `"2y"` | Dubeolsik with historical/archaic jamo |
| `"korean_3set_dubeol"` | `"32"` | Sebeolsik mapped to 2-set key positions |
| `"korean_3set_390"` | `"39"` | Sebeolsik 390 |
| `"korean_3set_final"` | `"3f"` | Sebeolsik Final |
| `"korean_3set_noshift"` | `"3s"` | Sebeolsik Noshift (no Shift required) |
| `"korean_3set_old"` | `"3y"` | Sebeolsik with historical jamo |
| `"korean_romaja"` | `"ro"` | Latin-to-Hangul transliteration |
| `"korean_ahnmatae"` | `"ahn"` | Ahnmatae ergonomic layout |

v1 ships `"direct"` + `"korean_2set"` only. The full table is documented to establish the naming convention for all libhangul keyboards.

**Why the engine owns the mapping (not the server):**
- The engine is the only consumer of libhangul keyboard IDs — it calls `hangul_ic_new()` and `hangul_ic_select_keyboard()`.
- A cross-component mapping table (previously in protocol doc 05 Section 4.3) produced the `"korean_3set_390" -> "3f"` bug (should be `"39"`). Moving the mapping into the engine eliminates this bug class.
- The mapping is a trivial static table, unit-testable in isolation.

**`processKeyImpl` handling of `hangul_ic_process()` return value:**

The implementation must handle the case where `hangul_ic_process()` returns `false` (key rejected by libhangul). See [Section 2: Phase 1 hangul_ic_process() Return-False Handling](01-overview.md#phase-1-hangul_ic_process-return-false-handling) for the full algorithm.

**Composition state constants** — Korean-specific string constants for `ImeResult.composition_state`:

```zig
pub const CompositionStates = struct {
    pub const leading_jamo = "ko_leading_jamo";
    pub const vowel_only = "ko_vowel_only";
    pub const syllable_no_tail = "ko_syllable_no_tail";
    pub const syllable_with_tail = "ko_syllable_with_tail";
    pub const double_tail = "ko_double_tail";
};
```

> When no composition is active, `ImeResult.composition_state` is `null`. There is no string constant for this state — `null` is the canonical representation.

> **Naming convention**: When a language has exactly one composition state graph shared by all its input method variants, use ISO 639-1 prefix (`ko_`, `ja_`). When a language has multiple input methods with **distinct composition state graphs**, use `{iso639}_{method}_` prefix (`zh_pinyin_`, `zh_bopomofo_`, `zh_cangjie_`). The discriminating factor is the composition model, not the region or locale.
>
> | Language | Prefix | Rationale |
> |---|---|---|
> | Korean | `ko_` | One state graph for all variants (2-set, 3-set, romaja all share the same syllable/jamo model) |
> | Japanese | `ja_` | One state graph |
> | Chinese Pinyin | `zh_pinyin_` | Distinct state graph from Bopomofo/Cangjie |
> | Chinese Bopomofo | `zh_bopomofo_` | Distinct state graph |
> | Chinese Cangjie | `zh_cangjie_` | Distinct state graph |
>
> When the same input method supports multiple character sets (e.g., Pinyin for both Traditional and Simplified Chinese), the composition state prefix reflects the input method's state graph, not the character set. Character set selection is a configuration parameter of the engine, distinguished by the `input_method` identifier (e.g., `"chinese_pinyin_traditional"` vs `"chinese_pinyin_simplified"`), not by the composition state prefix.
>
> The `ko_` prefix is used for composition states (engine-internal runtime state), NOT for input method identifiers (which use the full `"korean_"` prefix).

`ko_vowel_only` is produced when a vowel is entered without a preceding consonant. This occurs naturally in 3-set (Sebeolsik) layouts where consonant and vowel keys are physically separated. In 2-set (Dubeolsik), libhangul inserts an implicit ㅇ leading consonant, producing `ko_syllable_no_tail` instead. The scenario matrix in [Section 3.2](02-types.md#32-imeresult-output-from-ime) illustrates 2-set behavior (v1 default) and is not exhaustive of all reachable states.

**Session persistence**: `active_input_method` (string) is the only **engine-internal** field needed to reconstruct a `HangulImeEngine` on session restore — the server creates a new engine with the saved `input_method` string. However, the full per-session persistence schema also saves `keyboard_layout` (orthogonal to `input_method`). Composition state is never persisted — it is flushed on session deactivation before the session is saved. See [Section 9](05-extensibility-and-deployment.md#9-session-persistence) for the full persistence schema.

### 3.8 MockImeEngine (For Testing)

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
test "committed text is sent to ghostty_surface_key" {
    var mock = MockImeEngine{
        .results = &.{
            .{ .committed_text = "한", .preedit_changed = true },
        },
    };
    var session = Session.initWithEngine(mock.engine());
    session.handleKeyEvent(focused_pane, .{ .hid_keycode = 0x15, .modifiers = .{}, .shift = false, .action = .press });
    // Assert ghostty_surface_key was called with composing=false, text="한"
}
```
