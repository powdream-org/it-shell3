# 01 — libitshell3 ↔ libitshell3-ime Interface Contract

> **Status**: Draft v2 — subject to revision.
> **Supersedes**: Portions of [04-architecture.md](../../../01-overview/04-architecture.md) and [05-integration-with-libitshell3.md](../../../01-overview/05-integration-with-libitshell3.md) regarding types and processing flow.

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

---

## 2. Processing Pipeline

### Three-Phase Key Processing

```
Client sends: HID keycode + modifiers + shift
                    │
                    ▼
┌──────────────────────────────────────────────────┐
│  Phase 0: Global Shortcut Check (libitshell3)    │
│                                                   │
│  • Language switch → setActiveLanguage(lang_id)   │
│    (toggle key detection is libitshell3's concern)│
│  • App-level shortcuts that bypass IME entirely   │
│  • If consumed: STOP                              │
└──────────────────────┬───────────────────────────┘
                       │ not consumed
                       ▼
┌──────────────────────────────────────────────────┐
│  Phase 1: IME Engine (libitshell3-ime)           │
│                                                   │
│  processKey(KeyEvent) → ImeResult                 │
│                                                   │
│  Engine internally:                               │
│  • Checks modifiers (Ctrl/Alt/Cmd) → flush + fwd │
│  • Checks non-printable (arrow/F-key) → flush+fwd│
│  • Feeds printable to libhangul → compose         │
│  • Returns committed/preedit/forward_key          │
└──────────────────────┬───────────────────────────┘
                       │ ImeResult
                       ▼
┌──────────────────────────────────────────────────┐
│  Phase 2: ghostty Integration (libitshell3)      │
│                                                   │
│  committed_text → ghostty_surface_key             │
│                   (composing=false, text=utf8)    │
│                                                   │
│  preedit_text   → ghostty_surface_preedit         │
│                   (utf8, len)                     │
│                                                   │
│  forward_key    → HID→ghostty_key mapping         │
│                 → ghostty keybinding check         │
│                 → if not bound: ghostty_surface_key│
│                   (composing=false, text=null)    │
└──────────────────────────────────────────────────┘
```

### Why IME Runs Before Keybindings

When the user presses Ctrl+C during Korean composition (preedit = "하"):

1. **Phase 0 (shortcuts)**: libitshell3 checks — Ctrl+C is not a language toggle or global shortcut. Pass through.
2. **Phase 1 (IME)**: Engine detects Ctrl modifier → flushes "하" → returns `{ committed: "하", forward_key: Ctrl+C }`
3. **Phase 2 (ghostty)**: Committed text "하" is sent to PTY via `ghostty_surface_key`. Then Ctrl+C goes through ghostty's keybinding system. If Cmd+C is bound to "copy", it fires. If not, `ghostty_surface_key` encodes it as `0x03` (ETX).

This ensures the user's in-progress composition is preserved before any keybinding action.

**Verified by PoC** (`poc/ime-key-handling/`): All 10 test scenarios pass — arrows, Ctrl+C, Ctrl+D, Enter, Escape, Tab, backspace jamo-undo, shifted keys, and mixed compose-arrow-compose sequences all work correctly with libhangul.

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

    /// Modifier key state (excluding Shift — see `shift` field).
    modifiers: Modifiers,

    /// Shift key state. Separated from modifiers because Shift changes
    /// the character produced (e.g., 'r'→ㄱ vs 'R'→ㄲ in Korean 2-set),
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
/// All three output fields are orthogonal — any combination is valid.
///
/// Memory: all slices point into internal buffers owned by the ImeEngine
/// instance. They are valid until the next call to processKey(), flush(),
/// or reset() on the SAME engine instance.
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
    /// Used for dirty tracking — only send preedit updates to client
    /// when this is true.
    preedit_changed: bool = false,
};
```

**Scenario matrix:**

| Situation | committed | preedit | forward_key | preedit_changed |
|-----------|-----------|---------|-------------|-----------------|
| English 'a' (direct mode) | `"a"` | null | null | false |
| Korean ㄱ (start composing) | null | `"ㄱ"` | null | true |
| Korean 가 (add vowel) | null | `"가"` | null | true |
| Korean 간 → new ㄱ (syllable break) | `"간"` | `"ㄱ"` | null | true |
| Arrow during composition | `"한"` (flush) | null | arrow key | true |
| Ctrl+C during composition | `"하"` (flush) | null | Ctrl+C key | true |
| Enter during composition | `"ㅎ"` (flush) | null | Enter key | true |
| Backspace mid-composition | null | `"하"` (undo) | null | true |
| Backspace empty composition | null | null | Backspace | false |
| English Ctrl+C (no composition) | null | null | Ctrl+C key | false |
| Mode toggle (Korean→direct) | `"한"` (flush) | null | null | true |
| Release event | null | null | null | false |

### 3.3 Language and Mode

```zig
/// A language identifier. Determines which composition engine processes keys.
/// libitshell3 configures the available languages and tells libitshell3-ime
/// which one is active. Language switching (toggle key detection, UI) is
/// entirely libitshell3's concern.
pub const LanguageId = enum(u8) {
    /// Direct passthrough — no composition. Used for English, Latin scripts,
    /// and any layout where keys map directly to characters.
    /// Named "direct" (not "english") because it applies to any non-composing layout.
    direct = 0,

    /// Korean — Hangul composition via libhangul.
    /// Jamo are assembled into syllables algorithmically.
    korean = 1,

    // Future:
    // japanese = 2,  // Kana composition + kanji candidate selection (libkkc/libmozc)
    // chinese = 3,   // Pinyin composition + hanzi candidate selection (librime)
};

/// Descriptor for a supported language. Returned by getSupportedLanguages().
pub const LanguageDescriptor = struct {
    id: LanguageId,
    /// Human-readable name (e.g., "English (Direct)", "한국어 (2-set)")
    name: []const u8,
    /// Whether this language uses composition (preedit).
    /// false for direct, true for Korean/Japanese/Chinese.
    is_composing: bool,
};
```

**Language management protocol:**

libitshell3 owns language selection. The interaction is:

1. **At startup**: libitshell3 calls `getSupportedLanguages()` to discover what the IME supports.
2. **Configuration**: libitshell3 calls `setEnabledLanguages()` with the user's selected language list (e.g., `[.direct, .korean]`). This determines the rotation order for toggle keys.
3. **Language switch**: When the user presses the toggle key (detected by libitshell3), libitshell3 calls `setActiveLanguage(lang_id)`. The IME flushes any pending composition and switches.
4. **Synchronization**: libitshell3 can call `getActiveLanguage()` at any time to query the current state (e.g., after session restore).

### 3.4 ImeEngine (Interface for Dependency Injection)

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
        activate: *const fn (ptr: *anyopaque) void,

        /// Pane lost focus. Engine should flush pending composition.
        /// (Commit the in-progress syllable so it's not lost.)
        deactivate: *const fn (ptr: *anyopaque) ImeResult,

        // --- Language management ---

        /// Get list of languages this engine supports.
        /// Returns a slice valid for the engine's lifetime.
        getSupportedLanguages: *const fn (ptr: *anyopaque) []const LanguageDescriptor,

        /// Set which languages are enabled (user's rotation list).
        /// e.g., [.direct, .korean] means toggle rotates between these two.
        setEnabledLanguages: *const fn (ptr: *anyopaque, langs: []const LanguageId) void,

        /// Get current active language.
        getActiveLanguage: *const fn (ptr: *anyopaque) LanguageId,

        /// Set active language. Flushes pending composition if switching
        /// away from a composing language.
        /// Called by libitshell3 when user presses the toggle key.
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

    pub fn getSupportedLanguages(self: ImeEngine) []const LanguageDescriptor {
        return self.vtable.getSupportedLanguages(self.ptr);
    }

    pub fn setEnabledLanguages(self: ImeEngine, langs: []const LanguageId) void {
        self.vtable.setEnabledLanguages(self.ptr, langs);
    }

    pub fn getActiveLanguage(self: ImeEngine) LanguageId {
        return self.vtable.getActiveLanguage(self.ptr);
    }

    pub fn setActiveLanguage(self: ImeEngine, lang: LanguageId) ImeResult {
        return self.vtable.setActiveLanguage(self.ptr, lang);
    }
};
```

**Why vtable over comptime generics:**
- Comptime generics (`fn Pane(comptime Ime: type) type`) would monomorphize all Pane code per IME type, inflating binary size when multiple engines exist.
- vtable is a single pointer indirection — negligible cost at the call rates we see (< 100 calls/second for human typing).
- vtable works with C FFI (comptime generics don't export to C).

### 3.5 HangulImeEngine (Concrete Implementation)

```zig
/// Concrete IME engine wrapping libhangul for Korean + direct mode passthrough.
pub const HangulImeEngine = struct {
    hic: *c.HangulInputContext,
    active_language: LanguageId,
    enabled_languages: [4]LanguageId = .{ .direct, .korean, .direct, .direct },
    enabled_count: usize = 2,
    layout_id: []const u8,  // e.g., "2" for dubeolsik (string, not enum)

    // Internal fixed-size buffers for ImeResult slices
    committed_buf: [256]u8 = undefined,
    preedit_buf: [64]u8 = undefined,
    committed_len: usize = 0,
    preedit_len: usize = 0,

    // Previous preedit for dirty tracking
    prev_preedit_len: usize = 0,

    // Static language descriptors
    const supported_languages = [_]LanguageDescriptor{
        .{ .id = .direct, .name = "English (Direct)", .is_composing = false },
        .{ .id = .korean, .name = "한국어 (2-set)", .is_composing = true },
    };

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
    fn getSupportedLanguagesImpl(ptr: *anyopaque) []const LanguageDescriptor;
    fn setEnabledLanguagesImpl(ptr: *anyopaque, langs: []const LanguageId) void;
    fn getActiveLanguageImpl(ptr: *anyopaque) LanguageId;
    fn setActiveLanguageImpl(ptr: *anyopaque, lang: LanguageId) ImeResult;
};
```

**Why `layout_id` is a string, not an enum:**
- libhangul identifies keyboards by string ID ("2", "3f", "ro", etc.).
- An enum would need to stay in sync with libhangul's keyboard list.
- libhangul supports external keyboards loaded from XML files — an enum can't represent those.
- v1 ships dubeolsik ("2") only. Additional layouts are a config change, not an API change.

---

## 4. Responsibility Matrix

| Responsibility | Owner | Rationale |
|---|---|---|
| HID keycode → ASCII character | **libitshell3-ime** | IME needs ASCII for `hangul_ic_process()`. Mapping is layout-dependent (Korean 2-set vs 3-set). |
| HID keycode → ghostty key enum | **libitshell3** | ghostty's key encoder uses its own W3C UIEvents-based enum. IME-independent. |
| Hangul composition (jamo assembly, backspace) | **libitshell3-ime** | Core IME logic. Wraps libhangul. |
| Modifier detection + flush decision | **libitshell3-ime** | Engine decides when Ctrl/Alt/Cmd breaks composition. Matches ibus-hangul/fcitx5-hangul pattern. |
| UCS-4 → UTF-8 conversion | **libitshell3-ime** | libhangul outputs UCS-4. The rest of the system uses UTF-8. |
| Language toggle key detection | **libitshell3** | Configurable keybinding (한/영, Right Alt, Caps Lock). Not an IME concern. |
| Language list configuration | **libitshell3** | Calls `setEnabledLanguages()` with user's selected list. |
| Active language switching | **libitshell3** | Calls `setActiveLanguage(lang_id)` when user toggles. |
| Reporting supported languages | **libitshell3-ime** | Returns `LanguageDescriptor[]` via `getSupportedLanguages()`. |
| Flushing on language switch | **libitshell3-ime** | `setActiveLanguage()` flushes pending composition internally. |
| Keybinding interception (Cmd+V, Cmd+C) | **libitshell3 via ghostty** | Keybindings run in Phase 2, after IME has flushed. |
| Calling `ghostty_surface_key()` | **libitshell3** | Daemon translates ImeResult into ghostty API calls. |
| Calling `ghostty_surface_preedit()` | **libitshell3** | Daemon forwards preedit to ghostty's renderer overlay. |
| Terminal escape sequence encoding | **ghostty** (via `ghostty_surface_key`) | ghostty's KeyEncoder runs daemon-side. We do NOT write our own encoder. |
| PTY writes | **ghostty** (internal to `ghostty_surface_key`) | ghostty handles PTY I/O internally after encoding. |
| Sending preedit/render state to remote client | **libitshell3** (protocol layer) | Part of the FrameUpdate protocol. |
| Rendering preedit overlay on screen | **it-shell3 app** (client) | Client receives preedit from server, renders via Metal. |
| Per-pane ImeEngine lifecycle | **libitshell3** | Creates/destroys engine per pane. Calls activate/deactivate on focus change. |

### What libitshell3-ime Does NOT Do

- Does NOT know about PTYs, sockets, sessions, panes, or protocols.
- Does NOT encode terminal escape sequences (no VT knowledge).
- Does NOT detect language toggle keys (that's libitshell3's keybinding concern).
- Does NOT decide when to switch languages (libitshell3 calls `setActiveLanguage()`).
- Does NOT interact with ghostty APIs (no ghostty dependency).
- Does NOT manage candidate window UI (app layer concern, future).

---

## 5. ghostty Integration

### ImeResult → ghostty API Mapping

The daemon's per-pane key handler translates `ImeResult` into ghostty calls:

```zig
fn handleKeyEvent(pane: *Pane, key: KeyEvent) void {
    const result = pane.ime.processKey(key);

    // 1. Send committed text (if any) via ghostty key event path
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
    }

    // 2. Update preedit overlay (if changed)
    if (result.preedit_changed) {
        if (result.preedit_text) |text| {
            ghostty_surface_preedit(pane.surface, text.ptr, text.len);
        } else {
            ghostty_surface_preedit(pane.surface, null, 0); // clear
        }
    }

    // 3. Forward unconsumed key (if any) through ghostty's full pipeline
    if (result.forward_key) |fwd| {
        const ghost_key = ghostty_input_key_s{
            .action = switch (fwd.action) {
                .press => .press,
                .release => .release,
                .repeat => .repeat,
            },
            .mods = mapModifiers(fwd.modifiers, fwd.shift),
            .consumed_mods = .{},
            .keycode = mapHidToGhosttyKey(fwd.hid_keycode),
            .text = null,
            .unshifted_codepoint = 0,
            .composing = false,
        };
        // Goes through ghostty's keybinding check → key encoder → PTY
        ghostty_surface_key(pane.surface, ghost_key);
    }
}
```

### Critical Rule: NEVER Use `ghostty_surface_text()`

`ghostty_surface_text()` is ghostty's **clipboard paste** API. It wraps text in bracketed paste markers (`\e[200~...\e[201~`) when bracketed paste mode is active. Using it for IME committed text causes the **Korean doubling bug** discovered in the it-shell project:

```
User types: 한글
ghostty_surface_text("한") → \e[200~한\e[201~
ghostty_surface_text("글") → \e[200~글\e[201~
Display: 하하한한그그글글  ← DOUBLED
```

All IME output MUST go through `ghostty_surface_key()` with `composing=false` and the text in the `text` field. This path uses the KeyEncoder, which is KKP-aware and never wraps in bracketed paste.

### Two HID Mapping Tables

| Table | Location | Input | Output | Purpose |
|---|---|---|---|---|
| HID → ASCII | **libitshell3-ime** | `hid_keycode` + `shift` | ASCII char (`'a'`, `'A'`, `'r'`, `'R'`) | Feed `hangul_ic_process()` |
| HID → ghostty key enum | **libitshell3** | `hid_keycode` | `ghostty_input_key_e` value | Feed `ghostty_surface_key()` |

Both are static lookup tables. They don't conflict and shouldn't be merged — they serve different consumers in different libraries.

---

## 6. Memory Ownership

### Rule: Internal Buffers, Invalidated on Next Mutating Call

`ImeResult` fields (`committed_text`, `preedit_text`) are slices pointing into **fixed-size internal buffers** owned by the `HangulImeEngine` instance:

```
committed_buf: [256]u8  — holds committed UTF-8 text
preedit_buf:   [64]u8   — holds preedit UTF-8 text
```

**Lifetime**: Slices are valid until the next call to `processKey()`, `flush()`, `reset()`, `deactivate()`, or `setMode()` on the **same** engine instance.

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
// Future — not implemented in v1
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
3. Register the factory in libitshell3's engine registry (future Phase 7).
4. No changes to `KeyEvent`, `ImeResult`, or the processing pipeline.

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
// Hypothetical future itshell3_ime.h — NOT for v1
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
// In itshell3.h — the preedit callback the host app receives
typedef void (*itshell3_preedit_cb)(
    uint32_t pane_id,
    const char* text,       // UTF-8 preedit text, NULL if cleared
    size_t text_len,
    uint32_t cursor_x,
    uint32_t cursor_y,
    void* userdata
);

// In itshell3.h — the language change callback
typedef void (*itshell3_language_cb)(
    uint32_t pane_id,
    uint8_t language_id,    // 0=direct, 1=korean
    const char* language_name, // UTF-8, e.g. "한국어 (2-set)"
    void* userdata
);
```

The host app never knows about `ImeEngine`, `KeyEvent`, or `ImeResult`. It sends raw key events via the wire protocol and receives preedit/mode updates via callbacks.

---

## Appendix A: Stale Documentation Notes

The following existing documents contain outdated information that conflicts with this interface contract:

| Document | Issue | Status |
|----------|-------|--------|
| `docs/libitshell3/13-render-state-protocol.md` | References NSTextInputContext for server-side preedit (lines 277-284). Should reference libitshell3-ime's `processKey()` flow. | Stale — needs update |
| `docs/libitshell3/09-recommended-architecture.md` | Contains client-driven preedit API (`itshell3_preedit_start/update/end`). With native IME, preedit is server-driven. | Stale — needs update |
| `docs/libitshell3/14-architecture-validation-report.md` | States "~300-400 lines of pure Zig, no external library needed" (line 113). We chose libhangul wrapper instead. | Inconsistent — note the decision |
| `docs/libitshell3-ime/04-architecture.md` | `InputMode` uses `english` (should be `direct`). `flush()` returns `?[]const u8` (should return `ImeResult`). `KeyboardLayout` is an enum (should be string ID). No `ImeEngine` trait. | Superseded by this document |

## Appendix B: v1 Scope

For Phase 1.5 (native IME), implement only:

- **HangulImeEngine** with dubeolsik ("2") layout.
- **Direct mode** passthrough (HID → ASCII, no composition).
- **Mode toggle** via `setMode()` called by libitshell3.
- **No candidate support** (Korean doesn't need it).
- **No separate C API** (internal to libitshell3).
- **No external keyboard XML loading** (libhangul compiled without `ENABLE_EXTERNAL_KEYBOARDS`).
- Additional layouts ("3f", "39", "ro", etc.) deferred to Phase 6 (polish). Adding them is a config change, not an API change — libhangul supports all 9 internally.
