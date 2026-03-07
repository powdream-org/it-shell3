# Integration with libitshell3

## Where libitshell3-ime Lives in the Stack

```
Client (macOS/iOS)                    Server (Daemon)
┌──────────────────┐                  ┌──────────────────────────────┐
│                  │                  │                              │
│  Raw key events  │    KeyEvent     │  ┌────────────────────────┐  │
│  (HID keycode    │ ──────────────► │  │   libitshell3-ime      │  │
│   + modifiers)   │    protocol     │  │                        │  │
│                  │                  │  │  processKey(event)     │  │
│                  │                  │  │      │                 │  │
│                  │                  │  │      ▼                 │  │
│                  │                  │  │  ImeResult {           │  │
│                  │                  │  │    committed → PTY     │  │
│                  │                  │  │    preedit → display   │  │
│                  │                  │  │    forward → terminal  │  │
│                  │                  │  │  }                     │  │
│                  │                  │  └────────────────────────┘  │
│                  │                  │                              │
│                  │   FrameUpdate   │  libghostty-vt Terminal      │
│  Metal GPU       │ ◄──────────────── │  (VT parse, render state)  │
│  renderer        │    protocol     │                              │
│                  │                  │  PTY ←→ shell process       │
└──────────────────┘                  └──────────────────────────────┘
```

---

## Key Event Protocol (Client → Server)

### Wire Format

```
KeyEvent message {
    msg_type: u8,           // MSG_KEY_EVENT
    pane_id: u32,           // target pane
    hid_keycode: u8,        // USB HID usage code
    modifiers: u8,          // bit flags: ctrl(0), alt(1), super(2)
    shift: bool,            // Shift key state
    timestamp: u64,         // monotonic timestamp (for key repeat detection)
}
```

Size: 16 bytes per key event. At 30 keys/second typing speed: ~480 bytes/second.

### What the Client Sends

The client captures raw hardware key events and sends them as-is:

**macOS client**: Intercepts `keyDown(with: NSEvent)`. Extracts `event.keyCode` (which is a macOS virtual keycode, mapped to HID by the client) and modifier flags.

**iOS client (custom keyboard)**: The built-in software keyboard emits HID keycodes directly. No UITextInput involved.

**iOS client (hardware keyboard)**: Intercepts `pressesBegan(_:with:)`. Extracts `UIKey.keyCode` (HID usage code) and modifier flags.

### Mode Toggle Key

The Korean/English toggle is handled on the server side:

| Platform | Toggle Key | HID Code |
|----------|-----------|----------|
| macOS | 한/영 key (Caps Lock remapped) | 0x39 (Caps Lock) or configurable |
| iOS custom keyboard | Dedicated toggle button | Configurable |
| External | Right Alt (common on Korean keyboards) | 0xE6 |

When the server receives the toggle key:
1. Call `imeContext.toggleMode()` → flush pending composition
2. Send mode indicator in next FrameUpdate
3. Do NOT forward the toggle key to PTY

---

## Server-Side Processing Flow

### Per-Pane Key Event Handler

```zig
fn handleKeyEvent(pane: *Pane, event: KeyEvent) void {
    // 1. Process through IME
    const result = pane.ime_context.processKey(event);

    // 2. Handle committed text
    if (result.committed_text) |text| {
        pane.pty.write(text);  // Write UTF-8 to PTY
    }

    // 3. Handle forwarded key
    if (result.forward_key) |key| {
        const escape_seq = pane.key_encoder.encode(key);
        pane.pty.write(escape_seq);  // Write escape sequence to PTY
    }

    // 4. Update preedit state for display
    if (result.preedit_changed) {
        pane.preedit_text = result.preedit_text;
        pane.markDirty();  // Trigger FrameUpdate to client
    }
}
```

### Integration with Key Encoder

libitshell3-ime handles **text composition** only. Terminal escape sequence encoding (Kitty Keyboard Protocol, application cursor mode, etc.) is handled by libitshell3's key encoder:

```
Key event → libitshell3-ime → committed UTF-8 text → PTY (raw write)
                             → forwarded key → key encoder → escape sequence → PTY
                             → preedit text → FrameUpdate → client display
```

This separation is important: libhangul produces UTF-8 text (e.g., "한"), which is written directly to the PTY. The key encoder produces escape sequences (e.g., `\x1b[C` for right arrow, `\x03` for Ctrl+C), which are also written to the PTY. They never cross paths.

---

## Preedit in FrameUpdate Protocol

### Preedit Fields in FrameUpdate

From `docs/modules/libitshell3/13-render-state-protocol.md`:

```
FrameUpdate {
    ...
    // Preedit (IME composition state)
    preedit_active: bool,
    preedit_text: []u8,         // UTF-8
    preedit_cursor_x: u16,      // cursor position for preedit overlay
    preedit_cursor_y: u16,
    ...
}
```

### Preedit Display on Client

The client renders preedit as a simple overlay:
1. Draw the preedit text at `(preedit_cursor_x, preedit_cursor_y)` with underline decoration.
2. The preedit text overlays the terminal grid cells at the cursor position.
3. When `preedit_active` becomes false, remove the overlay.

This is independent of the cell rendering pipeline — it's a thin overlay, not part of the terminal grid state.

### Preedit Lifecycle

```
1. User starts typing Korean:
   KeyEvent('r') → processKey → preedit="ㄱ"
   → FrameUpdate: preedit_active=true, preedit_text="ㄱ"

2. User continues:
   KeyEvent('k') → processKey → preedit="가"
   → FrameUpdate: preedit_active=true, preedit_text="가"

3. User continues:
   KeyEvent('s') → processKey → preedit="간"
   → FrameUpdate: preedit_active=true, preedit_text="간"

4. User types next syllable:
   KeyEvent('r') → processKey → committed="간", preedit="ㄱ"
   → PTY write: "간" (UTF-8: 0xED 0x95 0x9C... wait, that's wrong)
   → PTY write: "간" (UTF-8: 0xEA 0xB0 0x84)
   → FrameUpdate: preedit_active=true, preedit_text="ㄱ"

5. User presses Enter:
   KeyEvent(Enter) → processKey → committed="ㄱ", forward=Enter
   → PTY write: "ㄱ" (UTF-8: 0xE3 0x84 0xB1)
   → PTY write: "\r"
   → FrameUpdate: preedit_active=false
```

---

## Session Persistence and IME State

### What Gets Saved in Session Snapshots

```json
{
    "panes": [
        {
            "id": 1,
            "ime": {
                "mode": "korean",
                "layout": "dubeolsik",
                "preedit": null
            }
        },
        {
            "id": 2,
            "ime": {
                "mode": "english",
                "layout": "dubeolsik",
                "preedit": null
            }
        }
    ]
}
```

**Important**: Preedit text is NOT saved in snapshots. When restoring a session, all panes start with empty composition. This is the expected behavior — nobody expects to resume mid-syllable after a daemon restart.

What IS saved:
- Input mode (English/Korean) per pane
- Keyboard layout per pane

### Multi-Client Preedit

When multiple clients are attached to the same session:
- Each client sees the same preedit state (it's per-pane on the server).
- Only one client can be the "active input source" per pane at a time.
- If client A is composing and client B sends a key to the same pane, client A's composition is flushed (last-writer-wins).

---

## Mode Indicator Protocol

The server sends the current IME mode in FrameUpdate for the client to display:

```
FrameUpdate {
    ...
    ime_mode: u8,    // 0 = english, 1 = korean
    ...
}
```

The client displays this as a status indicator (e.g., "한" or "A" in the status bar). The exact UI is the app layer's responsibility.

---

## iOS Custom Keyboard Integration

The iOS client uses a built-in custom keyboard that emits HID keycodes:

```
┌─────────────────────────────────────────┐
│              iOS App                     │
│                                          │
│  ┌──────────────────────────────────┐   │
│  │        Terminal View              │   │
│  │     (Metal GPU renderer)          │   │
│  │                                   │   │
│  │   Displays preedit overlay        │   │
│  │   from server FrameUpdate         │   │
│  └──────────────────────────────────┘   │
│                                          │
│  ┌──────────────────────────────────┐   │
│  │     Custom Software Keyboard      │   │
│  │                                   │   │
│  │  ┌───┬───┬───┬───┬───┬───┬───┐  │   │
│  │  │ Q │ W │ E │ R │ T │ Y │...│  │   │
│  │  ├───┼───┼───┼───┼───┼───┼───┤  │   │
│  │  │ A │ S │ D │ F │ G │ H │...│  │   │
│  │  ├───┴┬──┴┬──┴┬──┴┬──┴┬──┴───┤  │   │
│  │  │Shft│ Z │ X │ C │ V │ ...  │  │   │
│  │  ├────┴───┴───┴───┴───┴──────┤  │   │
│  │  │한/영│     Space     │ Enter│  │   │
│  │  └────────────────────────────┘  │   │
│  │                                   │   │
│  │  On key press: send KeyEvent     │   │
│  │  { hid: 0x04, shift: false }     │   │
│  │  via Unix socket to server       │   │
│  └──────────────────────────────────┘   │
└──────────────────────────────────────────┘
```

Key points:
- The keyboard does NOT use iOS UITextInput.
- It does NOT involve iOS's system IME.
- It emits the same HID keycodes as a hardware keyboard.
- The server's libitshell3-ime handles all composition.
- The preedit display comes from the server's FrameUpdate, rendered as an overlay.

This completely sidesteps the iOS async IME problem documented in [01-rationale.md](./01-rationale.md).
