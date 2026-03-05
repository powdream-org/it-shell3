# IME Interface Contract v0.6 — Types

> **Version**: v0.6
> **Date**: 2026-03-05
> **Part of the IME Interface Contract v0.6. See [01-overview.md](01-overview.md) for the document index.**

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
    /// always correct but wasteful — see [Section 5](04-ghostty-integration.md#5-ghostty-integration) for details.
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

> **Orthogonal axis: `keyboard_layout`**: Physical keyboard layout (QWERTY/AZERTY/QWERTZ) is a separate per-session field, orthogonal to `input_method`. Korean input methods always use QWERTY-normalized input regardless of physical keyboard. The `keyboard_layout` field persists across input method switches. See protocol doc 05, Section 4.1 for details.
