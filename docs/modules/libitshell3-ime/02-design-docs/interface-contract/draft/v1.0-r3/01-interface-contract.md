# 01 — libitshell3 <-> libitshell3-ime Interface Contract

> **Status**: Draft v0.3 — PoC-validated, all resolutions applied.
> **Supersedes**: [v0.2/01-interface-contract.md](../v1.0-r2/01-interface-contract.md), [v0.1/01-interface-contract.md](../v1.0-r1/01-interface-contract.md), interface-design.md (deleted, merged here), portions of [04-architecture.md](../../../01-overview/04-architecture.md), and [05-integration-with-libitshell3.md](../../../01-overview/05-integration-with-libitshell3.md).
> **Review participants**: principal-architect, ime-expert, ghostty-expert
> **PoC validation**: `poc/02-ime-ghostty-real/poc-ghostty-real.m` — 22/24 tests pass (2 skipped due to libghostty VT parser bug, not IME code)
> **Changes from v0.2**: See [Appendix D: Changes from v0.2](#appendix-d-changes-from-v02)

## 1. Overview

This document defines the **exact interface** between libitshell3 (terminal multiplexer daemon) and libitshell3-ime (native IME engine). It specifies:

- The types that cross the boundary (input and output)
- Who is responsible for what
- How the IME output maps to libghostty API calls
- Memory ownership and lifetime rules
- Future extensibility for Japanese/Chinese without v1 overhead

### Design Principles

1. **Single interface for all languages.** No engine-type flags, no capability negotiation. Korean simply never populates candidates. (Informed by fcitx5/ibus: both use one `keyEvent` method for all languages.)
2. **Engine owns composition decisions.** The IME engine decides when to flush on modifiers, not the framework. (Informed by ibus-hangul, fcitx5-hangul patterns.)
3. **Struct return over callbacks.** `processKey()` returns an `ImeResult` struct — simpler and more testable than side-effect callbacks. Candidate lists (future) use a separate optional callback channel.
4. **Don't make the common path pay for the uncommon path.** English/Korean processing adds zero overhead for future Japanese/Chinese candidate support.
5. **Testable via trait.** libitshell3 depends on an `ImeEngine` interface, not the concrete implementation. Mock injection for tests.
6. **Framework owns language management.** libitshell3 (the framework) decides what languages are available and which is active. The engine receives `setActiveLanguage()` calls and processes keys accordingly. (Informed by fcitx5/ibus: language enumeration and toggle logic live in the framework, not in individual engines.)

---

## 2. Processing Pipeline

### Three-Phase Key Processing

```
Client sends: HID keycode + modifiers + shift
                    |
                    v
+--------------------------------------------------+
|  Phase 0: Global Shortcut Check (libitshell3)    |
|                                                   |
|  - Language switch -> setActiveLanguage(lang_id)  |
|    (toggle key detection is libitshell3's concern)|
|  - App-level shortcuts that bypass IME entirely   |
|  - If consumed: STOP                              |
+----------------------+---------------------------+
                       | not consumed
                       v
+--------------------------------------------------+
|  Phase 1: IME Engine (libitshell3-ime)           |
|                                                   |
|  processKey(KeyEvent) -> ImeResult                |
|                                                   |
|  Engine internally:                               |
|  - Checks modifiers (Ctrl/Alt/Cmd) -> flush + fwd|
|  - Checks non-printable (arrow/F-key) -> flush+fwd|
|  - Feeds printable to libhangul -> compose        |
|  - Handles "not consumed" (hangul_ic_process()    |
|    returns false): flush + forward rejected key   |
|  - Returns committed/preedit/forward_key          |
+----------------------+---------------------------+
                       | ImeResult
                       v
+--------------------------------------------------+
|  Phase 2: ghostty Integration (libitshell3)      |
|                                                   |
|  committed_text -> ghostty_surface_key            |
|                   (composing=false, text=utf8)    |
|                   + RELEASE event (text=null)     |
|                                                   |
|  preedit_text   -> ghostty_surface_preedit        |
|                   (utf8, len)                     |
|                                                   |
|  forward_key    -> HID->ghostty_key mapping       |
|                 -> ghostty keybinding check        |
|                 -> if not bound: ghostty_surface_key|
|                   (composing=false, text=null*)   |
|                   + RELEASE event (text=null)     |
|                                                   |
|  * Exception: Space forward uses text=" "         |
+--------------------------------------------------+
```

### Why IME Runs Before Keybindings

When the user presses Ctrl+C during Korean composition (preedit = "하"):

1. **Phase 0 (shortcuts)**: libitshell3 checks — Ctrl+C is not a language toggle or global shortcut. Pass through.
2. **Phase 1 (IME)**: Engine detects Ctrl modifier -> flushes "하" -> returns `{ committed: "하", forward_key: Ctrl+C }`
3. **Phase 2 (ghostty)**: Committed text "하" is sent to PTY via `ghostty_surface_key`. Then Ctrl+C goes through ghostty's keybinding system. If Cmd+C is bound to "copy", it fires. If not, `ghostty_surface_key` encodes it as `0x03` (ETX).

This ensures the user's in-progress composition is preserved before any keybinding action.

**Verified by PoC** (`poc/01-ime-key-handling/`): All 10 test scenarios pass — arrows, Ctrl+C, Ctrl+D, Enter, Escape, Tab, backspace jamo-undo, shifted keys, and mixed compose-arrow-compose sequences all work correctly with libhangul.

### Phase 1: hangul_ic_process() Return-False Handling

When `hangul_ic_process()` returns `false`, libhangul rejected the key (it is not a valid jamo for the current keyboard layout). This occurs with punctuation, certain number keys, and other characters libhangul does not recognize.

**Correct handling:**

1. Call `hangul_ic_process(hic, ascii)`.
2. **Regardless of return value**: Check `hangul_ic_get_commit_string()` and `hangul_ic_get_preedit_string()`. libhangul may update these even when returning false (e.g., a syllable break may produce committed text before the rejected character).
3. **If `hangul_ic_process()` returned false**:
   - If composition was non-empty, flush remaining composition via `hangul_ic_flush()`.
   - Forward the rejected key to the terminal.
4. Populate `ImeResult` with any committed text, updated preedit, and the forwarded key.

**Example**: User types "ㅎ" then ".":
- `hangul_ic_process(hic, '.')` returns false (period is not a jamo).
- `hangul_ic_get_commit_string()` returns empty (no syllable break triggered).
- `hangul_ic_get_preedit_string()` still returns "ㅎ" (still composing).
- Since not consumed: flush "ㅎ", forward ".".
- Result: `{ committed: "ㅎ", preedit: null, forward_key: '.', preedit_changed: true }`.

**Verified by PoC** (`poc/02-ime-ghostty-real/poc-ghostty-real.m` lines 298–324).

---

## 3. Interface Types

### 3.1 KeyEvent (Input to IME)

```zig
/// A key event from the client, represented as a physical key press.
/// This is the input to the IME engine's processKey() method.
pub const KeyEvent = struct {
    /// USB HID usage code (Keyboard page 0x07).
    /// Represents the PHYSICAL key position, not the character produced.
    /// e.g., 0x04 = 'a' position, 0x28 = Enter, 0x4F = Right Arrow
    hid_keycode: u8,

    /// Modifier key state (excluding Shift -- see `shift` field).
    modifiers: Modifiers,

    /// Shift key state. Separated from modifiers because Shift changes
    /// the character produced (e.g., 'r'->ㄱ vs 'R'->ㄲ in Korean 2-set),
    /// whereas Ctrl/Alt/Cmd trigger composition flush.
    shift: bool,

    /// Key press action.
    action: Action,

    pub const Action = enum {
        press,
        release,
        repeat,
    };

    pub const Modifiers = packed struct(u8) {
        ctrl: bool = false,
        alt: bool = false,
        super_key: bool = false,
        _padding: u5 = 0,
    };

    /// Returns true if any composition-breaking modifier is held.
    pub fn hasCompositionBreakingModifier(self: KeyEvent) bool {
        return self.modifiers.ctrl or self.modifiers.alt or self.modifiers.super_key;
    }

    /// Returns true if this is a printable key position (letters, digits, punctuation).
    /// Based on HID usage codes for the US ANSI keyboard.
    pub fn isPrintablePosition(self: KeyEvent) bool {
        return (self.hid_keycode >= 0x04 and self.hid_keycode <= 0x38);
    }
};
```

**Design notes:**
- `hid_keycode` is the USB HID usage code — a physical key position. Korean input depends on physical key position (not the produced character), making HID the correct representation.
- `shift` is separate from `modifiers` because Shift participates in character production (Korean jamo selection), while Ctrl/Alt/Cmd trigger composition flush. This mirrors the ibus-hangul pattern where `IBUS_CONTROL_MASK | IBUS_MOD1_MASK` triggers flush but `IBUS_SHIFT_MASK` does not.
- `action` (press/release/repeat) added based on ghostty's `ghostty_input_action_e`. Release events are needed for future Kitty keyboard protocol support. The IME engine typically ignores release events.

### 3.2 ImeResult (Output from IME)

```zig
/// The result of processing a key event through the IME engine.
/// All three output fields are orthogonal -- any combination is valid.
///
/// Memory: all slices point into internal buffers owned by the ImeEngine
/// instance. They are valid until the next call to processKey(), flush(),
/// reset(), or setActiveLanguage() on the SAME engine instance.
pub const ImeResult = struct {
    /// UTF-8 text to commit to the terminal (write to PTY).
    /// null if nothing to commit.
    ///
    /// Examples:
    ///   - Korean syllable completed: "한"
    ///   - Composition flushed by modifier: "하"
    ///   - English passthrough: "a"
    committed_text: ?[]const u8 = null,

    /// UTF-8 preedit text for display overlay.
    /// null if no active composition.
    ///
    /// Examples:
    ///   - Mid-composition: "가"
    ///   - Composition ended: null (client should clear overlay)
    preedit_text: ?[]const u8 = null,

    /// Key event to forward to the terminal (for escape sequence encoding).
    /// null if the key was fully consumed by the IME.
    ///
    /// Examples:
    ///   - Arrow key during composition: the arrow key event
    ///   - Ctrl+C during composition: the Ctrl+C key event
    ///   - Korean jamo key: null (consumed)
    forward_key: ?KeyEvent = null,

    /// True if preedit state changed from the previous call.
    /// Used for dirty tracking -- only send preedit updates to client
    /// when this is true.
    ///
    /// MANDATORY for production: the engine MUST set this accurately.
    /// - true when preedit transitions: null->non-null, non-null->null,
    ///   or non-null->different-non-null.
    /// - false when preedit is unchanged (e.g., direct mode key,
    ///   release event, modifier with no active composition).
    ///
    /// Callers MAY ignore this flag and call ghostty_surface_preedit()
    /// unconditionally as a safety fallback during debugging. This is
    /// always correct but wasteful — see Section 5 for details.
    preedit_changed: bool = false,
};
```

**Scenario matrix:**

| Situation | committed | preedit | forward_key | preedit_changed |
|-----------|-----------|---------|-------------|-----------------|
| English 'a' (direct mode) | `"a"` | null | null | false |
| English Shift+'a' (direct mode) | `"A"` | null | null | false |
| Direct mode Enter | null | null | Enter key | false |
| Direct mode Space | null | null | Space key | false |
| Direct mode Ctrl+C | null | null | Ctrl+C key | false |
| Direct mode Arrow | null | null | Arrow key | false |
| Direct mode Escape | null | null | Escape key | false |
| Korean ㄱ (start composing) | null | `"ㄱ"` | null | true |
| Korean 가 (add vowel) | null | `"가"` | null | true |
| Korean 간 -> new ㄱ (syllable break) | `"간"` | `"ㄱ"` | null | true |
| Arrow during composition | `"한"` (flush) | null | arrow key | true |
| Ctrl+C during composition | `"하"` (flush) | null | Ctrl+C key | true |
| Enter during composition | `"ㅎ"` (flush) | null | Enter key | true |
| Space during composition | `"한"` (flush) | null | Space key | true |
| Backspace mid-composition | null | `"하"` (undo) | null | true |
| Backspace empty composition | null | null | Backspace | false |
| Space with empty composition | null | null | Space key | false |
| English Ctrl+C (no composition) | null | null | Ctrl+C key | false |
| Language toggle (Korean->direct) | `"한"` (flush) | null | null | true |
| Release event | null | null | null | false |

**Direct mode behavior**: In direct mode, `processKey()` performs a simple branch:
- Printable key without modifiers -> HID-to-ASCII lookup -> `committed_text = ascii_char`, no forward.
- Everything else (non-printable, modified, unmapped) -> `forward_key = original_key`, no committed text.
- Direct mode never has preedit (no composition), so `preedit_changed` is always false.

### 3.3 Modifier Flush Policy

When the IME has active preedit and a modifier+key or special key arrives, the engine **flushes (commits)** the in-progress composition, then forwards the key. The preedit is never silently discarded.

| Key Type | Preedit Action | Rationale |
|---|---|---|
| Ctrl+key | **Flush** (commit preedit) | Preserve user's typed text before command execution |
| Alt+key | **Flush** (commit preedit) | Same as Ctrl |
| Super/Cmd+key | **Flush** (commit preedit) | Same as Ctrl |
| Enter | **Flush** (commit preedit) | User intends to submit what they typed |
| Tab | **Flush** (commit preedit) | User is moving forward (tab completion) |
| Escape | **Flush** (commit preedit) | Commit what user typed, then forward Escape |
| Arrow keys | **Flush** (commit preedit) | User is navigating -- commit what they have |
| Space | **Flush** (commit preedit) | Word separator -- commit syllable, then insert space |
| Backspace | **IME handles** | `hangul_ic_backspace()` undoes last jamo; if empty, forward |

**Example -- Ctrl+C during preedit "하":**
```
ImeResult{ .committed_text = "하", .preedit_text = null,
           .forward_key = Ctrl+C, .preedit_changed = true }
```
The committed text "하" is written to PTY first, then Ctrl+C sends SIGINT. The user's in-progress text is preserved.

**Verification**: This matches the actual behavior of both **ibus-hangul** (`ibus_hangul_engine_process_key_event()` calls `hangul_ic_flush()` on `IBUS_CONTROL_MASK | IBUS_MOD1_MASK`) and **fcitx5-hangul** (`HangulState::keyEvent()` calls `flush()` on modifier detection). Both commit the preedit -- neither discards it.

> **Note**: The `interface-design.md` (Section 1.4) previously specified RESET (discard) for Ctrl/Alt/Super modifiers. That was incorrect -- it claimed to match ibus-hangul but ibus-hangul actually flushes (commits). This contract corrects that error.

### 3.4 LanguageId

```zig
/// A language identifier. Determines which composition engine processes keys.
/// libitshell3 configures the available languages and tells libitshell3-ime
/// which one is active. Language switching (toggle key detection, UI) is
/// entirely libitshell3's concern.
pub const LanguageId = enum(u8) {
    /// Direct passthrough -- no composition. Used for English, Latin scripts,
    /// and any layout where keys map directly to characters.
    /// Named "direct" (not "english") because it applies to any non-composing layout.
    direct = 0,

    /// Korean -- Hangul composition via libhangul.
    /// Jamo are assembled into syllables algorithmically.
    korean = 1,

    // Future:
    // japanese = 2,  // Kana composition + kanji candidate selection (libkkc/libmozc)
    // chinese = 3,   // Pinyin composition + hanzi candidate selection (librime)
};
```

**Language management protocol (simplified from v0.1):**

libitshell3 owns language selection. The interaction is:

1. **At startup**: libitshell3 creates the engine knowing what languages it supports (hardcoded for v1: direct + korean). No runtime discovery needed.
2. **Language switch**: When the user presses the toggle key (detected by libitshell3), libitshell3 calls `setActiveLanguage(lang_id)`. The IME atomically flushes any pending composition and switches.
3. **Synchronization**: libitshell3 can call `getActiveLanguage()` at any time to query the current state (e.g., after session restore).

**Removed from v0.1**: `getSupportedLanguages()`, `setEnabledLanguages()`, and `LanguageDescriptor` are removed. In fcitx5 and ibus, language enumeration and enable/disable are framework-level concerns, not engine concerns. libitshell3 is the framework -- it knows what languages are available because it created the engine.

**Composing-capable check**: For v1, `getActiveLanguage() != .direct` is sufficient to determine whether the active language supports composition. The `isEmpty()` method provides the runtime check for whether composition is actually in progress.

### 3.5 ImeEngine (Interface for Dependency Injection)

```zig
/// Abstract interface for an IME engine. libitshell3's Pane holds an ImeEngine
/// rather than a concrete type, enabling mock injection for tests.
///
/// Modeled after fcitx5's InputMethodEngine: a minimal interface where only
/// processKey() is required. activate/deactivate handle focus changes.
pub const ImeEngine = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Process a key event. Returns committed text, preedit update,
        /// and/or a key to forward. This is the only required method.
        processKey: *const fn (ptr: *anyopaque, key: KeyEvent) ImeResult,

        /// Flush and commit any in-progress composition.
        /// Used when: pane switch, language switch, focus loss.
        flush: *const fn (ptr: *anyopaque) ImeResult,

        /// Discard in-progress composition without committing.
        /// Used when: session close, error recovery.
        reset: *const fn (ptr: *anyopaque) void,

        /// Query whether composition is in progress.
        isEmpty: *const fn (ptr: *anyopaque) bool,

        /// Pane gained focus. Engine may restore visual state.
        /// No-op for Korean (state is preserved in the buffer).
        /// Language mode (active_language) is preserved across
        /// deactivate/activate cycles -- NOT reset to direct.
        activate: *const fn (ptr: *anyopaque) void,

        /// Pane lost focus. Engine should flush pending composition.
        /// (Commit the in-progress syllable so it's not lost.)
        /// Language mode (active_language) is NOT changed.
        deactivate: *const fn (ptr: *anyopaque) ImeResult,

        // --- Language management ---

        /// Get current active language.
        getActiveLanguage: *const fn (ptr: *anyopaque) LanguageId,

        /// Set active language. Flushes pending composition atomically
        /// if switching away from a composing language.
        /// If lang matches the current active language, this is a no-op
        /// (returns empty ImeResult, no flush).
        /// Called by libitshell3 when user presses the toggle key.
        /// forward_key in the returned ImeResult is always null --
        /// the toggle key is consumed by Phase 0.
        setActiveLanguage: *const fn (ptr: *anyopaque, lang: LanguageId) ImeResult,
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

    pub fn getActiveLanguage(self: ImeEngine) LanguageId {
        return self.vtable.getActiveLanguage(self.ptr);
    }

    pub fn setActiveLanguage(self: ImeEngine, lang: LanguageId) ImeResult {
        return self.vtable.setActiveLanguage(self.ptr, lang);
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
| `activate` | Pane gained focus | void |
| `deactivate` | Pane lost focus (flushes) | ImeResult |
| `getActiveLanguage` | Query current language | LanguageId |
| `setActiveLanguage` | Switch language (flushes atomically) | ImeResult |

**Why vtable over comptime generics:**
- Comptime generics (`fn Pane(comptime Ime: type) type`) would monomorphize all Pane code per IME type, inflating binary size when multiple engines exist.
- vtable is a single pointer indirection — negligible cost at the call rates we see (< 100 calls/second for human typing).
- vtable works with C FFI (comptime generics don't export to C).

### 3.6 setActiveLanguage Behavior

`setActiveLanguage()` is the only language-switching method. Its behavior depends on whether the requested language differs from the current one:

**Case 1: Switching to a different language (e.g., korean -> direct):**

1. Call `hangul_ic_flush()` internally to commit any in-progress composition.
2. Read the flushed string from libhangul.
3. Set `active_language = new_language_id`.
4. Return `ImeResult{ .committed_text = flushed_text, .preedit_text = null, .forward_key = null, .preedit_changed = true }`.

**Case 2: "Switching" to the already-active language (e.g., korean -> korean):**

Return `ImeResult{}` (all null/false). No flush, no state change.

**Rationale for no-op on same-language**: The user toggled to the same mode by mistake (or the framework called it redundantly). Flushing would be a surprising side effect — the user didn't intend to commit their in-progress composition. This matches fcitx5 (`InputMethodManager::setCurrentGroup()`) and ibus (`ibus_bus_set_global_engine()`), both of which treat same-engine switches as no-ops.

**Atomicity**: `setActiveLanguage()` flushes and switches in a single call. The caller must NOT call `flush()` then `setActiveLanguage()` separately — a key event arriving between those two calls could be processed in the wrong language.

**forward_key is always null**: `setActiveLanguage()` is called from Phase 0 in response to a toggle key that has already been consumed. There is no key to forward. If a toggle key (e.g., Right Alt) leaked through to ghostty, it would produce garbage escape sequences (`\e` prefix for Alt).

**libhangul cleanup**: `hangul_ic_flush()` alone is sufficient — no need to call `hangul_ic_reset()` after flush. Verified in libhangul source: `hangul_ic_flush()` calls `hangul_buffer_clear()` which zeroes all jamo fields (`choseong`, `jungseong`, `jongseong`) and clears the stack. After flush, `hangul_ic_is_empty()` returns true.

### 3.7 HangulImeEngine (Concrete Implementation)

```zig
/// Concrete IME engine wrapping libhangul for Korean + direct mode passthrough.
pub const HangulImeEngine = struct {
    hic: *c.HangulInputContext,
    active_language: LanguageId,
    layout_id: []const u8,  // e.g., "2" for dubeolsik (string, not enum)

    // Internal fixed-size buffers for ImeResult slices
    committed_buf: [256]u8 = undefined,
    preedit_buf: [64]u8 = undefined,
    committed_len: usize = 0,
    preedit_len: usize = 0,

    // Previous preedit for dirty tracking
    prev_preedit_len: usize = 0,

    pub fn init(allocator: Allocator, layout_id: []const u8) !HangulImeEngine;
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
    fn getActiveLanguageImpl(ptr: *anyopaque) LanguageId;
    fn setActiveLanguageImpl(ptr: *anyopaque, lang: LanguageId) ImeResult;
};
```

**Why `layout_id` is a string, not an enum:**
- libhangul identifies keyboards by string ID ("2", "3f", "ro", etc.).
- An enum would need to stay in sync with libhangul's keyboard list.
- libhangul supports external keyboards loaded from XML files — an enum can't represent those.
- v1 ships dubeolsik ("2") only. Additional layouts are a config change, not an API change.

**`processKeyImpl` handling of `hangul_ic_process()` return value:**

The implementation must handle the case where `hangul_ic_process()` returns `false` (key rejected by libhangul). See [Section 2: Phase 1 hangul_ic_process() Return-False Handling](#phase-1-hangul_ic_process-return-false-handling) for the full algorithm.

### 3.8 MockImeEngine (For Testing)

```zig
pub const MockImeEngine = struct {
    /// Queue of results to return from processKey, in order.
    results: []const ImeResult,
    call_index: usize = 0,
    active_language: LanguageId = .direct,
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
        .getActiveLanguage = getActiveLanguageImpl,
        .setActiveLanguage = setActiveLanguageImpl,
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
    var pane = Pane.initWithEngine(mock.engine());
    pane.handleKeyEvent(.{ .hid_keycode = 0x15, .modifiers = .{}, .shift = false, .action = .press });
    // Assert ghostty_surface_key was called with composing=false, text="한"
}
```

---

## 4. Responsibility Matrix

| Responsibility | Owner | Rationale |
|---|---|---|
| HID keycode -> ASCII character | **libitshell3-ime** | IME needs ASCII for `hangul_ic_process()`. Mapping is layout-dependent (Korean 2-set vs 3-set). |
| HID keycode -> platform-native keycode | **libitshell3** | ghostty's key encoder uses platform-native keycodes (`uint32_t`). IME-independent. |
| Hangul composition (jamo assembly, backspace) | **libitshell3-ime** | Core IME logic. Wraps libhangul. |
| Modifier detection + flush decision | **libitshell3-ime** | Engine decides when Ctrl/Alt/Cmd flushes composition. Matches ibus-hangul/fcitx5-hangul pattern. All modifiers **flush** (commit), never reset (discard). |
| UCS-4 -> UTF-8 conversion | **libitshell3-ime** | libhangul outputs UCS-4. The rest of the system uses UTF-8. |
| Language toggle key detection | **libitshell3** | Configurable keybinding (한/영, Right Alt, Caps Lock). Not an IME concern. |
| Active language switching | **libitshell3** | Calls `setActiveLanguage(lang_id)` when user toggles. |
| Flushing on language switch | **libitshell3-ime** | `setActiveLanguage()` flushes pending composition internally (atomically). |
| Keybinding interception (Cmd+V, Cmd+C) | **libitshell3 via ghostty** | Keybindings run in Phase 2, after IME has flushed. |
| Calling `ghostty_surface_key()` | **libitshell3** | Daemon translates ImeResult into ghostty API calls. |
| Calling `ghostty_surface_preedit()` | **libitshell3** | Daemon forwards preedit to ghostty's renderer overlay. |
| Terminal escape sequence encoding | **ghostty** (via `ghostty_surface_key`) | ghostty's KeyEncoder runs daemon-side. We do NOT write our own encoder. |
| PTY writes | **ghostty** (internal to `ghostty_surface_key`) | ghostty handles PTY I/O internally after encoding. |
| Sending preedit/render state to remote client | **libitshell3** (protocol layer) | Part of the FrameUpdate protocol. |
| Rendering preedit overlay on screen | **it-shell3 app** (client) | Client receives preedit from server, renders via Metal. |
| Per-pane ImeEngine lifecycle | **libitshell3** | Creates/destroys engine per pane. Calls activate/deactivate on focus change. |
| Language indicator in FrameUpdate | **libitshell3** | Purely metadata field (`ime_mode: u8`, 0=direct, 1=korean). ghostty has no language state. |
| Composing-capable check | **libitshell3** | Derives from LanguageId: `direct = no`, `korean = yes`. Runtime check: `engine.isEmpty()`. No `LanguageDescriptor` needed. |

### What libitshell3-ime Does NOT Do

- Does NOT know about PTYs, sockets, sessions, panes, or protocols.
- Does NOT encode terminal escape sequences (no VT knowledge).
- Does NOT detect language toggle keys (that's libitshell3's keybinding concern).
- Does NOT decide when to switch languages (libitshell3 calls `setActiveLanguage()`).
- Does NOT interact with ghostty APIs (no ghostty dependency).
- Does NOT manage candidate window UI (app layer concern, future).
- Does NOT enumerate or manage language lists (framework concern).

---

## 5. ghostty Integration

### ghostty Input States

ghostty's `keyCallback` recognizes exactly four input states based on two fields (`composing` and `utf8`/`text`):

| ghostty State | `composing` | `text` | Behavior |
|---|---|---|---|
| **Committed text** | `false` | non-empty | Key encoder writes UTF-8 to PTY. Normal key processing. |
| **Composing (preedit active)** | `true` | non-empty | Key encoder produces NO output (legacy) or only modifiers (Kitty). Preedit displayed via separate `preeditCallback`. |
| **Forwarded key (no text)** | `false` | empty | Physical key encoded via function key tables, Ctrl sequences, etc. |
| **Composing cancel** | `true` | empty | Composition cancelled. Key encoder produces nothing. |

libitshell3 only uses the first and third states. We never set `composing=true` on `ghostty_surface_key()` — preedit is handled separately via `ghostty_surface_preedit()`.

### ImeResult -> ghostty API Mapping

The daemon's per-pane key handler translates `ImeResult` into ghostty calls. Every `ghostty_surface_key()` press event **MUST** be followed by a corresponding release event. The release event has `.action = .release` and `.text = null` (no text on release — re-sending text would double-commit).

```zig
fn handleKeyEvent(pane: *Pane, key: KeyEvent) void {
    const result = pane.ime.processKey(key);

    // 1. Send committed text (if any) via ghostty key event path
    //    NOTE: For committed text, keycode is non-critical -- ghostty uses
    //    the .text field for PTY output when composing=false and text is set.
    if (result.committed_text) |text| {
        const ghost_key = ghostty_input_key_s{
            .action = .press,
            .mods = .{},
            .consumed_mods = .{},
            .keycode = mapHidToGhosttyKey(key.hid_keycode),
            .text = text.ptr,
            .unshifted_codepoint = 0,
            .composing = false,  // committed text is NOT composing
        };
        ghostty_surface_key(pane.surface, ghost_key);

        // Release event -- MUST follow every press. No text on release.
        const release_key = ghostty_input_key_s{
            .action = .release,
            .mods = ghost_key.mods,
            .consumed_mods = .{},
            .keycode = ghost_key.keycode,
            .text = null,  // never re-send text on release
            .unshifted_codepoint = 0,
            .composing = false,
        };
        ghostty_surface_key(pane.surface, release_key);
    }

    // 2. Update preedit overlay (if changed)
    // MANDATORY: ghostty does NOT auto-clear preedit. From Surface.zig:
    // "The core surface will NOT reset the preedit state on charCallback
    // or keyCallback and we rely completely on the apprt implementation
    // to track the preedit state correctly."
    // libitshell3 MUST call ghostty_surface_preedit(NULL, 0) explicitly
    // whenever preedit_changed=true and preedit_text=null.
    //
    // NOTE: Skipping this call when preedit_changed=false is an
    // optimization, not a correctness requirement. Calling
    // ghostty_surface_preedit() unconditionally on every key event is
    // always correct (and recommended during debugging), but wasteful --
    // it triggers renderer state updates even when preedit hasn't changed.
    if (result.preedit_changed) {
        if (result.preedit_text) |text| {
            ghostty_surface_preedit(pane.surface, text.ptr, text.len);
        } else {
            ghostty_surface_preedit(pane.surface, null, 0); // explicit clear required
        }
    }

    // 3. Forward unconsumed key (if any) through ghostty's full pipeline
    //    NOTE: For forwarded keys, keycode is CRITICAL -- ghostty uses it
    //    for escape sequence encoding (Ctrl+C -> ETX, arrows -> escape
    //    sequences, etc.). Must be platform-native keycode.
    if (result.forward_key) |fwd| {
        const is_space = fwd.hid_keycode == 0x2C;
        const ghost_key = ghostty_input_key_s{
            .action = switch (fwd.action) {
                .press => .press,
                .release => .release,
                .repeat => .repeat,
            },
            .mods = mapModifiers(fwd.modifiers, fwd.shift),
            .consumed_mods = .{},
            .keycode = mapHidToGhosttyKey(fwd.hid_keycode),
            // Space is a printable key -- ghostty needs .text = " " to
            // produce the space character. Other special keys (Enter,
            // Escape, arrows) have dedicated encoding paths and use
            // .text = null.
            .text = if (is_space) " " else null,
            .unshifted_codepoint = if (is_space) ' ' else 0,
            .composing = false,
        };
        // Goes through ghostty's keybinding check -> key encoder -> PTY
        ghostty_surface_key(pane.surface, ghost_key);

        // Release event -- MUST follow every press
        const release_key = ghostty_input_key_s{
            .action = .release,
            .mods = ghost_key.mods,
            .consumed_mods = .{},
            .keycode = ghost_key.keycode,
            .text = null,  // never re-send text on release
            .unshifted_codepoint = 0,
            .composing = false,
        };
        ghostty_surface_key(pane.surface, release_key);
    }
}
```

**Keycode criticality by event type:**

| Event Type | `.text` field | Keycode impact |
|---|---|---|
| Committed text | Non-empty | **Non-critical** — ghostty uses `.text` for PTY output |
| Forwarded key (control/special) | null | **Critical** — ghostty uses keycode for escape sequence encoding |
| Forwarded Space | `" "` | **Non-critical** — ghostty uses `.text` for the space character |
| Language switch flush | Non-empty | **Non-critical** — use `.unidentified` (no originating key) |

### Press+Release Pairs

Every `ghostty_surface_key()` press event MUST be followed by a corresponding release event:

1. **Internal state tracking**: ghostty tracks key state internally. Sending press without release may leave ghostty's key state machine in an incorrect state.
2. **Kitty keyboard protocol (future)**: Kitty protocol mode requires release events for correct reporting. Legacy mode ignores releases (`key_encode.zig` line 322: `if (event.action != .press and event.action != .repeat) return;`), so releases are a no-op in legacy mode -- but sending them is harmless and forward-compatible.
3. **Release events always have `.text = null`**: Re-sending text on release would double-commit the text.

**Verified by PoC**: All 24 PoC test scenarios send press+release pairs and pass.

### Critical Rule: Explicit Preedit Clearing Required

ghostty does **not** auto-clear the preedit overlay when committed text is sent via `ghostty_surface_key()`. From `Surface.zig`: "The core surface will NOT reset the preedit state on charCallback or keyCallback."

libitshell3 **must** call `ghostty_surface_preedit(null, 0)` explicitly whenever `preedit_changed = true` and `preedit_text = null`. Failure to do so leaves stale preedit overlay on screen after composition ends.

### Language Switch ghostty Integration

When `setActiveLanguage()` returns committed text (from flushing the preedit), it follows the same `ghostty_surface_key()` path as any other committed text. The only difference: use `key = .unidentified` since there is no originating physical key (the toggle key was consumed by Phase 0).

```zig
fn handleLanguageSwitch(pane: *Pane, new_lang: LanguageId) void {
    const result = pane.ime.setActiveLanguage(new_lang);

    if (result.committed_text) |text| {
        const ghost_key = ghostty_input_key_s{
            .action = .press,
            .mods = .{},
            .consumed_mods = .{},
            .keycode = .unidentified,  // no originating key
            .text = text.ptr,
            .unshifted_codepoint = 0,
            .composing = false,
        };
        ghostty_surface_key(pane.surface, ghost_key);

        // Release event
        const release_key = ghostty_input_key_s{
            .action = .release,
            .mods = .{},
            .consumed_mods = .{},
            .keycode = .unidentified,
            .text = null,
            .unshifted_codepoint = 0,
            .composing = false,
        };
        ghostty_surface_key(pane.surface, release_key);
    }

    if (result.preedit_changed) {
        ghostty_surface_preedit(pane.surface, null, 0); // always clear on switch
    }

    // Update FrameUpdate metadata for language indicator
    pane.ime_mode = @intFromEnum(new_lang);
    pane.markDirty();
}
```

### Critical Rule: NEVER Use `ghostty_surface_text()`

`ghostty_surface_text()` is ghostty's **clipboard paste** API. It wraps text in bracketed paste markers (`\e[200~...\e[201~`) when bracketed paste mode is active. Using it for IME committed text causes the **Korean doubling bug** discovered in the it-shell project:

```
User types: 한글
ghostty_surface_text("한") -> \e[200~한\e[201~
ghostty_surface_text("글") -> \e[200~글\e[201~
Display: 하하한한그구글글  <- DOUBLED
```

All IME output MUST go through `ghostty_surface_key()` with `composing=false` and the text in the `text` field. This path uses the KeyEncoder, which is KKP-aware and never wraps in bracketed paste.

### Two HID Mapping Tables

| Table | Location | Input | Output | Purpose |
|---|---|---|---|---|
| HID -> ASCII | **libitshell3-ime** | `hid_keycode` + `shift` | ASCII char (`'a'`, `'A'`, `'r'`, `'R'`) | Feed `hangul_ic_process()` |
| HID -> platform keycode | **libitshell3** | `hid_keycode` | Platform-native keycode (`uint32_t`) | Feed `ghostty_surface_key()` |

Both are static lookup tables. They don't conflict and shouldn't be merged — they serve different consumers in different libraries.

**Layer 1 (HID -> platform keycode)** is layout-independent: HID `0x04` always maps to the physical A key regardless of QWERTY/Dvorak/Korean. ghostty's `keycodes.entries` table (a comptime array mapping native keycode -> abstract Key) is the reference. libitshell3 builds an equivalent HID -> platform keycode table.

**Layer 2 (HID -> ASCII)** is layout-dependent: HID `0x04` maps to `'a'` in QWERTY but would map differently in other layouts. For Korean 2-set, the ASCII character is what libhangul expects (e.g., `'r'` -> ㄱ, `'k'` -> ㅏ). This matches ibus-hangul and fcitx5-hangul's approach of normalizing to US QWERTY from the hardware keycode.

These layers are orthogonal. Layer 1 replaces ghostty's `embedded.zig:KeyEvent.core()`. Layer 2 replaces ghostty's `UCKeyTranslate` / OS text input path (which we bypass entirely with our native IME).

**Platform keycode note**: The `keycode` field in `ghostty_input_key_s` expects **platform-native keycodes**, not USB HID usage codes:
- **macOS**: Carbon virtual key codes (e.g., `kVK_ANSI_A = 0x00`, `kVK_Return = 0x24`)
- **Linux**: XKB keycodes
- **Windows**: Win32 keycodes

The `mapHidToGhosttyKey()` function produces these platform-native keycodes. The mapping can be derived from ghostty's `keycodes.zig` `raw_entries` table, which contains `{ USB_HID, evdev, xkb, win, mac, W3C_code }` tuples. At compile time, the correct platform column is selected.

> **PoC note**: The PoC (`poc/02-ime-ghostty-real/poc-ghostty-real.m`) uses `ghostty_input_key_e` enum values as keycodes instead of platform-native keycodes. This is a bug masked by two factors: (1) committed text uses `.text` for PTY output, so keycode is irrelevant; (2) forwarded key escape sequence output was not verified in tests. The production implementation MUST use platform-native keycodes. This was identified and documented in the v0.2 review cycle (Resolution 14).

### ghostty Language Awareness

ghostty's Surface has **zero** language-related state. There are no `language`, `locale`, or `ime` fields anywhere in Surface or the renderer. The language indicator shown to the user (e.g., "한" or "A" in the status bar) is purely a metadata field in FrameUpdate (`ime_mode: u8`), managed entirely by libitshell3. ghostty does not need to know or care about the active language.

### Focus Change and Language Preservation

When a pane loses focus (`deactivate`), the engine flushes composition and returns ImeResult. The `active_language` field is **not** changed. When the same pane regains focus (`activate`), it's still in the same language mode (e.g., korean). This is entirely internal to the engine — ghostty's Surface has no concept of IME language.

Users expect that switching panes and coming back preserves their input mode. The engine's `active_language` persists across deactivate/activate cycles.

### Key Encoder Integration

ghostty's key encoder (`key_encode.zig:75`) has a clean, directly callable interface:

```zig
pub fn encode(
    writer: *std.Io.Writer,
    event: key.KeyEvent,
    opts: Options,  // terminal mode state: cursor_keys, kitty_flags, etc.
) !void
```

This function is pure Zig with no Surface/apprt dependency. The daemon can call it directly without going through `ghostty_surface_key()`.

The `forward_key` from libitshell3-ime maps to `key.KeyEvent` as:
```
forward_key.hid_keycode -> key.KeyEvent.key   (via HID-to-platform-key table)
forward_key.modifiers   -> key.KeyEvent.mods
forward_key.shift       -> key.KeyEvent.mods.shift
(no utf8, no composing -- it's a forwarded key, not text)
```

The `Options` (DEC modes, Kitty flags, modifyOtherKeys) come from the daemon's terminal state via libghostty-vt's Terminal.

**Phase 1 approach:** Use `ghostty_surface_key()` (goes through the full Surface/keyCallback path). Simpler integration, proven correct.

**Phase 2+ approach:** Call `key_encode.encode()` directly. Avoids the Surface abstraction, gives full control. Requires the daemon to maintain its own terminal mode state (which it already does via libghostty-vt's Terminal).

### ghostty Event Loop Processing

ghostty requires regular event loop processing via `ghostty_app_tick()` for I/O operations (writing to PTY, reading child process output, updating terminal state). The daemon architecture must ensure `ghostty_app_tick()` is called at appropriate intervals. This is a daemon architecture concern documented here for cross-reference; see the daemon architecture document for the event loop design.

### Known Limitation: Left/Home Arrow Key Crash

Left arrow and Home key trigger a crash in certain libghostty build configurations:

```
invalid enum value in terminal.stream.Stream.nextNonUtf8
```

The crash occurs when ghostty's VT parser processes the shell's escape sequence response to cursor movement. Right arrow works correctly. The IME flush-on-cursor-move logic is verified via Right arrow. This is a libghostty VT parser issue, not an IME issue. Building from latest ghostty source may resolve it.

---

## 6. Memory Ownership

### Rule: Internal Buffers, Invalidated on Next Mutating Call

`ImeResult` fields (`committed_text`, `preedit_text`) are slices pointing into **fixed-size internal buffers** owned by the `HangulImeEngine` instance:

```
committed_buf: [256]u8  -- holds committed UTF-8 text
preedit_buf:   [64]u8   -- holds preedit UTF-8 text
```

**Lifetime**: Slices are valid until the next call to `processKey()`, `flush()`, `reset()`, `deactivate()`, or `setActiveLanguage()` on the **same** engine instance.

**Rationale**: This mirrors libhangul's own memory model — `hangul_ic_get_preedit_string()` returns an internal pointer invalidated by the next `hangul_ic_process()` call. Zero heap allocation per keystroke.

**Buffer sizing**:
- 256 bytes for committed text: a single Korean syllable is 3 bytes UTF-8. The longest possible commit from one keystroke is a flushed syllable + a non-jamo character = ~6 bytes. 256 bytes is vastly oversized for safety.
- 64 bytes for preedit: a single composing syllable is always exactly one character (3 bytes UTF-8). 64 bytes is vastly oversized for safety.

**Caller responsibility**: If the caller needs to retain the text across multiple `processKey()` calls, it must copy the data. In practice, the daemon's Phase 2 (ghostty integration) immediately consumes the text by calling `ghostty_surface_key()` or `ghostty_surface_preedit()`, so no copying is needed.

---

## 7. Future Extensibility

### Candidate Support (Japanese/Chinese)

When Japanese (libkkc/libmozc) or Chinese (librime) engines are added, they need candidate list support. The design principle: **don't add candidate fields to ImeResult**.

**Why not ImeResult?**
- Korean/English (99% of keystrokes for v1) would carry an always-null `candidates` field.
- Candidate events are rare — triggered by explicit user action (Space in Japanese, Hanja key in Korean), not every keystroke.
- Candidate list lifecycle is different from key processing: a list stays visible across multiple keystrokes (arrow navigation, page up/down).

**Solution: Separate callback channel.**

```zig
// Future -- not implemented in v1
pub const CandidateEvent = union(enum) {
    show: CandidateList,    // display candidate panel
    update: CandidateList,  // update visible candidates (page change, cursor move)
    hide: void,             // hide candidate panel
};

pub const CandidateList = struct {
    candidates: []const Candidate,
    selected_index: usize,
    page_start: usize,
    page_size: usize,
};

pub const Candidate = struct {
    text: []const u8,       // UTF-8 candidate text
    comment: ?[]const u8,   // Optional annotation (e.g., reading, meaning)
};
```

The `ImeEngine` VTable would gain an optional callback:

```zig
// Future addition to VTable
setCandidateCallback: ?*const fn (
    ptr: *anyopaque,
    callback: ?*const fn (ctx: *anyopaque, event: CandidateEvent) void,
    ctx: ?*anyopaque,
) void,
```

Korean engine's `setCandidateCallback` implementation: no-op (never emits candidates). Japanese/Chinese engines set the callback and emit `CandidateEvent` when the user invokes candidate selection.

**Impact on v1**: Zero. The VTable field is `null`. No code path touches it.

### Adding a New Language Engine

To add a new language (e.g., Japanese via libkkc):

1. Implement a struct with all `ImeEngine.VTable` functions.
2. Return an `ImeEngine` from a factory function.
3. Add a new `LanguageId` variant (`.japanese`).
4. Register the factory in libitshell3's engine registry (future Phase 7).
5. No changes to `KeyEvent`, `ImeResult`, or the processing pipeline.

---

## 8. C API Boundary

### Decision: libitshell3-ime Has No Public C API

libitshell3-ime is an **internal dependency** of libitshell3. It is statically linked into the libitshell3 library. External consumers interact with the combined library through `itshell3.h` only.

**Rationale:**
- libitshell3-ime is only consumed by libitshell3 (both Zig). No C FFI needed.
- The IME's key types (`KeyEvent`, `ImeResult`) are internal to the daemon. Clients never see them — they send raw HID keycodes over the wire protocol and receive preedit via FrameUpdate.
- Exposing a separate `itshell3_ime.h` would create two public APIs to maintain. YAGNI.

**If a standalone C API is ever needed** (e.g., another project wants to use the Korean IME), it can be added later. The `ImeEngine` vtable maps naturally to a C opaque handle + function pointers:

```c
// Hypothetical future itshell3_ime.h -- NOT for v1
typedef void* itshell3_ime_t;
typedef struct { /* ... */ } itshell3_ime_key_event_s;
typedef struct { /* ... */ } itshell3_ime_result_s;

itshell3_ime_t itshell3_ime_new(const char* layout_id);
void itshell3_ime_free(itshell3_ime_t);
itshell3_ime_result_s itshell3_ime_process_key(itshell3_ime_t, itshell3_ime_key_event_s);
itshell3_ime_result_s itshell3_ime_flush(itshell3_ime_t);
void itshell3_ime_reset(itshell3_ime_t);
```

### What IS Public: itshell3.h

The public C API (`itshell3.h`) exposes preedit through callbacks, not through IME types:

```c
// In itshell3.h -- the preedit callback the host app receives
typedef void (*itshell3_preedit_cb)(
    uint32_t pane_id,
    const char* text,       // UTF-8 preedit text, NULL if cleared
    size_t text_len,
    uint32_t cursor_x,
    uint32_t cursor_y,
    void* userdata
);

// In itshell3.h -- the language change callback
typedef void (*itshell3_language_cb)(
    uint32_t pane_id,
    uint8_t language_id,    // 0=direct, 1=korean
    const char* language_name, // UTF-8, e.g. "한국어 (2-set)"
    void* userdata
);
```

The host app never knows about `ImeEngine`, `KeyEvent`, or `ImeResult`. It sends raw key events via the wire protocol and receives preedit/mode updates via callbacks.

---

## 9. Session Persistence

### What is Saved (Per-Pane)

```json
{
    "ime": {
        "language": "korean",
        "layout_id": "2"
    }
}
```

### What is NOT Saved

- Preedit text (in-progress composition). On restore, all panes start with empty composition. Nobody expects to resume mid-syllable after a daemon restart.
- Engine-internal state (libhangul's jamo stack). Reconstructing this is not feasible and not useful.

### On Restore

Create a new `HangulImeEngine` with the saved `layout_id`, then call `engine.setActiveLanguage(saved_language)`.

---

## 10. Open Questions

1. **Hanja key in Korean**: Korean has an optional Hanja conversion feature (select a Hangul word and convert to Chinese character). This would use the candidate callback (Section 7). Should we plan for this in v1 scope, or defer? (Recommendation: defer.)

2. **Dead keys for European languages**: `direct` mode currently does no composition. European dead key sequences (e.g., `'` + `e` = `é`) require a mini composition engine. Should this be a separate engine implementation or a feature of the direct mode? (Recommendation: separate engine, deferred.)

3. **Multiple simultaneous modes**: Some users want per-pane mode AND a global mode indicator. The current design is per-pane only. Is global mode tracking needed? (Recommendation: per-pane only for v1. Global indicator is a UI concern the app can derive by reading the focused pane's mode.)

4. **macOS client OS IME suppression**: The macOS client must NOT call `interpretKeyEvents` for keyboard input — it sends raw keycodes to the daemon instead. However, `performKeyEquivalent` is still needed for system-level shortcuts (Cmd+Q, Cmd+H) that should bypass our IME. The pattern: check if the key is a system binding -> if yes, let AppKit handle it; if no, send to daemon. NSTextInputClient methods (`setMarkedText`, `insertText`) should still be implemented for clipboard paste, services, and accessibility — but not for keyboard input. (This is a client-app concern, not a library concern, but documenting here for completeness.)

---

## Appendix A: Stale Documentation Notes

The following existing documents contain outdated information that conflicts with this interface contract:

| Document | Issue | Status |
|----------|-------|--------|
| `docs/modules/libitshell3/01-overview/13-render-state-protocol.md` | References NSTextInputContext for server-side preedit (lines 277-284). Should reference libitshell3-ime's `processKey()` flow. | Stale -- needs update |
| `docs/modules/libitshell3/01-overview/09-recommended-architecture.md` | Contains client-driven preedit API (`itshell3_preedit_start/update/end`). With native IME, preedit is server-driven. | Stale -- needs update |
| `docs/modules/libitshell3/01-overview/14-architecture-validation-report.md` | States "~300-400 lines of pure Zig, no external library needed" (line 113). We chose libhangul wrapper instead. | Inconsistent -- note the decision |
| `docs/modules/libitshell3-ime/01-overview/04-architecture.md` | `InputMode` uses `english` (should be `direct`). `flush()` returns `?[]const u8` (should return `ImeResult`). `KeyboardLayout` is an enum (should be string ID). No `ImeEngine` trait. | Superseded by this document |
| `interface-design.md` (deleted) | Was the predecessor document. Section 1.4 Modifier Flush Policy specified RESET (discard) -- incorrect. All unique content merged into this document (v0.2). Deleted. |

## Appendix B: v1 Scope

For Phase 1.5 (native IME), implement only:

- **HangulImeEngine** with dubeolsik ("2") layout.
- **Direct mode** passthrough (HID -> ASCII, no composition).
- **Language toggle** via `setActiveLanguage()` called by libitshell3.
- **No candidate support** (Korean doesn't need it).
- **No separate C API** (internal to libitshell3).
- **No external keyboard XML loading** (libhangul compiled without `ENABLE_EXTERNAL_KEYBOARDS`).
- Additional layouts ("3f", "39", "ro", etc.) deferred to Phase 6 (polish). Adding them is a config change, not an API change -- libhangul supports all 9 internally.

## Appendix C: Changes from v0.1

This section documents all changes made from the v0.1 interface contract based on the team review (principal-architect, ime-expert, ghostty-expert).

### C.1 Vtable Simplification

**Removed methods** (3 methods removed, vtable reduced from 11 to 8):
- `getSupportedLanguages()` -- framework (libitshell3) knows available languages at creation time.
- `setEnabledLanguages()` -- framework manages language rotation list, not the engine.
- Language management renamed: `getMode()`/`setMode()` -> `getActiveLanguage()`/`setActiveLanguage()`.

**Removed types**:
- `LanguageDescriptor` -- libitshell3 hardcodes language metadata (name, is_composing) since it creates the engine.

**Rationale**: In fcitx5 and ibus, language enumeration and enable/disable are framework-level concerns. The engine just processes keys and switches language when told.

### C.2 Modifier Flush Policy Correction

**v0.1**: Ambiguous (interface-design.md said RESET for Ctrl/Alt/Super; v0.1 contract and PoC used FLUSH).

**v0.2**: Explicitly **FLUSH (commit)** for all modifiers. No exceptions.

**Evidence**: Verified in ibus-hangul source (`ibus_hangul_engine_process_key_event()` calls `hangul_ic_flush()` on `IBUS_CONTROL_MASK`) and fcitx5-hangul source (calls `flush()` on modifier detection). Both commit the preedit; neither discards it. The claim in `interface-design.md` that RESET matches ibus-hangul was incorrect.

### C.3 setActiveLanguage Same-Language Semantics

**v0.1**: Not specified.

**v0.2**: Explicitly a **no-op** when called with the already-active language. Returns empty `ImeResult`, no flush.

**Rationale**: Matches fcitx5/ibus behavior. Prevents surprising flush on accidental double-toggle.

### C.4 setActiveLanguage Atomicity

**v0.1**: Implicit.

**v0.2**: Explicitly documented that `setActiveLanguage()` flushes and switches atomically. Callers must NOT call `flush()` then `setActiveLanguage()` separately.

### C.5 libhangul Cleanup Clarification

**v0.1**: Not specified whether `hangul_ic_reset()` is needed after `hangul_ic_flush()`.

**v0.2**: Explicitly documented that `hangul_ic_flush()` alone is sufficient. Verified in libhangul source: `hangul_ic_flush()` calls `hangul_buffer_clear()` which zeroes all jamo fields (`choseong`, `jungseong`, `jongseong = 0`) and clears the stack. `hangul_ic_is_empty()` returns true after flush.

### C.6 ghostty Integration Additions

**Language switch ghostty path**: Added `handleLanguageSwitch()` pseudocode showing `key = .unidentified` for committed text from `setActiveLanguage()`.

**ghostty language awareness**: Explicitly documented that ghostty Surface has zero language-related state. Language indicator is purely FrameUpdate metadata.

**Focus change behavior**: Documented that `active_language` persists across deactivate/activate cycles.

### C.7 forward_key from setActiveLanguage

**v0.1**: Not specified.

**v0.2**: Explicitly always null. Toggle key is consumed by Phase 0. If it leaked through (e.g., Right Alt), ghostty would produce garbage escape sequences.

### C.8 LanguageId Naming

**v0.1**: Used both `InputMode` (in interface-design.md) and `LanguageId` (in v0.1 contract).

**v0.2**: Standardized on `LanguageId` throughout. Methods are `getActiveLanguage()`/`setActiveLanguage()`, not `getMode()`/`setMode()`.

### C.9 ghostty Keycode Space Clarification

**v0.1**: `mapHidToGhosttyKey()` output described as `ghostty_input_key_e` without specifying the keycode space.

**v0.2**: Clarified that `ghostty_input_key_s.keycode` expects **platform-native keycodes** (`uint32_t`), not USB HID usage codes. On macOS these are Carbon virtual key codes, on Linux they are XKB keycodes. The mapping is derivable from ghostty's `keycodes.zig` `raw_entries` table.

### C.10 Explicit Preedit Clearing Requirement

**v0.1**: Preedit clearing shown in example code but not called out as a mandatory requirement.

**v0.2**: Explicitly documented that ghostty does **not** auto-clear preedit state. From `Surface.zig`: "The core surface will NOT reset the preedit state on charCallback or keyCallback." libitshell3 must call `ghostty_surface_preedit(null, 0)` explicitly whenever `preedit_changed = true` and `preedit_text = null`.

## Appendix D: Changes from v0.2

This section documents all changes made from the v0.2 interface contract based on PoC validation (`poc/02-ime-ghostty-real/poc-ghostty-real.m` — 22/24 tests pass, 2 skipped due to libghostty VT parser bug).

### D.1 Space Key Handling (Resolution 12)

**v0.2**: Space not documented in scenario matrix or modifier flush policy table.

**v0.3**: Added Space to both tables. Space during composition flushes (commits preedit), then forwards Space. When forwarding Space via `ghostty_surface_key()`, the key event MUST include `.text = " "` and `.unshifted_codepoint = ' '` because Space is a printable key — ghostty's key encoder needs the text field to produce the space character. Other forwarded special keys (Enter, Escape, arrows) work with `.text = null` because they have dedicated encoding paths.

**Evidence**: PoC Test 7 ("한" + Space + "글") produces correct terminal output with this pattern.

### D.2 Press+Release Pairs Required (Resolution 13)

**v0.2**: `handleKeyEvent` pseudocode showed only press events for `ghostty_surface_key()`.

**v0.3**: Every `ghostty_surface_key()` press event MUST be followed by a corresponding release event with `.action = .release` and `.text = null`. This is required for ghostty's internal key state tracking and forward-compatibility with Kitty keyboard protocol. Legacy mode ignores releases (harmless no-op).

**Evidence**: All 24 PoC tests send press+release pairs and pass.

### D.3 Keycode Criticality by Event Type (Resolution 14)

**v0.2**: Stated that `mapHidToGhosttyKey()` must produce platform-native keycodes (Resolution 10) but did not document criticality differences by event type.

**v0.3**: Added keycode criticality table. For committed text (`.text` set), keycode is non-critical — ghostty uses `.text` for PTY output. For forwarded keys (`.text = null`), keycode is critical — ghostty uses it for escape sequence encoding. Documented that the PoC's use of `ghostty_input_key_e` enum values as keycodes is a masked bug (works for committed text, would fail for forwarded key escape sequences).

### D.4 preedit_changed Optimization Guidance (Resolution 15)

**v0.2**: Defined `preedit_changed: bool` but did not specify whether it's mandatory or an optimization.

**v0.3**: `preedit_changed` is mandatory for the production implementation. Added guidance: engine MUST set it accurately (true on null<->non-null transitions or content changes, false when unchanged). Callers MAY ignore it and call `ghostty_surface_preedit()` unconditionally as a debugging fallback — this is always correct but wasteful.

### D.5 hangul_ic_process() Return-False Handling (Resolution 16)

**v0.2**: Not documented.

**v0.3**: Added "Phase 1: hangul_ic_process() Return-False Handling" subsection to Section 2 and cross-reference in Section 3.7. Documents the algorithm for handling keys rejected by libhangul (punctuation, numbers, etc.): check commit/preedit strings regardless of return value, flush if non-empty, forward rejected key.

### D.6 Direct Mode Scenario Matrix Expansion (Resolution 17)

**v0.2**: Only one row for direct mode: "English 'a' (direct mode)".

**v0.3**: Added 6 direct mode rows: Shift+'a', Enter, Space, Ctrl+C, Arrow, Escape. Documented direct mode branch behavior: printable without modifiers -> committed text; everything else -> forward key. Direct mode never has preedit.

### D.7 ghostty Event Loop Note (Informational)

**v0.2**: Not mentioned.

**v0.3**: Added note in Section 5 that ghostty requires regular `ghostty_app_tick()` calls for I/O processing. Forward reference to daemon architecture document.

### D.8 Left/Home Arrow Key Crash Note (Informational)

**v0.2**: Not mentioned.

**v0.3**: Added known limitation in Section 5 documenting the Left/Home arrow key crash in certain libghostty builds (`invalid enum value in terminal.stream.Stream.nextNonUtf8`). This is a libghostty VT parser issue, not an IME issue. IME flush-on-cursor-move verified via Right arrow.
