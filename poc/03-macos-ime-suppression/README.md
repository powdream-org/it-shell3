# macOS IME Suppression PoC

Validates that the it-shell3 macOS client can bypass the OS IME system entirely while retaining system shortcuts, clipboard, and accessibility.

## Background

The it-shell3 project uses a native Zig IME engine (libitshell3-ime) for Korean Hangul composition. The macOS client must:

1. Capture raw keycodes directly, bypassing `interpretKeyEvents:` (which routes through macOS's IME system)
2. Still allow system shortcuts (Cmd+Q, Cmd+H, etc.) via `performKeyEquivalent:`
3. Implement `NSTextInputClient` for clipboard/services/accessibility, but NOT for keyboard input

## What This PoC Tests

### Test 1: Raw keycode capture

The view overrides `keyDown:` directly and does NOT call `[self interpretKeyEvents:@[event]]`. This is the fundamental mechanism for bypassing the OS IME.

**What to verify:**
- Letters a-z produce correct macOS virtual keycodes and HID keycodes
- Shift+letter produces shifted characters (A-Z) with the same keycode
- When the macOS input source is Korean, the `keyCode` is unchanged (physical key position), but `event.characters` may differ
- Number keys, symbols, and punctuation all produce correct keycodes

### Test 2: System shortcuts via performKeyEquivalent

`performKeyEquivalent:` is called before `keyDown:` for Cmd-modified keys. The PoC passes known system shortcuts (Cmd+Q/H/W/C/V/X/A/M) through to AppKit and consumes other Cmd combinations.

**What to verify:**
- Cmd+Q quits the app (handled by AppKit menu)
- Cmd+H hides the app
- Cmd+C/V/X work for clipboard (via Edit menu)
- Other Cmd combos are logged and consumed

### Test 3: NSTextInputClient for non-keyboard services

The view implements `NSTextInputClient` protocol with minimal methods. The PoC tracks how many times `insertText:`, `setMarkedText:`, and `hasMarkedText` are called.

**What to verify:**
- During keyboard input, `insertText:` call count remains 0
- During keyboard input, `setMarkedText:` call count remains 0
- The `hasMarkedText` call count may increase (macOS queries this proactively), but this is harmless since we always return NO

### Test 4: No interference

The PoC validates that having `NSTextInputClient` implemented does NOT cause macOS to route keyboard events through it when `interpretKeyEvents:` is not called.

**What to verify:**
- The stats line at the top shows green (zero insertText/setMarkedText calls)
- If the stats line turns red, it means macOS routed keyboard input through NSTextInputClient despite not calling interpretKeyEvents: -- this would be a problem

### Test 5: Modifier keys via flagsChanged

Modifier-only key events (pressing/releasing Shift, Ctrl, Alt, Cmd without another key) are delivered via `flagsChanged:`, not `keyDown:`.

**What to verify:**
- Pressing and releasing Shift alone produces two flagsChanged events (press with Shift flag set, release with Shift flag cleared)
- Same for Ctrl, Alt/Option, Cmd

## Build

```bash
./build.sh
```

Or manually:

```bash
cc -fobjc-arc PoC.m -framework Foundation -framework AppKit -framework Carbon -o poc-ime-suppression
```

## Run

```bash
./poc-ime-suppression
```

A window appears showing:
- Current macOS input source (updates every 2 seconds)
- NSTextInputClient call count stats (green = good, red = interference detected)
- Log of all key events, color-coded:
  - **Green**: `keyDown:` events (raw keycode capture)
  - **Orange**: `flagsChanged:` events (modifier-only keys)
  - **Blue**: `performKeyEquivalent:` events (system shortcuts)
  - **Red**: `NSTextInputClient` method calls (should not appear during keyboard input)

Full logs are also written to the Terminal via `NSLog`.

## Test Procedure

### Step 1: English input source
1. Ensure macOS input source is set to "U.S." or "ABC"
2. Type: `a`, `b`, `c`, `1`, `2`, `3`, `;`, `'`, `/`
3. Verify green log entries show correct keycodes and characters
4. Hold Shift and type: `A`, `B`, `!`, `@`
5. Verify same keycodes but shifted characters

### Step 2: Korean input source
1. Switch macOS input source to "2-Set Korean" (Press Ctrl+Space or use menu bar)
2. The header should update to show Korean input source
3. Type the same physical keys: `a`, `b`, `c` (physical position)
4. **Expected**: `keyCode` values are identical to Step 1 (they are physical key positions)
5. **Expected**: `characters` may show Korean jamo IF macOS translates them, OR may show same ASCII characters. Either way, the `keyCode` is what matters for libitshell3-ime
6. **Critical**: `insertText:` and `setMarkedText:` call counts must remain 0

### Step 3: System shortcuts
1. Press Cmd+C -- verify blue log entry and clipboard copy attempt
2. Press Cmd+V -- verify blue log entry and paste attempt
3. Press Cmd+H -- app should hide
4. Press Cmd+Q -- app should quit

### Step 4: Modifier combos
1. Press Ctrl+C -- verify green `keyDown` with Ctrl modifier (NOT performKeyEquivalent, since no Cmd)
2. Press Alt+key -- verify green `keyDown` with Alt/Opt modifier
3. Press Shift alone (press and release) -- verify orange `flagsChanged` entries

## Key Findings for it-shell3

### macOS keyCode is physical key position
`NSEvent.keyCode` represents the physical key position, not the character. This is exactly what libitshell3-ime needs: HID keycodes represent physical positions, and the IME engine maps them to characters based on the active input method.

### macOS keyCode != HID keycode
macOS uses its own virtual keycode space (defined in `<Carbon/HIToolbox/Events.h>`). These must be mapped to USB HID keycodes for the IME contract. The PoC includes a complete `macVKToHID()` mapping table.

### Not calling interpretKeyEvents is sufficient
Simply not calling `[self interpretKeyEvents:@[event]]` in `keyDown:` is enough to prevent macOS from routing keyboard input through the OS IME. No need to:
- Return nil from `inputContext`
- Override `inputContext` at all
- Use any other suppression technique

### NSTextInputClient is safe to implement
Having `NSTextInputClient` methods implemented does not cause interference. macOS only routes events through these methods when `interpretKeyEvents:` is called.

### event.characters with Korean input source
When the macOS input source is Korean, `event.characters` may contain Korean jamo characters. However, since libitshell3-ime handles composition natively using the physical keycode + shift state, the `characters` field is informational only. The `keyCode` field is the authoritative input.

## Relation to it-shell3 Architecture

```
NSEvent (keyDown:)
    |
    v
macOS keyCode + modifiers
    |
    v
macVKToHID() mapping         <-- This PoC validates this layer
    |
    v
HID keycode (u8) + modifiers
    |
    v
libitshell3-ime processKey()  <-- IME contract (separate PoC)
    |
    v
ImeResult { committed, preedit, forward_key, ... }
    |
    v
ghostty surface API           <-- ime-ghostty-real PoC validates this
```

This PoC validates the top half of the pipeline: raw keycode capture from macOS without OS IME interference.

## Files

- `PoC.m` -- Single-file Objective-C application
- `build.sh` -- Build script
- `README.md` -- This file
