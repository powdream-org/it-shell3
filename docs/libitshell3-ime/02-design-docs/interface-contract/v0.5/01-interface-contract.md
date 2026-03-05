# 01 — libitshell3 <-> libitshell3-ime Interface Contract

> **Status**: Draft v0.5 — Review issues 2.1, 2.2, 2.3, 2.5a, 2.5b applied. Issue 2.4 deferred to protocol v0.6 (see `protocol-changes-for-v06.md`).
> **Supersedes**: [v0.4/01-interface-contract.md](../v0.4/01-interface-contract.md), [v0.3/01-interface-contract.md](../v0.3/01-interface-contract.md), [v0.2/01-interface-contract.md](../v0.2/01-interface-contract.md), [v0.1/01-interface-contract.md](../v0.1/01-interface-contract.md)
> **Date**: 2026-03-05
> **Review participants**: protocol-architect, ime-expert, cjk-specialist
> **PoC validation**: `poc/ime-ghostty-real/poc-ghostty-real.m` — 22/24 tests pass (2 skipped due to libghostty VT parser bug, not IME code)
> **Changes from v0.3**: See [Appendix E: Changes from v0.3](#appendix-e-changes-from-v03)
> **Changes from v0.4-pre**: See [Appendix F: Identifier Consensus Changes](#appendix-f-identifier-consensus-changes)
> **Changes from v0.4**: See [Appendix G: Changes from v0.4](#appendix-g-changes-from-v04)

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
6. **Framework owns input method management.** libitshell3 (the framework) decides what input methods are available and which is active. The engine receives `setActiveInputMethod()` calls and processes keys accordingly. (Informed by fcitx5/ibus: language enumeration and toggle logic live in the framework, not in individual engines.)

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
|  - Language switch -> setActiveInputMethod(id)    |
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
3. **Phase 2 (ghostty)**: Committed text "하" is sent to PTY via `ghostty_surface_key`. Then Ctrl+C goes through ghostty's keybinding system. If Ctrl+C is bound to a keybinding, it fires. If not, `ghostty_surface_key` encodes it as `0x03` (ETX).

This ensures the user's in-progress composition is preserved before any keybinding action.

**Verified by PoC** (`poc/ime-key-handling/`): All 10 test scenarios pass — arrows, Ctrl+C, Ctrl+D, Enter, Escape, Tab, backspace jamo-undo, shifted keys, and mixed compose-arrow-compose sequences all work correctly with libhangul.

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

**Verified by PoC** (`poc/ime-ghostty-real/poc-ghostty-real.m` lines 298–324).

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
    /// Valid range: 0x00–HID_KEYCODE_MAX (0xE7).
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

    /// Maximum valid USB HID keycode for the Keyboard/Keypad page (0x07).
    /// The IME engine handles keycodes in the range 0x00–0xE7 only.
    /// The server MUST NOT pass keycodes above HID_KEYCODE_MAX to processKey().
    /// Keycodes above this value bypass the IME engine entirely and are
    /// routed directly to ghostty.
    pub const HID_KEYCODE_MAX: u8 = 0xE7;

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
- **Wire-to-KeyEvent mapping**: The server decomposes the protocol wire modifier bitmask into KeyEvent fields. See protocol doc 04 Section 2.1 for the full mapping table (wire Shift bit -> `KeyEvent.shift`, wire bits 1–3 -> `KeyEvent.modifiers`).
- **CapsLock and NumLock** (wire modifier bits 4–5) are intentionally not consumed by the IME engine. Lock key state does not affect Hangul composition — jamo selection depends solely on the Shift key. CapsLock as a language toggle key is detected in Phase 0 (libitshell3), not by the IME.

### 3.2 ImeResult (Output from IME)

```zig
/// The result of processing a key event through the IME engine.
/// All fields are orthogonal -- any combination is valid.
///
/// Memory: all slices point into internal buffers owned by the ImeEngine
/// instance. They are valid until the next call to processKey(), flush(),
/// reset(), deactivate(), or setActiveInputMethod() on the SAME engine instance.
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

    /// Composition state for protocol metadata (PreeditUpdate messages).
    /// Engine-specific string describing the current composition stage.
    /// null when no composition is active or when the engine does not
    /// track sub-states (e.g., direct mode).
    /// Memory: points to static string literals, valid indefinitely.
    ///
    /// Korean engines use HangulImeEngine.CompositionStates constants.
    /// The server passes this value through to PreeditUpdate JSON without
    /// interpretation.
    composition_state: ?[]const u8 = null,
};
```

**Scenario matrix:**

| Situation | committed_text | preedit_text | forward_key | preedit_changed | composition_state |
|-----------|----------------|--------------|-------------|-----------------|-------------------|
| English 'a' (direct mode) | `"a"` | null | null | false | null |
| English Shift+'a' (direct mode) | `"A"` | null | null | false | null |
| Direct mode Enter | null | null | Enter key | false | null |
| Direct mode Space | null | null | Space key | false | null |
| Direct mode Ctrl+C | null | null | Ctrl+C key | false | null |
| Direct mode Arrow | null | null | Arrow key | false | null |
| Direct mode Escape | null | null | Escape key | false | null |
| Korean ㄱ (start composing) | null | `"ㄱ"` | null | true | `"ko_leading_jamo"` |
| Korean 가 (add vowel) | null | `"가"` | null | true | `"ko_syllable_no_tail"` |
| Korean 한 (add tail consonant) | null | `"한"` | null | true | `"ko_syllable_with_tail"` |
| Korean 없 (double tail ㅂㅅ) | null | `"없"` | null | true | `"ko_double_tail"` |
| Korean 간 -> new ㄱ (syllable break) | `"간"` | `"ㄱ"` | null | true | `"ko_leading_jamo"` |
| Arrow during composition | `"한"` (flush) | null | arrow key | true | null |
| Ctrl+C during composition | `"하"` (flush) | null | Ctrl+C key | true | null |
| Enter during composition | `"ㅎ"` (flush) | null | Enter key | true | null |
| Escape during composition | `"한"` (flush) | null | Escape key | true | null |
| Tab during composition | `"한"` (flush) | null | Tab key | true | null |
| Space during composition | `"한"` (flush) | null | Space key | true | null |
| Backspace removes tail (한→하) | null | `"하"` (undo) | null | true | `"ko_syllable_no_tail"` |
| Backspace empty composition | null | null | Backspace | false | null |
| Space with empty composition | null | null | Space key | false | null |
| English Ctrl+C (no composition) | null | null | Ctrl+C key | false | null |
| Input method switch (korean_2set->direct) | `"한"` (flush) | null | null | true | null |
| Release event | null | null | null | false | null |

**Direct mode behavior**: In direct mode, `processKey()` performs a simple branch:
- Printable key without modifiers -> HID-to-ASCII lookup -> `committed_text = ascii_char`, no forward. **Exception: Space is always forwarded** (consistent across all modes — see Section 3.3).
- Everything else (non-printable, modified, unmapped) -> `forward_key = original_key`, no committed text.
- Direct mode never has preedit (no composition), so `preedit_changed` is always false and `composition_state` is always null.

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
| Shift+key | **No flush** (jamo selection) | Shift selects jamo variants (ㄱ->ㄲ), not a composition-breaking modifier |
| Backspace | **IME handles** | `hangul_ic_backspace()` undoes last jamo; if empty, forward |

**Example -- Ctrl+C during preedit "하":**
```
ImeResult{ .committed_text = "하", .preedit_text = null,
           .forward_key = Ctrl+C, .preedit_changed = true }
```
The committed text "하" is written to PTY first, then Ctrl+C sends SIGINT. The user's in-progress text is preserved.

**Verification**: This matches the actual behavior of both **ibus-hangul** (`ibus_hangul_engine_process_key_event()` calls `hangul_ic_flush()` on `IBUS_CONTROL_MASK | IBUS_MOD1_MASK`) and **fcitx5-hangul** (`HangulState::keyEvent()` calls `flush()` on modifier detection). Both commit the preedit -- neither discards it.

> **Note**: The `interface-design.md` (Section 1.4) previously specified RESET (discard) for Ctrl/Alt/Super modifiers. That was incorrect -- it claimed to match ibus-hangul but ibus-hangul actually flushes (commits). This contract corrects that error.

### 3.4 Input Method Identifiers

The canonical representation for input method identification is a **single string** (`input_method: []const u8`). This is the ONLY representation that crosses any component boundary — protocol wire, IME contract API, session persistence, configuration.

**Naming convention**: `{language}_{human_readable_variant}`. The language prefix identifies which composition pipeline to use. The suffix is a human-readable layout/variant name, not an engine-native ID.

- `"direct"` — special case, no language prefix. Direct passthrough, no composition. Used for English, Latin scripts, and any non-composing layout.
- `"korean_*"` — Korean Hangul composition via libhangul. Jamo are assembled into syllables algorithmically.
- Future: `"japanese_*"` (kana composition + kanji candidate selection), `"chinese_*"` (pinyin/wubi/zhuyin composition + hanzi candidate selection).

**Input method management protocol (simplified from v0.1):**

libitshell3 owns input method selection. The interaction is:

1. **At startup**: libitshell3 creates the engine knowing what input methods it supports (hardcoded for v1: `"direct"` + `"korean_2set"`). No runtime discovery needed.
2. **Input method switch**: When the user presses the toggle key (detected by libitshell3), libitshell3 calls `setActiveInputMethod(input_method)`. The IME atomically flushes any pending composition and switches.
3. **Synchronization**: libitshell3 can call `getActiveInputMethod()` at any time to query the current state (e.g., after session restore).

**Removed from v0.1**: `getSupportedLanguages()`, `setEnabledLanguages()`, and `LanguageDescriptor` are removed. In fcitx5 and ibus, language enumeration and enable/disable are framework-level concerns, not engine concerns. libitshell3 is the framework -- it knows what input methods are available because it created the engine.

**Removed from v0.4-pre**: `LanguageId` enum is removed from the public API. The engine uses input method strings directly. Composing-capable check is trivially `!std.mem.eql(u8, input_method, "direct")`. The `isEmpty()` method provides the runtime check for whether composition is actually in progress.

> **Orthogonal axis: `keyboard_layout`**: Physical keyboard layout (QWERTY/AZERTY/QWERTZ) is a separate per-pane field, orthogonal to `input_method`. Korean input methods always use QWERTY-normalized input regardless of physical keyboard. The `keyboard_layout` field persists across input method switches. See protocol doc 05, Section 4.1 for details.

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
        /// Active input method is preserved across
        /// deactivate/activate cycles -- NOT reset to direct.
        activate: *const fn (ptr: *anyopaque) void,

        /// Pane lost focus. Engine should flush pending composition.
        /// (Commit the in-progress syllable so it's not lost.)
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
| `activate` | Pane gained focus | void |
| `deactivate` | Pane lost focus (flushes) | ImeResult |
| `getActiveInputMethod` | Query current input method | `[]const u8` |
| `setActiveInputMethod` | Switch input method (flushes atomically) | `error{UnsupportedInputMethod}!ImeResult` |

**Why vtable over comptime generics:**
- Comptime generics (`fn Pane(comptime Ime: type) type`) would monomorphize all Pane code per IME type, inflating binary size when multiple engines exist.
- vtable is a single pointer indirection — negligible cost at the call rates we see (< 100 calls/second for human typing).
- vtable works with C FFI (comptime generics don't export to C).

### 3.6 setActiveInputMethod Behavior

`setActiveInputMethod()` is the only input-method-switching method. It handles both language switches (e.g., `"korean_2set"` -> `"direct"`) and layout switches (e.g., `"korean_2set"` -> `"korean_3set_final"`) uniformly. Its behavior depends on whether the requested input method differs from the current one:

**Case 1: Switching to a different input method (e.g., `"korean_2set"` -> `"direct"`):**

1. Call `hangul_ic_flush()` internally to commit any in-progress composition.
2. Read the flushed string from libhangul.
3. Set `active_input_method = new_method`.
4. Update internal engine mode and libhangul keyboard if needed.
5. Return `ImeResult{ .committed_text = flushed_text, .preedit_text = null, .forward_key = null, .preedit_changed = true, .composition_state = null }`.

**Case 2: "Switching" to the already-active input method (e.g., `"korean_2set"` -> `"korean_2set"`):**

Return `ImeResult{}` (all null/false). No flush, no state change.

**Case 3: Unsupported input method string:**

Return `error.UnsupportedInputMethod`. The server MUST only send input method strings from the canonical registry (Section 3.7). Receiving an unrecognized string is a server bug.

**Rationale for no-op on same-method**: The user toggled to the same mode by mistake (or the framework called it redundantly). Flushing would be a surprising side effect — the user didn't intend to commit their in-progress composition. This matches fcitx5 (`InputMethodManager::setCurrentGroup()`) and ibus (`ibus_bus_set_global_engine()`), both of which treat same-engine switches as no-ops.

**Atomicity**: `setActiveInputMethod()` flushes and switches in a single call. The caller must NOT call `flush()` then `setActiveInputMethod()` separately — a key event arriving between those two calls could be processed in the wrong input method.

**forward_key is always null**: `setActiveInputMethod()` is called from Phase 0 in response to a toggle key that has already been consumed. There is no key to forward. If a toggle key (e.g., Right Alt) leaked through to ghostty, it would produce garbage escape sequences (`\e` prefix for Alt).

**libhangul cleanup**: `hangul_ic_flush()` alone is sufficient — no need to call `hangul_ic_reset()` after flush. Verified in libhangul source: `hangul_ic_flush()` calls `hangul_buffer_clear()` which zeroes all jamo fields (`choseong`, `jungseong`, `jongseong`) and clears the stack. After flush, `hangul_ic_is_empty()` returns true.

**String parameter ownership**: The `method` parameter is borrowed for the duration of the call. The engine copies the string into its own storage (or references a static string) — the caller does not need to keep the pointer alive after the call returns.

> **Discard-and-switch pattern**: `reset()` followed by `setActiveInputMethod()` is safe for discard-and-switch when the caller holds the per-pane lock. After `reset()`, the engine is empty and `setActiveInputMethod()` performs a no-flush switch. This pattern implements the protocol's `commit_current=false` on InputMethodSwitch.

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

The implementation must handle the case where `hangul_ic_process()` returns `false` (key rejected by libhangul). See [Section 2: Phase 1 hangul_ic_process() Return-False Handling](#phase-1-hangul_ic_process-return-false-handling) for the full algorithm.

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

`ko_vowel_only` is produced when a vowel is entered without a preceding consonant. This occurs naturally in 3-set (Sebeolsik) layouts where consonant and vowel keys are physically separated. In 2-set (Dubeolsik), libhangul inserts an implicit ㅇ leading consonant, producing `ko_syllable_no_tail` instead. The scenario matrix in [Section 3.2](#32-imeresult-output-from-ime) illustrates 2-set behavior (v1 default) and is not exhaustive of all reachable states.

**Session persistence**: `active_input_method` (string) is the only field that must be saved per pane for session persistence. On session restore, the server creates a new `HangulImeEngine` with the saved `input_method` string. Composition state is never persisted — it is flushed on pane deactivation before the session is saved.

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
| Active input method switching | **libitshell3** | Calls `setActiveInputMethod(input_method)` when user toggles. |
| Flushing on input method switch | **libitshell3-ime** | `setActiveInputMethod()` flushes pending composition internally (atomically). |
| Keybinding interception (Cmd+V, Cmd+C) | **libitshell3 via ghostty** | Keybindings run in Phase 2, after IME has flushed. |
| Calling `ghostty_surface_key()` | **libitshell3** | Daemon translates ImeResult into ghostty API calls. |
| Calling `ghostty_surface_preedit()` | **libitshell3** | Daemon forwards preedit to ghostty's renderer overlay. |
| Terminal escape sequence encoding | **ghostty** (via `ghostty_surface_key`) | ghostty's KeyEncoder runs daemon-side. We do NOT write our own encoder. |
| PTY writes | **ghostty** (internal to `ghostty_surface_key`) | ghostty handles PTY I/O internally after encoding. |
| Sending preedit/render state to remote client | **libitshell3** (protocol layer) | Part of the FrameUpdate protocol. |
| Rendering preedit overlay on screen | **it-shell3 app** (client) | Client receives preedit from server, renders via Metal. |
| Per-pane ImeEngine lifecycle | **libitshell3** | Creates/destroys engine per pane. Calls activate/deactivate on focus change. |
| Language indicator in FrameUpdate | **libitshell3** | Metadata field derived from `active_input_method` string (e.g., `"direct"` vs `"korean_2set"`). ghostty has no language state. See protocol doc 05 for wire encoding. |
| Composing-capable check | **libitshell3** | Derives from input method string: `"direct" = no`, anything else = yes. Runtime check: `engine.isEmpty()`. No `LanguageDescriptor` needed. |
| `display_width` / UAX #11 character width computation | **libitshell3** | East Asian Width property lookup (narrow/wide/ambiguous) for CellData encoding. IME engine has no knowledge of display width — it only deals with key events and composition text. |

### What libitshell3-ime Does NOT Do

- Does NOT know about PTYs, sockets, sessions, panes, or protocols.
- Does NOT encode terminal escape sequences (no VT knowledge).
- Does NOT detect language toggle keys (that's libitshell3's keybinding concern).
- Does NOT decide when to switch input methods (libitshell3 calls `setActiveInputMethod()`).
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

### Input Method Switch ghostty Integration

When `setActiveInputMethod()` returns committed text (from flushing the preedit), it follows the same `ghostty_surface_key()` path as any other committed text. The only difference: use `key = .unidentified` since there is no originating physical key (the toggle key was consumed by Phase 0).

```zig
fn handleInputMethodSwitch(pane: *Pane, new_method: []const u8) void {
    const result = pane.ime.setActiveInputMethod(new_method) catch |err| switch (err) {
        error.UnsupportedInputMethod => {
            log.err("unsupported input method: {s}", .{new_method});
            return;
        },
    };

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

    // Update FrameUpdate metadata for input method indicator
    pane.active_input_method = new_method;
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

> **PoC note**: The PoC (`poc/ime-ghostty-real/poc-ghostty-real.m`) uses `ghostty_input_key_e` enum values as keycodes instead of platform-native keycodes. This is a bug masked by two factors: (1) committed text uses `.text` for PTY output, so keycode is irrelevant; (2) forwarded key escape sequence output was not verified in tests. The production implementation MUST use platform-native keycodes. See [review-resolutions.md Resolution 14](../review-resolutions.md#resolution-14-keycode-criticality--platform-native-confirmed-poc-bug-documented) for the full analysis.

### ghostty Language Awareness

ghostty's Surface has **zero** language-related state. There are no `language`, `locale`, or `ime` fields anywhere in Surface or the renderer. The language indicator shown to the user (e.g., "한" or "A" in the status bar) is derived by libitshell3 from the engine's `active_input_method` string and sent as metadata in FrameUpdate. ghostty does not need to know or care about the active input method.

### Focus Change and Language Preservation

When a pane loses focus (`deactivate`), the engine flushes composition and returns ImeResult. The `active_input_method` field is **not** changed. When the same pane regains focus (`activate`), it's still in the same input method (e.g., `"korean_2set"`). This is entirely internal to the engine — ghostty's Surface has no concept of IME state.

Users expect that switching panes and coming back preserves their input mode. The engine's `active_input_method` persists across deactivate/activate cycles.

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

**Lifetime**: Slices are valid until the next call to `processKey()`, `flush()`, `reset()`, `deactivate()`, or `setActiveInputMethod()` on the **same** engine instance.

**Rationale**: This mirrors libhangul's own memory model — `hangul_ic_get_preedit_string()` returns an internal pointer invalidated by the next `hangul_ic_process()` call. Zero heap allocation per keystroke.

**Buffer sizing**:
- 256 bytes for committed text: a single Korean syllable is 3 bytes UTF-8. The longest possible commit from one keystroke is a flushed syllable + a non-jamo character = ~6 bytes. 256 bytes is vastly oversized for safety.
- 64 bytes for preedit: a single composing syllable is always exactly one character (3 bytes UTF-8). 64 bytes is vastly oversized for safety.

**`composition_state` memory**: Points to static string literals (see `HangulImeEngine.CompositionStates`). Valid indefinitely — not invalidated by any method call.

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
3. Add canonical input method strings to the registry (e.g., `"japanese_romaji"`, `"japanese_kana"`).
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

itshell3_ime_t itshell3_ime_new(const char* input_method);
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

// In itshell3.h -- the input method change callback
typedef void (*itshell3_input_method_cb)(
    uint32_t pane_id,
    const char* input_method,  // canonical string, e.g. "korean_2set", "direct"
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
        "input_method": "korean_2set"
    }
}
```

A single field. No reverse-mapping needed — the canonical protocol string is stored directly.

### What is NOT Saved

- Preedit text (in-progress composition). On restore, all panes start with empty composition. Nobody expects to resume mid-syllable after a daemon restart.
- Engine-internal state (libhangul's jamo stack). Reconstructing this is not feasible and not useful.

### On Restore

Create a new `HangulImeEngine` with the saved `input_method` string: `HangulImeEngine.init(allocator, saved_input_method)`.

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
| `docs/libitshell3/01-overview/13-render-state-protocol.md` | References NSTextInputContext for server-side preedit (lines 277-284). Should reference libitshell3-ime's `processKey()` flow. | Stale -- needs update |
| `docs/libitshell3/01-overview/09-recommended-architecture.md` | Contains client-driven preedit API (`itshell3_preedit_start/update/end`). With native IME, preedit is server-driven. | Stale -- needs update |
| `docs/libitshell3/01-overview/14-architecture-validation-report.md` | States "~300-400 lines of pure Zig, no external library needed" (line 113). We chose libhangul wrapper instead. | Inconsistent -- note the decision |
| `docs/libitshell3-ime/01-overview/04-architecture.md` | `InputMode` uses `english` (should be `direct`). `flush()` returns `?[]const u8` (should return `ImeResult`). `KeyboardLayout` is an enum (should be string ID). No `ImeEngine` trait. | Superseded by this document |
| `interface-design.md` (deleted) | Was the predecessor document. Section 1.4 Modifier Flush Policy specified RESET (discard) -- incorrect. All unique content merged into this document (v0.2). Deleted. |

## Appendix B: v1 Scope

For Phase 1.5 (native IME), implement only:

- **HangulImeEngine** with dubeolsik (`"korean_2set"`) as default.
- **Direct mode** passthrough (`"direct"`, HID -> ASCII, no composition).
- **Input method toggle** via `setActiveInputMethod()` called by libitshell3.
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
- Language management renamed: `getMode()`/`setMode()` -> `getActiveLanguage()`/`setActiveLanguage()` (later renamed to `getActiveInputMethod()`/`setActiveInputMethod()` — see Appendix F).

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

**Language switch ghostty path**: Added `handleLanguageSwitch()` pseudocode showing `key = .unidentified` for committed text from `setActiveLanguage()`. (Later renamed to `handleInputMethodSwitch()` and `setActiveInputMethod()` — see [Appendix F](#appendix-f-identifier-consensus-changes).)

**ghostty language awareness**: Explicitly documented that ghostty Surface has zero language-related state. Language indicator is purely FrameUpdate metadata.

**Focus change behavior**: Documented that `active_language` persists across deactivate/activate cycles. (Later renamed to `active_input_method` — see [Appendix F](#appendix-f-identifier-consensus-changes).)

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

This section documents all changes made from the v0.2 interface contract based on PoC validation (`poc/ime-ghostty-real/poc-ghostty-real.m` — 22/24 tests pass, 2 skipped due to libghostty VT parser bug).

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

## Appendix E: Changes from v0.3

This section documents all changes made from the v0.3 interface contract based on cross-document consistency review between Protocol v0.4 and IME Contract v0.3. Review participants: protocol-architect, ime-expert, cjk-specialist.

Review artifacts:
- `docs/libitshell3-ime/02-design-docs/interface-contract/v0.3/review-notes-cross-review.md`
- `docs/libitshell3/02-design-docs/server-client-protocols/v0.4/review-notes-cross-review-ime.md`

### E.1 HID_KEYCODE_MAX Constant (Issue 1)

**v0.3**: No explicit boundary constant for valid HID keycodes.

**v0.4**: Added `pub const HID_KEYCODE_MAX: u8 = 0xE7` to Section 3.1 (KeyEvent). Added inline doc comment on `hid_keycode` field noting the valid range `0x00–HID_KEYCODE_MAX`. Added server validation note in the constant's doc comment: "The server MUST NOT pass keycodes above HID_KEYCODE_MAX to processKey(). Keycodes above this value bypass the IME engine entirely and are routed directly to ghostty."

**Rationale**: The IME engine handles only USB HID Keyboard/Keypad page (0x07), which is bounded at 0xE7. Documenting this boundary as a named constant clarifies the contract. The wire protocol carries u16 keycodes to support future HID pages; narrowing to u8 at the IME boundary is correct practice for a domain that is provably bounded.

### E.2 Wire-to-KeyEvent Mapping Cross-Reference (Issue 2)

**v0.3**: No cross-reference to the server's wire-to-KeyEvent decomposition.

**v0.4**: Added design note in Section 3.1: "Wire-to-KeyEvent mapping: The server decomposes the protocol wire modifier bitmask into KeyEvent fields. See protocol doc 04 Section 2.1 for the full mapping table (wire Shift bit -> `KeyEvent.shift`, wire bits 1–3 -> `KeyEvent.modifiers`)."

**Rationale**: The IME contract's separation of `shift: bool` from `Modifiers` is only meaningful if the server correctly decomposes the wire bitmask. Cross-referencing the protocol makes this decomposition explicit.

### E.3 CapsLock/NumLock Intentional Omission (Issue 3)

**v0.3**: No explanation for why CapsLock/NumLock state is not in the KeyEvent.

**v0.4**: Added design note in Section 3.1: "CapsLock and NumLock (wire modifier bits 4–5) are intentionally not consumed by the IME engine. Lock key state does not affect Hangul composition — jamo selection depends solely on the Shift key. CapsLock as a language toggle key is detected in Phase 0 (libitshell3), not by the IME."

**Rationale**: Prevents future implementors from wondering whether CapsLock/NumLock should be added. Matches ibus-hangul and fcitx5-hangul, neither of which consumes these lock states.

### E.4 composition_state Field Added to ImeResult (Issue 5)

**v0.3**: ImeResult had no `composition_state` field.

**v0.4**: Added `composition_state: ?[]const u8 = null` field to ImeResult (Section 3.2) with doc comment explaining: engine-specific string, null when no composition active or direct mode, points to static string literals (valid indefinitely), server passes through to PreeditUpdate JSON without interpretation.

**Rationale**: The IME engine internally knows the Hangul composition stage. Forcing the server to reverse-engineer this from NFC decomposition of the preedit string is redundant and error-prone. The field uses `?[]const u8` (nullable string) rather than a typed enum to satisfy Design Principle #1 ("Single interface for all languages") — Korean-specific composition stages cannot be shared with future Japanese/Chinese engines.

### E.5 Scenario Matrix Updated with composition_state (Issue 5)

**v0.3**: Scenario matrix had 4 columns.

**v0.4**: Added `composition_state` column to the scenario matrix in Section 3.2 with appropriate values for each row. Korean composition scenarios show `"ko_leading_jamo"`, `"ko_syllable_no_tail"`, etc. All flush/direct/release rows show null.

### E.6 LanguageId Protocol String Mapping Cross-Reference (Issue 10)

**v0.3**: No documentation of the relationship between LanguageId enum values and protocol string identifiers.

**v0.4 (cross-review)**: Added a note in Section 3.4 (LanguageId): "Protocol string identifiers encode both language and keyboard layout (e.g., `"korean_2set"`). The server maps these to `LanguageId` (language) + `layout_id` (keyboard variant). For example, `"korean_2set"` maps to `LanguageId.korean` + `layout_id = "2"`. See protocol doc 04, Section 2.1 for the full identifier table."

**Superseded by Appendix F**: The identifier consensus removed `LanguageId` and `layout_id` entirely. Section 3.4 was rewritten to "Input Method Identifiers" with a single canonical string model. See [F.1](#f1-languageid-enum-removed-from-public-api) and [F.2](#f2-layout_id-removed-from-public-api).

**Rationale**: Originally documented the separation of concerns between `LanguageId` enum and protocol strings. The identifier consensus eliminated this separation entirely — the protocol string flows directly to the engine.

### E.7 reset()+setActiveLanguage() Discard-and-Switch Pattern (Issue 8)

**v0.3**: Section 3.6 only described the normal language-switch (commit) path.

**v0.4 (cross-review)**: Added note in Section 3.6: "`reset()` followed by `setActiveLanguage()` is safe for discard-and-switch when the caller holds the per-pane lock. After `reset()`, the engine is empty and `setActiveLanguage()` performs a no-flush language switch. This pattern implements the protocol's `commit_current=false` on InputMethodSwitch."

**Superseded by Appendix F**: `setActiveLanguage()` was renamed to `setActiveInputMethod()`. The discard-and-switch pattern remains valid with the new method name. See [F.3](#f3-vtable-methods-renamed).

**Rationale**: The protocol supports `commit_current=false` for InputMethodSwitch. No new IME method is needed — the server orchestrates cancel via `reset()` + `setActiveInputMethod()` under per-pane lock.

### E.8 CompositionStates String Constants Added to HangulImeEngine (Issue 5)

**v0.3**: HangulImeEngine had no composition state constants.

**v0.4**: Added `CompositionStates` nested struct to Section 3.7 with six string constants: `empty`, `ko_leading_jamo`, `ko_vowel_only`, `ko_syllable_no_tail`, `ko_syllable_with_tail`, `ko_double_tail`. Added naming convention note explaining the `ko_` prefix requirement for language-specific constants, and the rationale for `empty` being language-agnostic. (Note: `empty` was subsequently removed in v0.5 — see [G.3](#g3-compositionstatesempty-removed-issue-25b).)

**Rationale**: Provides canonical string values for `ImeResult.composition_state`. The `ko_` prefix prevents collision when future Japanese/Chinese engines define their own state strings.

### E.9 Session Persistence Fields Note (RestoreSession gap)

**v0.3**: Section 3.7 defined `active_language` and `layout_id` fields but did not explicitly connect them to session persistence requirements.

**v0.4 (cross-review)**: Added persistence note in Section 3.7: "Session persistence fields: `active_language` (LanguageId) and `layout_id` (string) are the fields that must be saved per pane for session persistence. On session restore, the server creates a new `HangulImeEngine` with the saved `layout_id` and calls `setActiveLanguage(saved_language_id)`. Composition state is never persisted — it is flushed on pane deactivation before the session is saved."

**Superseded by Appendix F**: Session persistence simplified to a single `input_method` field (e.g., `"korean_2set"`). No separate `active_language` or `layout_id`. See [F.5](#f5-session-persistence-simplified).

Also added `composition_state` memory model clarification to Section 6 (Memory Ownership): "Points to static string literals. Valid indefinitely — not invalidated by any method call." (This part remains valid.)

**Rationale**: Closes the RestoreSession IME initialization gap identified in cross-review. The identifier consensus further simplified the persistence model.

## Appendix F: Identifier Consensus Changes

This section documents all changes made to the v0.4 interface contract based on the three-way identifier design consensus (protocol-architect, ime-expert, cjk-specialist). The consensus resolved the inconsistency between the protocol's single-string identifiers and the IME contract's `LanguageId` enum + `layout_id` pair.

### F.1 LanguageId Enum Removed from Public API

**v0.4-pre**: `LanguageId` was a public `enum(u8)` type with `direct = 0`, `korean = 1`. Used in `getActiveLanguage()` return type and `setActiveLanguage()` parameter type.

**v0.4**: `LanguageId` removed from the public API entirely. Replaced by `input_method: []const u8` — a single canonical string (e.g., `"direct"`, `"korean_2set"`). Section 3.4 rewritten from "LanguageId" to "Input Method Identifiers".

**Rationale**: The `(LanguageId, layout_id)` pair required a server-side mapping table between protocol strings and IME types. This table produced the `"korean_3set_390" -> "3f"` bug (should be `"39"`). A single string flowing from protocol to IME eliminates the mapping table and this bug class. The engine internally derives a private `EngineMode` enum for hot-path dispatch.

### F.2 layout_id Removed from Public API

**v0.4-pre**: `HangulImeEngine` had a `layout_id: []const u8` field storing the libhangul keyboard ID (e.g., `"2"`). Constructor took `layout_id` as parameter.

**v0.4**: Replaced by `active_input_method: []const u8` storing the canonical protocol string (e.g., `"korean_2set"`). Constructor takes `input_method` as parameter. The engine maps the protocol string to a libhangul keyboard ID internally via `libhangulKeyboardId()`.

**Rationale**: The engine is the only consumer of libhangul keyboard IDs (information expert principle). The mapping lives in exactly one place — the engine constructor — and is unit-testable in isolation.

### F.3 Vtable Methods Renamed

**v0.4-pre**: `getActiveLanguage() -> LanguageId`, `setActiveLanguage(LanguageId) -> ImeResult`.

**v0.4**: `getActiveInputMethod() -> []const u8`, `setActiveInputMethod([]const u8) -> error{UnsupportedInputMethod}!ImeResult`.

**Rationale**: Aligns method names with the protocol field name `active_input_method`. One vocabulary across the entire stack. Error union added because the engine must validate input method strings — receiving an unsupported string is a server bug that should be surfaced explicitly.

### F.4 Canonical Input Method Registry Added

**v0.4-pre**: No canonical list of valid input method strings. Protocol doc 05 Section 4.3 had a mapping table (with the 3f/39 bug).

**v0.4**: Added canonical input method registry table to Section 3.7 with all 9 libhangul keyboard IDs correctly mapped. This is the single source of truth — protocol docs reference it via cross-reference, never duplicate it.

**Rationale**: Eliminates the cross-component mapping table that caused the 3f/39 bug. The registry is owned by the IME contract (the IME implementor knows libhangul's keyboard IDs).

### F.5 Session Persistence Simplified

**v0.4-pre**: Two fields persisted per pane: `active_language` (LanguageId) + `layout_id` (string).

**v0.4**: Single field: `input_method` (string, e.g., `"korean_2set"`). No reverse-mapping needed on restore.

### F.6 setActiveInputMethod String Parameter Ownership

**v0.4-pre**: Not applicable (parameter was `LanguageId` enum, a value type).

**v0.4**: Added string parameter ownership note in Section 3.6: the `method` parameter is borrowed for the duration of the call. The engine copies the string into its own storage. The caller does not need to keep the pointer alive after the call returns.

### F.7 Naming Convention Established

**Consensus**: Input method identifiers use `{language}_{human_readable_variant}` format. The language prefix serves as a namespace. `"direct"` is a special case with no prefix.

The `ko_` prefix is reserved for composition state constants (`"ko_leading_jamo"`, etc.), which are engine-internal runtime state. Input method identifiers use the full `"korean_"` prefix because they are user-facing configuration values.

**Rationale**: Human-readable names are self-documenting in protocol traces and debug logs. Engine-native IDs (like libhangul's `"2"`, `"3f"`) are implementation details that should not leak into the protocol. The Ahnmatae layout (libhangul ID `"ahn"`) demonstrated that engine-native IDs cannot be reliably extracted from protocol strings via simple string slicing.

---

## Appendix G: Changes from v0.4

### G.1 Memory Invalidation List Expanded (Issue 2.2)

**v0.4**: `ImeResult` doc comment stated slices are valid until the next call to `processKey()`, `flush()`, `reset()`, or `setActiveInputMethod()`.

**v0.5**: Added `deactivate()` to the invalidation list. `deactivate()` may flush and reset internal buffers, invalidating any previously returned slices.

### G.2 Composition State Prefix Convention Formalized (Issue 2.1)

**v0.4**: Naming convention note in Section 3.7 stated only that language-specific constants use a language prefix (`ko_`, `ja_`, `zh_`), and that `empty` is the sole language-agnostic constant.

**v0.5**: Replaced with a normative rule specifying the prefix granularity: when a language has exactly one composition state graph shared by all input method variants, use ISO 639-1 prefix (`ko_`, `ja_`); when a language has multiple input methods with distinct state graphs, use `{iso639}_{method}_` prefix (`zh_pinyin_`, `zh_bopomofo_`, `zh_cangjie_`). Added a concrete application table. Added normative note that when the same input method supports multiple character sets (e.g., Pinyin for Traditional and Simplified Chinese), the prefix reflects the state graph, not the character set — character set selection is a configuration parameter distinguished by the `input_method` identifier (e.g., `"chinese_pinyin_traditional"` vs `"chinese_pinyin_simplified"`), not by the composition state prefix.

### G.3 `CompositionStates.empty` Removed (Issue 2.5b)

**v0.4**: `CompositionStates` struct contained `pub const empty = "empty";` as a language-agnostic constant for the no-composition state.

**v0.5**: `empty` constant removed. `ImeResult.composition_state = null` is the canonical representation for no active composition. Using a string `"empty"` was redundant with the existing `null` semantics already defined by the `?[]const u8` type. Added normative note after the `CompositionStates` struct.

### G.4 `ko_vowel_only` Reachability Documented (Issue 2.5a)

**v0.4**: `ko_vowel_only` was listed in `CompositionStates` without explanation of when it is reachable in practice.

**v0.5**: Added reachability note: `ko_vowel_only` occurs in 3-set (Sebeolsik) layouts where consonant and vowel keys are physically separated. In 2-set (Dubeolsik), libhangul inserts an implicit ㅇ leading consonant, producing `ko_syllable_no_tail` instead. The scenario matrix illustrates 2-set behavior (v1 default) and is not exhaustive.

### G.5 Appendix E.9 Link Fixed (Issue 2.3)

**v0.4**: Appendix E.9 contained a broken link `[F.6](#f6-session-persistence-simplified)` pointing to a non-existent anchor.

**v0.5**: Corrected to `[F.5](#f5-session-persistence-simplified)`, which is the correct anchor for the "Session Persistence Simplified" entry in Appendix F.

### G.6 Section 3.7 Anchor Fix (Verification V-1)

**v0.4**: The `ko_vowel_only` reachability note in Section 3.7 contained a broken anchor `#32-imeresult-orthogonality-scenario-matrix`.

**v0.5**: Corrected to `#32-imeresult-output-from-ime`, which matches the actual heading of Section 3.2.
