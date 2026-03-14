# HangulImeEngine Internals

**Status**: Draft v1.0-r1
**Date**: 2026-03-14
**Scope**: Concrete implementation details of `HangulImeEngine` -- struct fields, engine mode dispatch, libhangul keyboard ID mapping, internal buffer layout, and `setActiveInputMethod` internal step sequence.

> This document describes **implementation internals** of the `HangulImeEngine` concrete type. For the caller-facing API contract (`ImeEngine` vtable, `ImeResult`, `KeyEvent`), see [interface-contract](../../interface-contract/draft/v1.0-r8/03-engine-interface.md).

---

## 1. HangulImeEngine Concrete Struct

```zig
/// Concrete IME engine wrapping libhangul for Korean + direct mode passthrough.
pub const HangulImeEngine = struct {
    hic: *c.HangulInputContext,
    active_input_method: []const u8,  // e.g., "korean_2set" -- the canonical protocol string
    engine_mode: EngineMode,          // cached for hot path -- derived from active_input_method

    // Internal fixed-size buffers for ImeResult slices
    committed_buf: [256]u8 = undefined,
    preedit_buf: [64]u8 = undefined,
    committed_len: usize = 0,
    preedit_len: usize = 0,

    // Previous preedit for dirty tracking (content-based, not length-only)
    prev_preedit_buf: [64]u8 = undefined,
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
};
```

### 1.1 Field Descriptions

| Field | Type | Purpose |
|-------|------|---------|
| `hic` | `*c.HangulInputContext` | Pointer to the libhangul input context. Created via `hangul_ic_new(keyboard_id)`. Owns all composition state internally. |
| `active_input_method` | `[]const u8` | The canonical protocol string (e.g., `"korean_2set"`, `"direct"`). Single source of truth for the current input method. |
| `engine_mode` | `EngineMode` | Cached dispatch tag derived from `active_input_method`. Avoids string comparison on every `processKey()` call. |
| `committed_buf` | `[256]u8` | Fixed-size buffer holding committed UTF-8 text for the current `ImeResult`. |
| `preedit_buf` | `[64]u8` | Fixed-size buffer holding preedit UTF-8 text for the current `ImeResult`. |
| `committed_len` | `usize` | Valid byte count in `committed_buf`. |
| `preedit_len` | `usize` | Valid byte count in `preedit_buf`. |
| `prev_preedit_buf` | `[64]u8` | Copy of preedit content from the previous `processKey()` call. Used together with `prev_preedit_len` for content-based `preedit_changed` dirty tracking. |
| `prev_preedit_len` | `usize` | Byte count of the previous preedit content (in `prev_preedit_buf`). `preedit_changed` is `false` only when both this length **and** the content in `prev_preedit_buf` exactly match the current preedit. Length-only comparison is insufficient: e.g., "ㄱ" (U+3131, 3 bytes) → "가" (U+AC00, 3 bytes) after a vowel keystroke must produce `preedit_changed = true` despite identical byte lengths. |

### 1.2 EngineMode

```zig
const EngineMode = enum { direct, composing };
```

`EngineMode` is an internal optimization, NOT part of the public API. It controls hot-path dispatch in `processKeyImpl`:

- **`direct`**: Key is mapped to ASCII and returned as `committed_text`. No libhangul involvement. Used for `"direct"` input method (English, Latin scripts).
- **`composing`**: Key is fed to `hangul_ic_process()` for jamo composition. Used for all `"korean_*"` input methods.

Derivation is trivial:

```zig
fn deriveMode(input_method: []const u8) EngineMode {
    if (std.mem.startsWith(u8, input_method, "korean_")) return .composing;
    return .direct;
}
```

---

## 2. libhangul Keyboard ID Mapping

The engine maps canonical input method strings to libhangul keyboard IDs. This mapping is internal to the engine -- no other component needs to know libhangul keyboard IDs.

```zig
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
```

### 2.1 Canonical Input Method Registry

| Canonical string | libhangul keyboard ID | Description |
|---|---|---|
| `"direct"` | N/A | No composition -- direct passthrough |
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
- The engine is the only consumer of libhangul keyboard IDs -- it calls `hangul_ic_new()` and `hangul_ic_select_keyboard()`.
- A cross-component mapping table (previously in protocol doc 05 Section 4.3) produced the `"korean_3set_390" -> "3f"` bug (should be `"39"`). Moving the mapping into the engine eliminates this bug class.
- The mapping is a trivial static table, unit-testable in isolation.

---

## 3. Internal Buffer Layout and Sizing

`ImeResult` fields (`committed_text`, `preedit_text`) are slices pointing into fixed-size internal buffers owned by the `HangulImeEngine` instance:

```
committed_buf: [256]u8  -- holds committed UTF-8 text
preedit_buf:   [64]u8   -- holds preedit UTF-8 text
```

### 3.1 Buffer Sizing Rationale

- **256 bytes for committed text**: A single Korean syllable is 3 bytes UTF-8. The longest possible commit from one keystroke is a flushed syllable + a non-jamo character = ~6 bytes. 256 bytes is vastly oversized for safety.
- **64 bytes for preedit**: A single composing syllable is always exactly one character (3 bytes UTF-8). 64 bytes is vastly oversized for safety.

### 3.2 libhangul Memory Model Reference

This design mirrors libhangul's own memory model -- `hangul_ic_get_preedit_string()` returns an internal pointer invalidated by the next `hangul_ic_process()` call. The engine copies libhangul's UCS-4 output into its own UTF-8 buffers. Zero heap allocation per keystroke.

### 3.3 Slice Lifetime

Slices are valid until the next call to `processKey()`, `flush()`, `reset()`, `deactivate()`, or `setActiveInputMethod()` on the **same** engine instance.

**Caller responsibility**: If the caller needs to retain the text across multiple `processKey()` calls, it must copy the data. See [daemon design doc 02 &sect;4.6](../../../../libitshell3/02-design-docs/daemon/draft/v1.0-r4/02-integration-boundaries.md#46-critical-runtime-invariant) for the daemon's consumption invariant.

---

## 4. setActiveInputMethod Internal Step Sequence

`setActiveInputMethod()` is the only input-method-switching method. Its internal steps depend on whether the requested input method differs from the current one.

### 4.1 Case 1: Switching to a Different Input Method

Example: `"korean_2set"` -> `"direct"`

1. Call `hangul_ic_flush()` internally to commit any in-progress composition.
2. Read the flushed string from libhangul.
3. Set `active_input_method = new_method`.
4. Update internal engine mode and libhangul keyboard if needed.
5. Return `ImeResult`:
   - If composition was active (flushed text is non-empty): `ImeResult{ .committed_text = flushed_text, .preedit_text = null, .forward_key = null, .preedit_changed = true }`.
   - If composition was not active (engine was already empty): `ImeResult{ .committed_text = null, .preedit_text = null, .forward_key = null, .preedit_changed = false }`.

`preedit_changed` is `true` only when the preedit state actually transitions (non-null to null from flushing). When the engine was already empty, preedit remains null throughout -- no transition occurred.

### 4.2 Case 2: Same Input Method (No-op)

Example: `"korean_2set"` -> `"korean_2set"`

Return `ImeResult{}` (all null/false). No flush, no state change.

**Rationale**: The user toggled to the same mode by mistake (or the framework called it redundantly). Flushing would be a surprising side effect. This matches fcitx5 (`InputMethodManager::setCurrentGroup()`) and ibus (`ibus_bus_set_global_engine()`), both of which treat same-engine switches as no-ops.

### 4.3 Case 3: Unsupported Input Method

Return `error.UnsupportedInputMethod`. The server MUST only send input method strings from the canonical registry (Section 2). Receiving an unrecognized string is a server bug.

### 4.4 hangul_ic_flush() Cleanup

`hangul_ic_flush()` alone is sufficient -- no need to call `hangul_ic_reset()` after flush. Verified in libhangul source: `hangul_ic_flush()` calls `hangul_buffer_clear()` which zeroes all jamo fields (`choseong`, `jungseong`, `jongseong`) and clears the stack. After flush, `hangul_ic_is_empty()` returns true.

---

## 5. processKeyImpl Note

The `processKeyImpl` function must handle the case where `hangul_ic_process()` returns `false` (key rejected by libhangul). See [11-hangul-ic-process-handling.md](11-hangul-ic-process-handling.md) for the full algorithm.

---

## 6. Session Persistence

`active_input_method` (string) is the only **engine-internal** field needed to reconstruct a `HangulImeEngine` on session restore -- the server creates a new engine with the saved `input_method` string. Composition state is never persisted -- the engine always starts with empty composition. See [daemon design doc 02 &sect;4.1](../../../../libitshell3/02-design-docs/daemon/draft/v1.0-r4/02-integration-boundaries.md#41-per-session-imeengine-lifecycle) for the full persistence and lifecycle details.
