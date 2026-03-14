# IME Interface Contract — Types

## 1. KeyEvent (Input to IME)

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

    /// Returns true if this key position produces a printable character
    /// (letter, digit, or punctuation) on a US ANSI keyboard.
    /// Based on USB HID Keyboard/Keypad page (0x07).
    ///
    /// Printable ranges:
    ///   0x04–0x27  a–z (0x04–0x1D), 1–0 (0x1E–0x27)
    ///   0x2D–0x38  punctuation: - = [ ] \ # ; ' ` , . /
    ///
    /// Explicitly excluded control keys in the gap 0x28–0x2C:
    ///   0x28 Enter, 0x29 Escape, 0x2A Backspace, 0x2B Tab, 0x2C Space
    /// These are flush-triggering or forwarding keys, never composition input.
    /// Space (0x2C) is always forwarded even in direct mode.
    pub fn isPrintablePosition(self: KeyEvent) bool {
        return (self.hid_keycode >= 0x04 and self.hid_keycode <= 0x27) or
               (self.hid_keycode >= 0x2D and self.hid_keycode <= 0x38);
    }
};
```

**Design notes:**
- `hid_keycode` is the USB HID usage code — a physical key position. Korean input depends on physical key position (not the produced character), making HID the correct representation.
- `shift` is separate from `modifiers` because Shift participates in character production (Korean jamo selection), while Ctrl/Alt/Cmd trigger composition flush. This mirrors the ibus-hangul pattern where `IBUS_CONTROL_MASK | IBUS_MOD1_MASK` triggers flush but `IBUS_SHIFT_MASK` does not.
- `action` (press/release/repeat) added based on ghostty's `ghostty_input_action_e`. Release events are needed for future Kitty keyboard protocol support. The IME engine typically ignores release events.
- **Wire-to-KeyEvent mapping**: The daemon decomposes the protocol wire modifier bitmask into `KeyEvent` fields before calling `processKey()`. See [daemon design doc 02 §4.2](../../../../../libitshell3/02-design-docs/daemon/draft/v1.0-r3/02-integration-boundaries.md#wire-to-keyevent-decomposition) for the full mapping table.
## 2. ImeResult (Output from IME)

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
    /// Callers MAY ignore this flag and update preedit unconditionally
    /// as a safety fallback during debugging. This is always correct
    /// but wasteful.
    preedit_changed: bool = false,
};
```

For the complete scenario matrix and direct mode behavior, see [behavior/draft/v1.0-r1/02-scenario-matrix.md](../../../behavior/draft/v1.0-r1/02-scenario-matrix.md).
## 3. Modifier Flush Policy

When the IME has active preedit and a modifier+key or special key arrives, the engine **flushes (commits)** the in-progress composition, then forwards the key. The preedit is never silently discarded. Shift does NOT flush — it participates in jamo selection (e.g., ㄱ→ㄲ).

For the complete flush policy table, examples, and verification against ibus-hangul/fcitx5-hangul, see [behavior/draft/v1.0-r1/03-modifier-flush-policy.md](../../../behavior/draft/v1.0-r1/03-modifier-flush-policy.md).
## 4. Input Method Identifiers

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

> **Orthogonal axis: `keyboard_layout`**: Physical keyboard layout (QWERTY/AZERTY/QWERTZ) is a separate per-session field, orthogonal to `input_method`. Korean input methods always use QWERTY-normalized input regardless of physical keyboard. The `keyboard_layout` field persists across input method switches. See [05-cjk-preedit-protocol.md, Section 3.3](../../../../../libitshell3-protocol/02-design-docs/server-client-protocols/draft/v1.0-r12/05-cjk-preedit-protocol.md#33-per-session-input-method-state) for details.
