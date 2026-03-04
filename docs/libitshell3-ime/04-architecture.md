# libitshell3-ime Architecture

## Overview

libitshell3-ime is a thin Zig wrapper around libhangul that adds:
1. **HID keycode → ASCII mapping** (layout-aware)
2. **Non-Hangul key pre-filtering** (modifiers, arrows, function keys)
3. **UCS-4 → UTF-8 conversion** (libhangul outputs UCS-4, the rest of the system uses UTF-8)
4. **English QWERTY mode** (passthrough without composition)
5. **A clean Zig API** that hides libhangul's C internals

```
┌─────────────────────────────────────────────────────────────┐
│                    libitshell3-ime                            │
│                                                              │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────┐ │
│  │ Layout       │  │ Key Filter   │  │ Composition Engine │ │
│  │ Mapper       │  │              │  │ (libhangul wrapper)│ │
│  │              │  │ Modifier?    │  │                    │ │
│  │ HID keycode  │  │ Arrow?       │  │ hangul_ic_process  │ │
│  │ + layout_id  │  │ Function?    │  │ hangul_ic_backspace│ │
│  │ → ASCII char │  │ → flush+fwd  │  │ hangul_ic_flush    │ │
│  │              │  │              │  │                    │ │
│  │              │  │ Printable?   │  │ UCS-4 → UTF-8     │ │
│  │              │  │ → compose    │  │ conversion         │ │
│  └──────┬───────┘  └──────┬───────┘  └────────┬───────────┘ │
│         │                 │                    │             │
│         └─────────────────┼────────────────────┘             │
│                           │                                  │
│                    ┌──────▼───────┐                          │
│                    │  ImeResult   │                          │
│                    │              │                          │
│                    │ .committed   │ → UTF-8 text for PTY     │
│                    │ .preedit     │ → UTF-8 text for display │
│                    │ .forward_key │ → key event for terminal │
│                    └──────────────┘                          │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Processing Flow

### Complete Flow Diagram

```
Raw HID keycode + modifiers + shift_pressed + active_layout
                    │
                    ▼
          ┌─────────────────┐
          │ 1. Mode Check   │
          │ English/Korean? │
          └────────┬────────┘
                   │
         ┌─────────┴──────────┐
         │                    │
    English mode         Korean mode
         │                    │
         ▼                    ▼
  ┌──────────────┐   ┌──────────────────┐
  │ 2a. Layout   │   │ 2b. Pre-Filter   │
  │ Map to ASCII │   │ Has modifier?    │
  │ Return as    │   │ Non-printable?   │
  │ committed    │   └───────┬──────────┘
  └──────────────┘           │
                    ┌────────┴─────────┐
                    │                  │
              Modifier/Special    Printable
                    │                  │
                    ▼                  ▼
           ┌──────────────┐   ┌──────────────────┐
           │ 3a. Flush    │   │ 3b. Layout Map   │
           │ composition  │   │ HID → ASCII char │
           │ + forward    │   └───────┬──────────┘
           │ original key │           │
           └──────────────┘           ▼
                             ┌──────────────────┐
                             │ 4. libhangul     │
                             │ process(ascii)   │
                             └───────┬──────────┘
                                     │
                            ┌────────┴────────┐
                            │                 │
                       consumed=true     consumed=false
                            │                 │
                            ▼                 ▼
                    ┌──────────────┐  ┌──────────────┐
                    │ 5a. Read     │  │ 5b. Flush    │
                    │ commit_str   │  │ composition  │
                    │ preedit_str  │  │ + forward    │
                    │ UCS4→UTF8   │  │ original key │
                    └──────────────┘  └──────────────┘
                            │                 │
                            └────────┬────────┘
                                     ▼
                              ┌──────────────┐
                              │  ImeResult   │
                              └──────────────┘
```

### Step-by-Step Description

**Step 1: Mode Check**

Check the active input mode (English or Korean). In English mode, skip composition entirely — just map the HID keycode to an ASCII character and return it as committed text.

**Step 2b: Pre-Filter (Korean mode)**

Before feeding to libhangul, filter out keys that should never enter the composition engine:

```
Pre-filter rules (in order):
1. Ctrl held    → flush + forward key
2. Alt held     → flush + forward key
3. Cmd/Super    → flush + forward key
4. Arrow keys   → flush + forward key
5. Function keys (F1-F12) → flush + forward key
6. Escape       → flush + forward key
7. Tab          → flush + forward key
8. Enter/Return → flush + forward key
9. Delete/Backspace → try hangul_ic_backspace() first
                      if false (empty) → forward backspace
10. Other non-printable → flush + forward key
```

This matches the pattern used by ibus-hangul and fcitx5-hangul.

**Step 3b: Layout Map**

For printable keys in Korean mode, map the HID keycode to the ASCII character that the 2-set keyboard layout expects. libhangul's `hangul_ic_process()` takes an ASCII key code (e.g., 'r' for ㄱ, 'k' for ㅏ).

**Step 4: libhangul Process**

Feed the ASCII character to `hangul_ic_process()`. Read the return value and strings.

**Step 5a/5b: Result Handling**

If consumed (true): read `get_preedit_string()` and `get_commit_string()`, convert from UCS-4 to UTF-8.

If not consumed (false): the key maps to 0 in libhangul's keyboard table. Flush composition, forward the key.

---

## Zig API Design

### Public Types

```zig
pub const ImeContext = struct {
    hic: *c.HangulInputContext,
    mode: InputMode,
    layout: KeyboardLayout,

    pub const InputMode = enum {
        english,
        korean,
    };

    pub const KeyboardLayout = enum {
        dubeolsik,       // "2"
        dubeolsik_yet,   // "2y"
        sebeolsik_32,    // "32"
        sebeolsik_390,   // "39"
        sebeolsik_final, // "3f"
        sebeolsik_noshift, // "3s"
        sebeolsik_yet,   // "3y"
        romaja,          // "ro"
        ahnmatae,        // "ahn"
    };
};

pub const KeyEvent = struct {
    hid_keycode: u8,       // USB HID usage code (0x04 = 'a', etc.)
    modifiers: Modifiers,
    shift: bool,           // Shift key state (for uppercase / shifted jamo)

    pub const Modifiers = packed struct {
        ctrl: bool = false,
        alt: bool = false,
        super_key: bool = false,  // Cmd on macOS
    };
};

pub const ImeResult = struct {
    /// UTF-8 text to commit to PTY. null if nothing to commit.
    committed_text: ?[]const u8,

    /// UTF-8 preedit text for display. null if no active composition.
    preedit_text: ?[]const u8,

    /// Key event to forward to terminal. null if key was consumed by IME.
    forward_key: ?KeyEvent,

    /// Whether preedit state changed (for dirty tracking).
    preedit_changed: bool,
};
```

### Public Functions

```zig
pub fn init(layout: KeyboardLayout) !ImeContext;
// Create a new IME context with the given Korean keyboard layout.
// Starts in English mode.

pub fn deinit(self: *ImeContext) void;
// Destroy the context. Discards any pending composition.
// Call flush() before deinit() if you need the pending text.

pub fn processKey(self: *ImeContext, key: KeyEvent) ImeResult;
// Process a key event. Returns committed text, preedit update,
// and/or a key to forward to the terminal.
//
// Thread safety: NOT thread-safe. Each pane should have its own context.

pub fn flush(self: *ImeContext) ?[]const u8;
// Flush and commit any in-progress composition.
// Returns UTF-8 committed text, or null if nothing was composing.

pub fn reset(self: *ImeContext) void;
// Discard any in-progress composition without committing.

pub fn isEmpty(self: *const ImeContext) bool;
// true if no composition is in progress.

pub fn toggleMode(self: *ImeContext) ImeResult;
// Toggle between English and Korean mode.
// If switching from Korean, flushes pending composition.
// Returns committed text from flush (if any).

pub fn setMode(self: *ImeContext, mode: InputMode) ImeResult;
// Set input mode explicitly. Flushes if switching from Korean.

pub fn setLayout(self: *ImeContext, layout: KeyboardLayout) void;
// Change Korean keyboard layout. Flushes pending composition.

pub fn getMode(self: *const ImeContext) InputMode;
// Get current input mode.
```

---

## HID Keycode to ASCII Mapping

The client sends raw USB HID keycodes. libitshell3-ime maps them to ASCII for libhangul.

### HID Usage Table (Keyboard Page 0x07)

Key HID codes for the letter keys:

| HID Code | Unshifted | Shifted |
|----------|-----------|---------|
| 0x04 | a | A |
| 0x05 | b | B |
| 0x06 | c | C |
| ... | ... | ... |
| 0x1D | z | Z |
| 0x1E | 1 | ! |
| 0x1F | 2 | @ |
| 0x20 | 3 | # |
| 0x21 | 4 | $ |
| 0x22 | 5 | % |
| 0x23 | 6 | ^ |
| 0x24 | 7 | & |
| 0x25 | 8 | * |
| 0x26 | 9 | ( |
| 0x27 | 0 | ) |
| 0x28 | Enter | — |
| 0x29 | Escape | — |
| 0x2A | Backspace | — |
| 0x2B | Tab | — |
| 0x2C | Space | — |
| 0x2D | - | _ |
| 0x2E | = | + |
| 0x2F | [ | { |
| 0x30 | ] | } |
| 0x31 | \ | \| |
| 0x33 | ; | : |
| 0x34 | ' | " |
| 0x35 | ` | ~ |
| 0x36 | , | < |
| 0x37 | . | > |
| 0x38 | / | ? |

For Korean 2-set, the unshifted/shifted ASCII character maps directly to libhangul's expected input (e.g., 'r' → ㄱ, 'R' → ㄲ).

### Non-Printable Keys (Forward to Terminal)

| HID Code | Key | Terminal Escape |
|----------|-----|-----------------|
| 0x28 | Enter | `\r` |
| 0x29 | Escape | `\x1b` |
| 0x2A | Backspace | `\x7f` or `\x08` |
| 0x2B | Tab | `\t` |
| 0x4F | Right Arrow | `\x1b[C` |
| 0x50 | Left Arrow | `\x1b[D` |
| 0x51 | Down Arrow | `\x1b[B` |
| 0x52 | Up Arrow | `\x1b[A` |
| 0x3A-0x45 | F1-F12 | `\x1bOP` through `\x1b[24~` |
| 0x49 | Insert | `\x1b[2~` |
| 0x4A | Home | `\x1b[H` |
| 0x4B | Page Up | `\x1b[5~` |
| 0x4C | Delete Forward | `\x1b[3~` |
| 0x4D | End | `\x1b[F` |
| 0x4E | Page Down | `\x1b[6~` |

Note: Terminal escape sequences depend on the terminal mode (normal vs application cursor, Kitty keyboard protocol, etc.). libitshell3-ime just returns the `forward_key` with the HID keycode — libitshell3's key encoder handles the actual escape sequence generation.

---

## Modifier Key Handling During Composition

### The Standard Pattern (ibus-hangul / fcitx5-hangul)

```
Key arrives during active composition (preedit = "하")
    │
    ├── Ctrl held? ──────► flush("하") → commit + forward Ctrl+key
    ├── Alt held? ───────► flush("하") → commit + forward Alt+key
    ├── Cmd/Super held? ─► flush("하") → commit + forward Cmd+key
    ├── Arrow key? ──────► flush("하") → commit + forward arrow
    ├── Function key? ───► flush("하") → commit + forward F-key
    ├── Escape? ─────────► flush("하") → commit + forward Esc
    ├── Enter? ──────────► flush("하") → commit + forward Enter
    ├── Tab? ────────────► flush("하") → commit + forward Tab
    ├── Backspace? ──────► hangul_ic_backspace()
    │                         ├── true: preedit updated (하→ㅎ)
    │                         └── false: forward backspace to terminal
    └── Printable? ──────► hangul_ic_process(ascii)
                              ├── true: update preedit/commit
                              └── false: flush + forward key
```

### Concrete Examples

| Preedit | Key | Action | Committed | New Preedit | Forwarded |
|---------|-----|--------|-----------|-------------|-----------|
| `"하"` | `ㄴ` (n key) | process() → true | — | `"한"` | — |
| `"한"` | `→` (right) | flush + forward | `"한"` | (empty) | Right arrow |
| `"하"` | `Ctrl+C` | flush + forward | `"하"` | (empty) | Ctrl+C |
| `"한"` | `Enter` | flush + forward | `"한"` | (empty) | Enter |
| `"ㅎ"` | `Escape` | flush + forward | `"ㅎ"` | (empty) | Escape |
| `"한"` | `Tab` | flush + forward | `"한"` | (empty) | Tab |
| `"한"` | Backspace | backspace() → true | — | `"하"` | — |
| `"ㅎ"` | Backspace | backspace() → true | — | (empty) | — |
| (empty) | Backspace | backspace() → false | — | — | Backspace |
| `"한"` | `.` (period) | process() → true | `"한."` | (empty) | — |
| (empty) | `a` | process() → true | — | `"ㅁ"` | — |

---

## UCS-4 to UTF-8 Conversion

libhangul returns `ucschar*` (uint32_t, UCS-4). The rest of the system uses UTF-8. The conversion is straightforward:

```zig
fn ucs4ToUtf8(ucs4: []const u32, buf: []u8) []const u8 {
    var i: usize = 0;
    for (ucs4) |cp| {
        if (cp == 0) break;  // null terminator
        if (cp < 0x80) {
            buf[i] = @intCast(cp);
            i += 1;
        } else if (cp < 0x800) {
            buf[i] = @intCast(0xC0 | (cp >> 6));
            buf[i + 1] = @intCast(0x80 | (cp & 0x3F));
            i += 2;
        } else if (cp < 0x10000) {
            buf[i] = @intCast(0xE0 | (cp >> 12));
            buf[i + 1] = @intCast(0x80 | ((cp >> 6) & 0x3F));
            buf[i + 2] = @intCast(0x80 | (cp & 0x3F));
            i += 3;
        } else {
            buf[i] = @intCast(0xF0 | (cp >> 18));
            buf[i + 1] = @intCast(0x80 | ((cp >> 12) & 0x3F));
            buf[i + 2] = @intCast(0x80 | ((cp >> 6) & 0x3F));
            buf[i + 3] = @intCast(0x80 | (cp & 0x3F));
            i += 4;
        }
    }
    return buf[0..i];
}
```

Korean Hangul syllables (U+AC00–U+D7A3) are all 3-byte UTF-8 sequences. Individual jamo (U+1100–U+11FF) are also 3-byte.

---

## Per-Pane State

Each terminal pane has its own `ImeContext`:

```
Pane 1: ImeContext { mode: .korean, layout: .dubeolsik, preedit: "한" }
Pane 2: ImeContext { mode: .english, layout: .dubeolsik, preedit: null }
Pane 3: ImeContext { mode: .korean, layout: .sebeolsik_390, preedit: "ㅎ" }
```

When the user switches panes:
1. The old pane's IME state is preserved (including preedit).
2. The new pane's IME state is loaded.
3. The client displays the new pane's preedit (if any).

When the user switches input mode (Korean ↔ English):
1. If switching from Korean: flush pending composition → commit to PTY.
2. Toggle the mode flag.
3. Send mode indicator to client for display (e.g., "한/A" status bar).
