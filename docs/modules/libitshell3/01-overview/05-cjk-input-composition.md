# CJK Input Composition

## Overview

CJK (Chinese, Japanese, Korean) input composition is the primary differentiator of it-shell3. This document covers how CJK IME works at each layer of the stack, from OS-level input methods to terminal rendering, and how it-shell3 must handle it for proper cross-session support.

---

## 1. How IME Composition Works

### The Problem

CJK text input uses Input Method Editors (IME) because:
- Chinese: Thousands of characters mapped from Pinyin/Wubi romanization
- Japanese: Kana → Kanji conversion
- Korean: Jamo consonant/vowel composition into Hangul syllable blocks

IME composition has two phases:
1. **Preedit (Composing)**: Text is being composed but not yet committed. It's displayed with underline/highlight.
2. **Commit**: The composed text is finalized and inserted.

### Korean Composition Example (Most Complex)

```
Keystroke    Preedit State    Description
─────────    ─────────────    ───────────
ㅎ (h)       ㅎ               Initial consonant
ㅏ (a)       하               + vowel → syllable block
ㄴ (n)       한               + final consonant → complete block
ㄱ (g)       한ㄱ             Ambiguous: ㄱ could be next syllable's initial
ㅡ (eu)      한그             Resolved: ㄱ moves to next syllable + vowel
```

### Korean Backspace (Jamo Decomposition)

```
Current      After Backspace   Description
───────      ───────────────   ───────────
한            하                 Remove final consonant ㄴ
하            ㅎ                 Remove vowel ㅏ
ㅎ            (empty)            Remove initial consonant, end composition
```

This decomposition must be handled correctly in preedit state synchronization.

---

## 2. libghostty's IME Support

### C API

```c
// Set preedit text during IME composition (UTF-8 encoded)
void ghostty_surface_preedit(ghostty_surface_t surface, const char* utf8, uintptr_t len);

// Commit finalized text
void ghostty_surface_text(ghostty_surface_t surface, const char* utf8, uintptr_t len);

// Get position for IME candidate window
void ghostty_surface_ime_point(ghostty_surface_t surface,
    double* x, double* y, double* width, double* height);
```

### Zig Implementation

```zig
// Surface.zig, line 2468+
pub fn preeditCallback(self: *Surface, preedit_: ?[]const u8) !void {
    // - Stores preedit text in renderer_state.preedit
    // - Pre-computes codepoints and width for rendering
    // - Triggers renderer refresh
    // - Pass null to clear preedit state
}
```

### Key Event Composition Flag

```zig
// input/key.zig
pub const KeyEvent = struct {
    action: Action,
    key: Key,
    mods: Mods,
    consumed_mods: Mods,
    composing: bool,          // TRUE during IME composition
    utf8: ?[]const u8,
    unshifted_codepoint: ?u32,
};
```

### Wide Character Rendering

```zig
// terminal/page.zig
pub const Cell = struct {
    wide: Wide,
    // ...
};

pub const Wide = enum(u2) {
    narrow,        // Width 1 (ASCII, most Latin)
    wide = 1,      // Width 2 (CJK ideographs, some emoji)
    spacer_tail,   // Placeholder after wide char (don't render)
    spacer_head,   // Placeholder at line end for wrap
};
```

### Unicode Width Properties

```zig
// unicode/props.zig
pub const Properties = packed struct {
    width: u2 = 0,                         // 0, 1, or 2
    width_zero_in_grapheme: bool = false,
    grapheme_break: GraphemeBreakNoControl = .other,
    emoji_vs_base: bool = false,
};
```

---

## 3. CJK Protocol Extension Design

**Source**: `~/dev/git/references/design-cjk-protocol-extensions.md`

### New Message Types

#### Capability Negotiation (Handshake Phase)

```
MSG_IDENTIFY_CJK_CAPS (ID: 114)
  Payload: uint32_t cjk_capabilities

  Bit flags:
    CJK_CAP_PREEDIT         = 0x01  // IME preedit synchronization
    CJK_CAP_AMBIGUOUS_WIDTH = 0x02  // Ambiguous width char config
    CJK_CAP_DOUBLE_WIDTH    = 0x04  // Double-width character support
    CJK_CAP_CONTROL_MODE    = 0x08  // Control mode CJK extensions
```

#### Preedit Messages (Runtime)

```
MSG_PREEDIT_START (ID: 311)
  Payload: {
    uint32_t pane_id;
    uint32_t cursor_x;
    uint32_t cursor_y;
  }

MSG_PREEDIT_UPDATE (ID: 312)
  Payload: {
    uint32_t pane_id;
    uint32_t cursor_x;
    uint32_t cursor_y;
    uint16_t text_len;
    char     text[];        // UTF-8 encoded preedit text
  }

MSG_PREEDIT_END (ID: 313)
  Payload: {
    uint32_t pane_id;
    uint16_t committed_len;
    char     committed[];   // UTF-8 encoded committed text (may be empty if cancelled)
  }

MSG_CJK_CONFIG (ID: 314)
  Payload: {
    uint16_t key_len;
    uint16_t value_len;
    char     key[];
    char     value[];
  }
```

#### Control Mode Extensions

```
%preedit-begin <pane-id> <cursor-x> <cursor-y>
%preedit-update <pane-id> <base64-text> <cursor-x> <cursor-y>
%preedit-end <pane-id> [<base64-committed-text>]
%cjk-config <key> <value>
```

### Server-Side Preedit State

```c
// Proposed struct for server-side pane CJK state
struct pane_cjk_state {
    bool            preedit_active;
    char            preedit_text[256];  // Current preedit (UTF-8)
    uint16_t        preedit_len;
    uint32_t        cursor_x;
    uint32_t        cursor_y;
    uint32_t        ambiguous_width;    // 1 or 2
};
```

### iOS Client Preedit Manager

```swift
// Proposed PreeditManager state machine
class PreeditManager {
    enum State {
        case idle
        case composing(text: String, cursorPosition: CGPoint)
    }

    var state: State = .idle
    var serverSupportsCJK: Bool = false

    func setMarkedText(_ text: String, selectedRange: NSRange) {
        // 1. Update local ghostty surface preedit
        ghostty_surface_preedit(surface, text.utf8CString, text.utf8.count)

        // 2. If server supports CJK, send preedit update
        if serverSupportsCJK {
            sendPreeditUpdate(text: text, cursorPosition: currentCursorPos)
        }

        state = .composing(text: text, cursorPosition: currentCursorPos)
    }

    func insertText(_ text: String) {
        // 1. Clear local preedit
        ghostty_surface_preedit(surface, nil, 0)

        // 2. Commit text to terminal
        ghostty_surface_text(surface, text.utf8CString, text.utf8.count)

        // 3. If server supports CJK, send preedit end
        if serverSupportsCJK {
            sendPreeditEnd(committedText: text)
        }

        state = .idle
    }
}
```

---

## 4. Ambiguous Width Characters

### The Problem

Some Unicode characters have "ambiguous" width — they may be displayed as 1 or 2 cells wide depending on the context (East Asian vs. Western):

- Box drawing characters (─ │ ┌ ┐)
- Greek letters (α β γ)
- Cyrillic letters
- Various symbols (° ± × ÷)

### Configuration Sync

The daemon and client must agree on ambiguous width treatment:
- Config key: `unicode-ambiguous-is-wide` (boolean)
- Synced via `MSG_CJK_CONFIG` or `%cjk-config`

---

## 5. AI Agent Input Areas

### The Challenge

AI agent chat interfaces (Claude Code, Codex CLI, Cursor) create custom input areas within the terminal that behave differently from normal shell input:

1. **Multi-line editing**: Shift+Enter inserts a newline instead of submitting
2. **Clipboard**: Cmd+C copies text (not SIGINT), Cmd+V pastes (not bracketed paste)
3. **CJK composition**: IME must work correctly within the agent's input buffer

### Detection Strategy

The daemon needs to detect when an AI agent's input area is active:

**Approach 1: Terminal Mode Detection**
- Monitor termios mode changes (raw mode vs. cooked mode)
- AI agents typically use raw mode with custom key handling
- Ghostty's termios polling (200ms) can detect this

**Approach 2: OSC Sequences**
- AI agents could emit custom OSC sequences to signal input area boundaries
- Example: `\033]9999;input-area-start\007` ... `\033]9999;input-area-end\007`
- Requires cooperation from agent developers

**Approach 3: Shell Integration**
- Detect running process via `/proc/pid/cmdline` or `ps`
- Known agent binaries: `claude`, `codex`, `cursor-terminal`
- Map process detection to input mode configuration

### Recommended Approach

Use a combination:
1. Default Shift+Enter handling configurable per-pane
2. Process detection for known AI agents
3. Custom key binding profiles per detected agent
4. Future: Propose OSC extension for agent input area signaling

---

## 6. Implementation Priority

### Phase 1: Basic CJK Rendering
- Leverage libghostty's built-in wide character support
- Ensure IUTF8 on all PTYs
- Verify HarfBuzz font shaping for CJK glyphs

### Phase 2: Local IME Composition
- Wire up `ghostty_surface_preedit()` in client
- Implement `ghostty_surface_ime_point()` for candidate window positioning
- Test with Korean (most complex), Japanese, Chinese input methods

### Phase 3: Preedit Synchronization
- Implement CJK capability negotiation in protocol handshake
- Add preedit messages (311-313) to protocol
- Server-side preedit state tracking
- Multi-client preedit rendering

### Phase 4: AI Agent Integration
- Process detection for known agents
- Custom key binding profiles (Shift+Enter, Cmd+C/V)
- CJK composition within agent input areas
