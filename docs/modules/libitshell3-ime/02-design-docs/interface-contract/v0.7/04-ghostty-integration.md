# IME Interface Contract v0.7 — ghostty Integration

> **Version**: v0.7
> **Date**: 2026-03-07
> **Part of the IME Interface Contract v0.7. See [01-overview.md](01-overview.md) for the document index.**
> **Changes from v0.6**: See [Appendix I: Changes from v0.6](99-appendices.md#appendix-i-changes-from-v06)

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

The daemon's key handler translates `ImeResult` into ghostty calls. Every `ghostty_surface_key()` press event **MUST** be followed by a corresponding release event. The release event has `.action = .release` and `.text = null` (no text on release — re-sending text would double-commit).

The engine is session-scoped. `session.engine` holds the single shared engine. The server tracks `focused_pane` and directs `ImeResult` output to that pane's PTY and surface.

```zig
fn handleKeyEvent(session: *Session, focused_pane: *Pane, key: KeyEvent) void {
    const result = session.engine.processKey(key);

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
        ghostty_surface_key(focused_pane.surface, ghost_key);

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
        ghostty_surface_key(focused_pane.surface, release_key);
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
            ghostty_surface_preedit(focused_pane.surface, text.ptr, text.len);
        } else {
            ghostty_surface_preedit(focused_pane.surface, null, 0); // explicit clear required
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
        ghostty_surface_key(focused_pane.surface, ghost_key);

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
        ghostty_surface_key(focused_pane.surface, release_key);
    }
}
```

### Intra-Session Pane Focus Change

When focus moves from pane A to pane B within the same session, the server flushes the engine and routes the result to pane A before switching focus:

```zig
fn handleIntraSessionFocusChange(session: *Session, pane_a: *Pane, pane_b: *Pane) void {
    // 1. Flush composition — committed text goes to pane A's PTY
    const result = session.engine.flush();

    // 2. Consume result immediately (MUST happen before next engine call)
    if (result.committed_text) |text| {
        const ghost_key = ghostty_input_key_s{
            .action = .press,
            .mods = .{},
            .consumed_mods = .{},
            .keycode = .unidentified,
            .text = text.ptr,
            .unshifted_codepoint = 0,
            .composing = false,
        };
        ghostty_surface_key(pane_a.surface, ghost_key);
        const release_key = ghostty_input_key_s{ .action = .release, .mods = .{}, .consumed_mods = .{}, .keycode = .unidentified, .text = null, .unshifted_codepoint = 0, .composing = false };
        ghostty_surface_key(pane_a.surface, release_key);
    }
    if (result.preedit_changed) {
        ghostty_surface_preedit(pane_a.surface, null, 0); // clear pane A's preedit overlay
    }

    // 3. Send PreeditEnd(pane=A, reason="focus_changed") to all clients
    //    (immediate delivery, bypasses coalescing -- per doc 05 Section 7.7)
    sendPreeditEnd(pane_a, "focus_changed");

    // 4. Update focused pane -- subsequent processKey() results route to pane B
    session.focused_pane = pane_b;
}
```

**Edge case — engine already empty**: `flush()` returns `ImeResult{}` (all null/false). The server skips the ghostty calls. The path is uniform regardless of composition state.

**Key invariant**: The server MUST consume `ImeResult` (process `committed_text` and update preedit) before making any subsequent call to the same engine instance. See [Section 6](#6-memory-ownership) for the shared engine memory ownership invariant.

### Keycode criticality by event type:

| Event Type | `.text` field | Keycode impact |
|---|---|---|
| Committed text | Non-empty | **Non-critical** — ghostty uses `.text` for PTY output |
| Forwarded key (control/special) | null | **Critical** — ghostty uses keycode for escape sequence encoding |
| Forwarded Space | `" "` | **Non-critical** — ghostty uses `.text` for the space character |
| Language switch flush | Non-empty | **Non-critical** — use `.unidentified` (no originating key) |
| Intra-session pane switch flush | Non-empty | **Non-critical** — use `.unidentified` (no originating key) |

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
fn handleInputMethodSwitch(session: *Session, new_method: []const u8) void {
    const result = session.engine.setActiveInputMethod(new_method) catch |err| switch (err) {
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
        ghostty_surface_key(session.focused_pane.surface, ghost_key);

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
        ghostty_surface_key(session.focused_pane.surface, release_key);
    }

    if (result.preedit_changed) {
        ghostty_surface_preedit(session.focused_pane.surface, null, 0); // always clear on switch
    }

    // Update FrameUpdate metadata for input method indicator
    session.markDirty();
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

ghostty's Surface has **zero** language-related state. There are no `language`, `locale`, or `ime` fields anywhere in Surface or the renderer. The language indicator shown to the user (e.g., "한" or "A" in the status bar) is derived by libitshell3 from the engine's `active_input_method` string and sent as metadata in FrameUpdate. ghostty does not need to know or care about the active input method.

### Focus Change and Language Preservation

When a session loses focus (`deactivate`), the engine flushes composition and returns ImeResult. The `active_input_method` field is **not** changed. When the same session regains focus (`activate`), it's still in the same input method (e.g., `"korean_2set"`). This is entirely internal to the engine — ghostty's Surface has no concept of IME state.

Users expect that switching between tabs and coming back preserves their input mode. The engine's `active_input_method` persists across deactivate/activate cycles.

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

### macOS and iOS Client IME Suppression (PoC Validated)

The macOS client MUST NOT call `interpretKeyEvents:` for keyboard input — it sends raw keycodes to the daemon instead. The iOS client suppresses the system soft keyboard using `inputView` override. Both approaches have been validated by PoC.

| | macOS | iOS |
|---|---|---|
| Suppress OS IME | Don't call `interpretKeyEvents:` | Override `inputView` → return empty UIView |
| Capture physical keys | `keyDown:` → `NSEvent.keyCode` (macOS VK) | `pressesBegan` → `UIPress.key.keyCode` (USB HID) |
| VK → HID mapping needed? | **Yes** — macOS uses its own VK space | **No** — iOS gives USB HID keycodes directly |
| System shortcuts | `performKeyEquivalent:` (must return YES to prevent double-fire) | Standard UIResponder chain |
| Clipboard/Services | Implement `NSTextInputClient` (safe, zero interference) | Handle via `UIPasteboard` directly |

Key findings:
- `event.characters` is unreliable across input sources; `keyCode` is rock-solid.
- The `processKey(hid_keycode, shift, modifiers)` interface maps naturally to both platforms: macOS needs one mapping table (VK → HID), iOS needs zero.
- Korean 2-Set IM has an internal English/Korean sub-mode toggle that is irrelevant — our engine owns the toggle via `setActiveInputMethod()`.

This is a client-app concern. It is documented here because it validates the contract's `KeyEvent` design (physical HID keycode as input). See `poc/03-macos-ime-suppression/` for the PoC source.

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

**Caller responsibility**: If the caller needs to retain the text across multiple `processKey()` calls, it must copy the data. In practice, the daemon's Phase 2 (ghostty integration) immediately consumes the text by calling `ghostty_surface_key()` or `ghostty_surface_preedit()`, so no copying is needed.

### Shared Engine Invariant

When multiple panes share a single engine instance (per-session ownership), the caller MUST consume the `ImeResult` (process `committed_text` via `ghostty_surface_key`, update preedit via `ghostty_surface_preedit`) before making any subsequent call to the same engine instance. This is required because the next call overwrites the engine's internal buffers.

In practice, this is satisfied naturally: the server processes one key event at a time on the main thread, and `ImeResult` consumption is synchronous within the key handling path. The `handleKeyEvent` and `handleIntraSessionFocusChange` code patterns in [Section 5](#5-ghostty-integration) already comply with this invariant.
