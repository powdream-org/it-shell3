# Input Handling

## Overview

Input handling for it-shell3 must support:
1. Standard terminal keyboard input
2. CJK IME composition (covered in detail in [05-cjk-input-composition.md](./05-cjk-input-composition.md))
3. Special key combinations: Shift+Enter, Cmd+C/V
4. Mouse events
5. Multiplexer-level keybindings (prefix key, pane navigation)

---

## 1. How Terminal Keyboard Input Works

### macOS Input Pipeline

```
Physical Keyboard
    │
    ▼
macOS HID System
    │
    ▼
NSEvent (keyDown/keyUp/flagsChanged)
    │
    ├─── performKeyEquivalent()  →  App-level shortcuts (Cmd+C, Cmd+V, etc.)
    │
    ├─── keyDown()  →  Regular key input
    │       │
    │       ├─── insertText()          →  Committed text (after IME)
    │       ├─── setMarkedText()       →  Preedit text (during IME)
    │       └─── doCommandBySelector() →  Key commands (Delete, Tab, etc.)
    │
    ▼
ghostty_surface_key() / ghostty_surface_text() / ghostty_surface_preedit()
    │
    ▼
Terminal escape sequences → PTY → Shell/Application
```

### How cmux/Ghostty Handles Key Input

**Source**: `~/dev/git/references/cmux/Sources/GhosttyTerminalView.swift`

```swift
// GhosttyTerminalView.swift (line 3018+)
class GhosttyTerminalView: NSView {

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Handle Cmd-key shortcuts BEFORE the menu system
        // This prevents Cmd+C from being consumed as "Copy" by AppKit
        // when the terminal wants to handle it differently

        if event.modifierFlags.contains(.command) {
            // Check if ghostty has a binding for this key
            if ghostty_surface_key_is_binding(surface, keyEvent) {
                ghostty_surface_key(surface, keyEvent)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // For keys without Cmd modifier (or only Shift):
        // 1. Let NSTextInputContext handle it for IME
        // 2. insertText() or setMarkedText() will be called

        // For composing (IME active):
        // - Set composing flag on key event
        // - Let the input context process it
        inputContext?.handleEvent(event)
    }

    // NSTextInputClient protocol:
    func insertText(_ string: Any, replacementRange: NSRange) {
        // Called when IME commits text
        ghostty_surface_text(surface, utf8String, length)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        // Called during IME composition
        ghostty_surface_preedit(surface, utf8String, length)
    }
}
```

### Ghostty Key Event Structure

```zig
// src/input/key.zig
pub const KeyEvent = struct {
    action: Action,              // press, release, repeat
    key: Key,                    // Physical key code
    mods: Mods,                  // Active modifiers (Shift, Ctrl, Alt, Super)
    consumed_mods: Mods,         // Modifiers consumed by text generation
    composing: bool,             // TRUE during IME composition
    utf8: ?[]const u8,           // Generated text (if any)
    unshifted_codepoint: ?u32,   // Codepoint without Shift applied
};

pub const Mods = packed struct {
    shift: bool,
    ctrl: bool,
    alt: bool,
    super_: bool,    // Cmd on macOS
    caps_lock: bool,
    num_lock: bool,
};
```

---

## 2. tmux Key Handling

**Source**: `~/dev/git/references/tmux/tty-keys.c`

### Key Parser Architecture

tmux builds a **ternary search tree** of escape sequences at startup:

```c
// tty-keys.c
struct tty_key {
    char            ch;         // Character in the sequence
    int             key;        // Resulting key code (if leaf)
    struct tty_key *left;       // Less than ch
    struct tty_key *right;      // Greater than ch
    struct tty_key *next;       // Equal to ch (next char in sequence)
};
```

This allows efficient prefix matching of multi-byte escape sequences.

### Raw Key Table (Hardcoded Sequences)

```c
static const struct tty_default_key_raw tty_default_raw_keys[] = {
    // Standard xterm sequences
    { "\033[A",     KEYC_UP },
    { "\033[B",     KEYC_DOWN },
    { "\033[C",     KEYC_RIGHT },
    { "\033[D",     KEYC_LEFT },

    // Shifted arrow keys
    { "\033[1;2A",  KEYC_UP|KEYC_SHIFT },

    // xterm modifyOtherKeys / CSI u format
    { "\033[13;2u", KEYC_ENTER|KEYC_SHIFT },  // Shift+Enter!

    // Function keys, Home, End, Insert, Delete, PgUp, PgDn...
};
```

### Shift+Enter in tmux

tmux recognizes Shift+Enter via:
- xterm CSI u encoding: `\033[13;2u` → `KEYC_ENTER|KEYC_SHIFT`
- The terminal emulator must be configured to send this sequence
- Ghostty supports this via the Kitty keyboard protocol

### Key Modifiers

```c
#define KEYC_SHIFT      0x00100000U
#define KEYC_ESCAPE     0x00200000U  // Alt/Meta
#define KEYC_CTRL       0x00400000U
#define KEYC_META       0x00800000U  // Super/Cmd (macOS)
```

---

## 3. Zellij Key Handling

**Source**: `~/dev/git/references/zellij/zellij-client/src/`

### Input Pipeline

```rust
// stdin_handler.rs
pub fn stdin_loop(
    os_input: Box<dyn ClientOsApi>,
    send_client_instructions: SenderWithContext<ClientInstruction>,
) {
    loop {
        // 1. Read from stdin
        let buf = os_input.read_from_stdin();

        // 2. Parse with termwiz
        let input_events = termwiz::input::InputParser::new().parse(&buf);

        // 3. Convert to zellij KeyWithModifier
        for event in input_events {
            match event {
                InputEvent::Key(key_event) => {
                    let key_with_modifier = KeyWithModifier::from(key_event);
                    send_client_instructions.send(
                        ClientInstruction::KeyEvent(key_with_modifier, raw_bytes)
                    );
                }
                InputEvent::Mouse(mouse_event) => { ... }
            }
        }
    }
}
```

### Kitty Keyboard Protocol Support

```rust
// keyboard_parser.rs
pub struct KeyWithModifier {
    pub key: Key,
    pub modifiers: Vec<KeyModifier>,
    pub raw_bytes: Vec<u8>,
    pub is_kitty_keyboard_protocol: bool,  // Enhanced key reporting
}
```

Zellij supports the Kitty keyboard protocol for:
- Distinguishing between key press, repeat, and release
- Reporting modifier keys as separate events
- Encoding Shift+Enter distinctly from Enter

### Input Modes

```rust
pub enum InputMode {
    Normal,    // Standard terminal input
    Locked,    // Only Ctrl+G to unlock
    Pane,      // Pane management mode
    Tab,       // Tab management mode
    Resize,    // Resize mode
    Move,      // Move pane mode
    Scroll,    // Scrollback mode
    Search,    // Search mode
    Session,   // Session management
    Tmux,      // tmux-compatible prefix mode
}
```

---

## 4. Handling Shift+Enter

### The Challenge

Shift+Enter must:
- In AI agent input areas: Insert a newline (not submit)
- In normal terminal: Send `\n` or `\r` (same as Enter)
- In tmux/zellij: Potentially mapped to a multiplexer action

### Terminal Encoding

| Encoding | Sequence | Notes |
|----------|----------|-------|
| Legacy | `\r` (same as Enter) | Cannot distinguish Shift+Enter |
| xterm modifyOtherKeys | `\033[13;2u` | CSI u format: keycode 13, modifier 2 (Shift) |
| Kitty keyboard protocol | `\033[13;2u` | Same encoding, but with press/release/repeat |

### Ghostty's Handling

Ghostty supports both xterm modifyOtherKeys and the Kitty keyboard protocol. When enabled:
- The terminal sends `\033[13;2u` for Shift+Enter
- The application (shell/agent) can detect this and handle it differently from plain Enter

### it-shell3 Strategy

```
┌────────────────────────────────────────────┐
│             it-shell3 Client               │
│                                            │
│  NSEvent (Shift+Enter)                     │
│      │                                     │
│      ▼                                     │
│  Check: Is this a multiplexer binding?     │
│      │                                     │
│      ├── YES → Execute multiplexer action  │
│      │                                     │
│      └── NO → Forward to ghostty surface   │
│              │                             │
│              ▼                             │
│         ghostty_surface_key()              │
│              │                             │
│              ▼                             │
│         Encode as \033[13;2u               │
│         (if Kitty/CSI u enabled)           │
│              │                             │
│              ▼                             │
│         Send to daemon → PTY → Shell/Agent │
└────────────────────────────────────────────┘
```

---

## 5. Handling Cmd+C / Cmd+V (macOS)

### The Challenge

On macOS:
- **Cmd+C** = Copy (AppKit default), but in terminal = should sometimes be SIGINT (Ctrl+C)
- **Cmd+V** = Paste (AppKit default), but in terminal = should be bracketed paste

### cmux/Ghostty Approach

```swift
// performKeyEquivalent handles Cmd-key events BEFORE AppKit menu system
override func performKeyEquivalent(with event: NSEvent) -> Bool {
    // Check if ghostty has a binding for Cmd+C
    if ghostty_surface_key_is_binding(surface, keyEvent) {
        // Let ghostty handle it (could be copy if text selected, or send to PTY)
        ghostty_surface_key(surface, keyEvent)
        return true
    }
    // Fall through to AppKit (standard Copy/Paste)
    return super.performKeyEquivalent(with: event)
}
```

### Ghostty's Copy/Paste Logic

Ghostty's default behavior:
- **Cmd+C with selection**: Copy selected text to clipboard
- **Cmd+C without selection**: Send Ctrl+C (SIGINT) to PTY
- **Cmd+V**: Paste from clipboard (with bracketed paste wrapping if enabled)

### it-shell3 Strategy

1. **Copy (Cmd+C)**:
   - If text is selected in the ghostty surface → Copy to clipboard
   - If no selection → Forward to daemon as Ctrl+C
   - AI agent mode: Always copy (agents handle Ctrl+C differently)

2. **Paste (Cmd+V)**:
   - Read from clipboard
   - Send as bracketed paste to daemon → PTY
   - AI agent mode: Insert text at cursor without bracketed paste wrapper

---

## 6. Multiplexer Key Bindings

### tmux Prefix Mode

tmux uses a prefix key (default: `Ctrl+B`) followed by a command key:
- `Ctrl+B` then `%`: Split horizontal
- `Ctrl+B` then `"`: Split vertical
- `Ctrl+B` then arrow: Navigate panes
- `Ctrl+B` then `d`: Detach

### Zellij Mode System

Zellij uses modal keybindings:
- `Ctrl+P`: Enter pane mode (arrow keys navigate)
- `Ctrl+T`: Enter tab mode
- `Ctrl+N`: Enter resize mode
- `Ctrl+S`: Enter scroll mode

### it-shell3 Approach

Consider a hybrid:

1. **Default**: Zellij-style modes (more discoverable)
2. **Optional**: tmux prefix compatibility mode
3. **Custom**: Per-pane key binding profiles for AI agents

```
┌──────────────────────────────────────┐
│         Key Event Processing         │
│                                      │
│  1. Check multiplexer bindings       │
│     (prefix mode / modal mode)       │
│         │                            │
│         ├── Match → Execute action   │
│         │                            │
│  2. Check CJK composition state     │
│     (IME preedit active?)            │
│         │                            │
│         ├── Composing → IME handler  │
│         │                            │
│  3. Check AI agent mode             │
│     (special key handling?)          │
│         │                            │
│         ├── Agent → Agent handler    │
│         │                            │
│  4. Forward to PTY                   │
│     (normal terminal input)          │
└──────────────────────────────────────┘
```

---

## 7. Mouse Events

### Ghostty Mouse API

```c
bool ghostty_surface_mouse_captured(ghostty_surface_t);   // Is mouse reporting active?
void ghostty_surface_mouse_button(ghostty_surface_t, ghostty_input_mouse_button_s);
void ghostty_surface_mouse_pos(ghostty_surface_t, double x, double y);
void ghostty_surface_mouse_scroll(ghostty_surface_t, double dx, double dy, ghostty_input_scroll_mods_s);
void ghostty_surface_mouse_pressure(ghostty_surface_t, uint32_t stage, float pressure);
```

### it-shell3 Mouse Handling

1. **Mouse reporting mode active** (`mouse_captured` = true):
   - Forward all mouse events through daemon to PTY
   - Application (vim, htop, etc.) handles them

2. **Mouse reporting inactive**:
   - Click: Focus pane
   - Drag: Select text
   - Right-click: Context menu
   - Scroll: Scrollback navigation

---

## 8. Key Encoding for the Wire Protocol

When forwarding key events from client to daemon:

### Option A: Raw Bytes
Send the raw escape sequence bytes that the terminal emulator would generate.
- Pros: Simple, no additional encoding needed
- Cons: Loses semantic information (can't distinguish key+modifier combos)

### Option B: Structured Key Events
Send structured key event with keycode + modifiers + text.
- Pros: Full semantic information, can remap on server side
- Cons: More complex encoding

### Option C: Hybrid (Recommended)
Send structured key event with optional raw bytes fallback:
```
KeyMessage {
    key: u32,           // Keycode
    mods: u8,           // Modifier flags
    text: [u8; 8],      // UTF-8 text (if any)
    text_len: u8,       // Length of text
    raw: [u8; 16],      // Raw escape sequence (fallback)
    raw_len: u8,        // Length of raw
    composing: bool,    // IME composition active
}
```
