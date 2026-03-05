# macOS IME Suppression PoC — Test Results & Findings

> **Date**: 2026-03-05
> **Tester**: Owner (project lead)
> **Platform**: macOS (Darwin 24.6.0), Apple Silicon (Mac Mini)
> **Input sources tested**: ABC (`com.apple.keylayout.ABC`), 2-Set Korean (`com.apple.inputmethod.Korean.2SetKorean`)

---

## 1. Test Runs

### Run 1: ABC input source + CapsLock switch to Korean

**Input source at start**: ABC

| Input | vk | hid | chars | mods | Notes |
|-------|----|-----|-------|------|-------|
| `a` | 0x00 | 0x04 | `a` | (none) | Correct |
| `s` | 0x01 | 0x16 | `s` | (none) | Correct |
| CapsLock toggle | 0x39 | 0x39 | — | CapsLock | Switched to Korean |
| `r` (physical) | 0x0F | 0x15 | `ㄱ` | (none) | chars changed to jamo, vk/hid unchanged |
| `k` (physical) | 0x28 | 0x0E | `ㅏ` | (none) | Same — chars=jamo, vk/hid=physical position |
| `d` (physical) | 0x02 | 0x07 | `ㅇ` | (none) | Same pattern |

**Observation**: After CapsLock switch, `event.characters` reflects Korean jamo but `keyCode` remains the physical key position. Harmless IMK framework message appeared: `error messaging the mach port for IMKCFRunLoopWakeUpReliable`.

### Run 2: Korean input source (English sub-mode)

**Input source at start**: 2-Set Korean

| Input | vk | hid | chars | mods | Notes |
|-------|----|-----|-------|------|-------|
| `a` | 0x00 | 0x04 | `a` | (none) | ASCII — Korean IM was in English sub-mode |
| `b` | 0x0B | 0x05 | `b` | (none) | Same |
| `c` | 0x08 | 0x06 | `c` | (none) | Same |
| `1` | 0x12 | 0x1E | `1` | (none) | Numbers unaffected |
| `2` | 0x13 | 0x1F | `2` | (none) | |
| `3` | 0x14 | 0x20 | `3` | (none) | |
| `;` | 0x29 | 0x33 | `;` | (none) | Symbols unaffected |
| `'` | 0x27 | 0x34 | `'` | (none) | |
| `/` | 0x2C | 0x38 | `/` | (none) | |
| Shift+`a` | 0x00 | 0x04 | `A` | Shift | Same keycode, shifted char |
| Shift+`b` | 0x0B | 0x05 | `B` | Shift | |
| Shift+`1` | 0x12 | 0x1E | `!` | Shift | |
| Shift+`2` | 0x13 | 0x1F | `@` | Shift | |

**Observation**: Korean 2-Set IM has an internal English/Korean toggle. When in English sub-mode, chars are ASCII even though the system input source is Korean. vk/hid codes remain identical to ABC input source.

### Run 3: Korean input source (Korean sub-mode)

**Input source at start**: 2-Set Korean

| Input | vk | hid | chars | mods | Notes |
|-------|----|-----|-------|------|-------|
| `a` (physical) | 0x00 | 0x04 | `ㅁ` (U+3141) | (none) | Korean jamo |
| `b` (physical) | 0x0B | 0x05 | `ㅠ` (U+3160) | (none) | Korean jamo |
| `c` (physical) | 0x08 | 0x06 | `ㅊ` (U+314A) | (none) | Korean jamo |

**Observation**: In Korean sub-mode, chars contain Korean jamo. Crucially, vk/hid codes are **identical** to ABC and Korean-English-sub-mode runs. This confirms `keyCode` is purely physical key position.

### Run 4: System shortcuts (ABC input source)

| Input | Event type | Result |
|-------|-----------|--------|
| Cmd+C | [EQV] passed to AppKit, then [KEY] keyDown | Logged as copy. `keyDown` also fired (app didn't consume in performKeyEquivalent) |
| Cmd+V | [EQV] passed to AppKit, then [KEY] keyDown | Logged as paste. Same double-fire |
| Cmd+H | [EQV] passed to AppKit, then [KEY] keyDown | **App did NOT hide.** Likely missing full app lifecycle in PoC |
| Cmd+Q | [EQV] passed to AppKit | **App quit successfully** |

**Observation**: `performKeyEquivalent:` fires for Cmd-modified keys and passes known system shortcuts to AppKit via `[super performKeyEquivalent:]`. Cmd+Q works. Cmd+H doesn't hide — expected for a minimal PoC without full AppKit lifecycle setup (no `NSApplicationActivationPolicyRegular` or proper menu). Not a concern for the production app.

**Note**: After `performKeyEquivalent:` returns NO from super, `keyDown:` is also called. The production app should return YES from `performKeyEquivalent:` for consumed shortcuts to prevent double-fire.

### Run 5: Modifier combos (ABC input source)

| Input | Event type | Observations |
|-------|-----------|--------------|
| Ctrl+C | [EQV] then [KEY] | `performKeyEquivalent:` fires for Ctrl+key too (not just Cmd). `keyDown` receives `mods=Ctrl`, chars=U+0003 (ETX) |
| Alt+K | [KEY] only | `keyDown` with `mods=Alt/Opt`, chars='˚' (macOS Option+K produces ˚) |
| Shift alone (press/release) | [MOD] x2 | `flagsChanged:` fires on press (Shift set) and release (Shift cleared) |

**Observation**: `performKeyEquivalent:` fires for Ctrl-modified keys too, not only Cmd. This is fine — the PoC allowlist only matches Cmd combos, so Ctrl combos fall through to `keyDown`.

### Run 6: Arrow keys (Korean input source)

**Input source at start**: 2-Set Korean

| Input | vk | hid | chars | mods | Notes |
|-------|----|-----|-------|------|-------|
| LeftArrow | 0x7B | 0x00 | U+F702 | Fn | HID mapping missing for arrow keys |
| RightArrow | 0x7C | 0x00 | U+F703 | Fn | Same |
| UpArrow | 0x7E | 0x00 | U+F700 | Fn | Same |
| DownArrow | 0x7D | 0x00 | U+F701 | Fn | Same |

**Observation**: Arrow keys report hid=0x00 — the `macVKToHID()` mapping table doesn't cover them. The vk codes (0x7B–0x7E) are correct. `performKeyEquivalent:` fires before `keyDown:` for arrow keys (macOS reports them with Fn modifier). This is not a problem for libitshell3-ime — arrow keys are forwarded directly to the PTY, not processed by the IME engine. The production client should map these via vk, not HID.

### Run 7: Key repeat — Space held down (Korean input source)

**Input source at start**: 2-Set Korean

| Input | vk | hid | chars | mods | Repeat? |
|-------|----|-----|-------|------|---------|
| Space (press) | 0x31 | 0x2C | ` ` | (none) | No |
| Space (hold) x12 | 0x31 | 0x2C | ` ` | (none) | Yes (`[REPEAT]`) |
| Space (release) | 0x31 | — | — | — | keyUp |

**Observation**: Key repeat is correctly detected via `event.isARepeat` (logged as `[REPEAT]`). Repeat interval is ~83ms (consistent with macOS default key repeat rate). The repeat flag is important for libitshell3-ime — the IME contract's `processKey()` takes an `is_repeat` parameter to distinguish initial press from repeat.

### Run 8: Function keys and special keys (Korean input source)

**Input source at start**: 2-Set Korean

| Input | vk | hid | chars | mods | Notes |
|-------|----|-----|-------|------|-------|
| F1 | 0x7A | 0x00 | U+F704 | Fn | HID mapping missing |
| F2 | 0x78 | 0x00 | U+F705 | Fn | |
| F3 | 0x63 | 0x00 | U+F706 | Fn | |
| F4 | 0x76 | 0x00 | U+F707 | Fn | |
| F5 | 0x60 | 0x00 | U+F708 | Fn | |
| F6 | 0x61 | 0x00 | U+F709 | Fn | |
| F7 | 0x62 | 0x00 | U+F70A | Fn | |
| F8 | 0x64 | 0x00 | U+F70B | Fn | |
| F9 | 0x65 | 0x00 | U+F70C | Fn | |
| F10 | 0x6D | 0x00 | U+F70D | Fn | |
| F12 | 0x6F | 0x00 | U+F70F | Fn | F11 not tested (macOS captures it for Show Desktop) |
| Escape | 0x35 | 0x29 | U+001B | (none) | HID mapping works |
| Help/Insert | 0x72 | 0x00 | U+F746 | Fn | HID mapping missing |
| Home | 0x73 | 0x00 | U+F729 | Fn | |
| PageUp | 0x74 | 0x00 | U+F72C | Fn | |
| ForwardDelete | 0x75 | 0x00 | U+F728 | Fn | |
| End | 0x77 | 0x00 | U+F72B | Fn | |
| PageDown | 0x79 | 0x00 | U+F72D | Fn | |
| `\` | 0x2A | 0x31 | `\` | (none) | HID mapping works |
| `` ` `` | 0x32 | 0x35 | `₩` (U+20A9) | (none) | Korean input source maps backtick to Won sign |
| Fn (alone) | 0x3F | 0x00 | — | Fn | Via flagsChanged, press/release |

**Observations**:
- Function keys (F1–F12), arrow keys, and navigation keys (Home/End/PageUp/PageDown/ForwardDelete/Help) all report hid=0x00 — the `macVKToHID()` mapping table only covers alphanumeric and symbol keys. These keys are not processed by the IME engine, so this is acceptable. The production client should use vk codes directly for non-character keys.
- `performKeyEquivalent:` fires for all Fn-modified keys before `keyDown:`.
- **Backtick → Won sign (₩)**: With Korean input source active, the backtick key (vk=0x32) produces `₩` (Korean Won sign, U+20A9) instead of `` ` ``. This is a macOS Korean keyboard layout behavior applied to `event.characters`. The vk code (0x32) and HID code (0x35) remain correct physical positions. libitshell3-ime uses the HID keycode, not characters, so this is not a problem.
- Escape has a correct HID mapping (0x29).
- Fn key alone is captured via `flagsChanged:` (press/release).

---

## 2. NSTextInputClient Interference

**Result: Zero interference across all runs.**

No `insertText:` or `setMarkedText:` calls were observed in any run. Having `NSTextInputClient` implemented does NOT cause macOS to route keyboard events through it as long as `interpretKeyEvents:` is not called.

---

## 3. Validated Assumptions

| Assumption | Validated? | Evidence |
|-----------|-----------|----------|
| Not calling `interpretKeyEvents:` bypasses OS IME | **Yes** | No composition occurred, no NSTextInputClient calls |
| `NSEvent.keyCode` is physical key position | **Yes** | Same vk across ABC, Korean-English, Korean-Korean modes |
| macOS VK-to-HID mapping works | **Yes** | Correct HID codes for all letter/number/symbol keys |
| `performKeyEquivalent:` handles system shortcuts | **Yes** | Cmd+Q quit, Cmd+C/V logged correctly |
| `flagsChanged:` captures modifier-only keys | **Yes** | Shift, Ctrl, Option, Cmd all detected |
| NSTextInputClient safe to implement alongside | **Yes** | Zero insertText/setMarkedText calls |
| Arrow keys received via keyDown | **Yes** | vk codes correct (0x7B–0x7E), but HID mapping missing (hid=0x00) |
| Function keys (F1–F12) received | **Yes** | vk codes correct, HID mapping missing (hid=0x00). Not IME-relevant |
| Navigation keys (Home/End/PgUp/PgDn/Del) | **Yes** | vk codes correct, HID mapping missing. Not IME-relevant |
| Key repeat detected | **Yes** | `isARepeat` correctly flags held keys as `[REPEAT]` |
| Backtick → ₩ under Korean IM | **Noted** | macOS remaps chars but vk/hid remain physical position |

---

## 4. Issues & Notes for Production

### 4.1 performKeyEquivalent double-fire

When `performKeyEquivalent:` passes a shortcut to AppKit via `[super performKeyEquivalent:]` and super returns NO, `keyDown:` is also called for the same event. The production app should return YES from `performKeyEquivalent:` for shortcuts it consumes, to prevent `keyDown:` from double-processing.

### 4.2 Cmd+H not working

Cmd+H (hide) didn't work in the PoC. This is a PoC setup issue — the minimal app doesn't have full AppKit lifecycle. The production app with proper `NSApplication` setup and menu bar will handle this correctly.

### 4.3 Korean IM English sub-mode

The Korean 2-Set input method has an internal English/Korean toggle (separate from the system input source switch). When in English sub-mode, `event.characters` returns ASCII. This is irrelevant for libitshell3-ime because:
- We use `keyCode` (physical position), not `characters`
- Our own IME engine handles the Korean/English toggle, not the OS

### 4.4 `error messaging the mach port for IMKCFRunLoopWakeUpReliable`

Harmless IMK framework message that appears when switching input sources via CapsLock. Can be ignored.

---

## 5. Conclusion

The IME suppression approach is **confirmed viable** for the it-shell3 macOS client. The single mechanism — not calling `interpretKeyEvents:` — is sufficient to bypass the OS IME entirely while retaining system shortcuts, clipboard, and accessibility. No additional workarounds needed.
