# Handover: IME Interface Contract v0.5 to v0.6

**Date**: 2026-03-05
**Author**: owner

---

## Insights and New Perspectives

### OS IME suppression is a solved problem on both platforms

The macOS IME suppression PoC (`poc/03-macos-ime-suppression/`) proved that a single mechanism — not calling `interpretKeyEvents:` — is sufficient to fully bypass the OS IME. No special tricks, no `inputContext` override, no runtime swizzling. The feared complexity was unfounded.

More importantly, the PoC revealed that **iOS is even cleaner than macOS**:

| | macOS | iOS |
|---|---|---|
| Suppress OS IME | Don't call `interpretKeyEvents:` | Override `inputView` → return empty UIView |
| Capture physical keys | `keyDown:` → `NSEvent.keyCode` (macOS VK) | `pressesBegan` → `UIPress.key.keyCode` (USB HID) |
| VK → HID mapping needed? | **Yes** — macOS uses its own VK space | **No** — iOS gives USB HID keycodes directly |
| System shortcuts | `performKeyEquivalent:` (must return YES to prevent double-fire) | Standard UIResponder chain |
| Clipboard/Services | Implement `NSTextInputClient` (safe, zero interference) | Not needed — handle via `UIPasteboard` directly |
| Custom keyboard | N/A (physical keyboard assumed) | Suppress system soft keyboard → render custom virtual keyboard in-app |

This means the IME contract's `processKey(hid_keycode, shift, modifiers)` interface maps naturally to both platforms — macOS needs one mapping table, iOS needs zero.

### `event.characters` is unreliable, `keyCode` is rock-solid

The PoC tested the same physical keys across three input source states (ABC, Korean-English-sub-mode, Korean-Korean-sub-mode). `event.characters` varied wildly (`a` vs `ㅁ`), but `keyCode` was **identical** every time. This confirms the architectural decision to use physical key position as the canonical input to libitshell3-ime.

Notable finding: Korean 2-Set IM has an internal English/Korean sub-mode toggle (separate from the system input source). This is completely irrelevant for us — we own the toggle via `setActiveInputMethod()`.

### Per-tab engine singleton changes the ownership model

The owner's decision to use one engine instance per tab (not per pane) is an architectural shift. The current contract assumes per-pane ownership throughout (Sections 2, 3, 5, 6). The v0.6 revision needs to rethink:
- **Preedit exclusivity**: Only the focused pane has an active preedit, but the engine is shared. When focus moves to another pane in the same tab, the previous pane's preedit must be committed or cancelled.
- **Session persistence**: One `input_method` per tab, not per pane.
- **Lifecycle**: Engine outlives individual panes — it's tied to the tab lifecycle.

### Backtick → Won sign (₩) under Korean IM

The PoC discovered that macOS remaps the backtick key to ₩ (U+20A9) when the Korean input source is active. Since libitshell3-ime uses the HID keycode (not `event.characters`), this doesn't affect us. But it's a good example of why bypassing `event.characters` was the right call.

---

## Design Philosophy

### "Don't call it" is the best suppression

The simplest possible approach turned out to be the correct one. Both macOS (`interpretKeyEvents:`) and iOS (`inputView`) suppression work by **omission**, not by fighting the framework. This aligns with the project's overall philosophy: own the composition pipeline end-to-end, don't patch around OS behavior.

### Two-layer key capture: shortcuts vs input

Both platforms naturally separate system shortcuts from regular input:
- macOS: `performKeyEquivalent:` (shortcuts) vs `keyDown:` (input)
- iOS: UIResponder key commands vs `pressesBegan` (input)

The production app should consume known shortcuts in the shortcut layer (return YES/true) to prevent double-fire into the input layer. This is a client-app concern, not an IME contract concern.

### Direct mode is sacred

The owner explicitly decided that European dead key composition must be a separate engine (`"european_deadkey"`), not added to direct mode. Direct mode = HID → ASCII passthrough, zero composition, zero state. This principle should be defended in future reviews.

---

## Owner Priorities

1. **Per-tab engine singleton** — the biggest architectural change for v0.6. All panes in a tab share one engine instance and one `input_method` state. This is the natural UX: switching to Korean in one pane should affect the whole tab.

2. **Hanja is excluded, not deferred** — Korean Hanja conversion will never be supported. The candidate callback (Section 7) exists for future Chinese/Japanese engines only. This simplifies the Korean engine scope permanently.

3. **iOS custom virtual keyboard** — the system soft keyboard must be suppressed so the app can render its own virtual keyboard. The `inputView` override approach is confirmed viable. This is a key differentiator for the iPad terminal experience.

4. **Simplicity over completeness** — direct mode stays pure, Korean engine stays focused on Hangul composition only, no feature creep.

---

## New Conventions and Procedures

None introduced in this session.

---

## Pre-Discussion Research Tasks

### 1. iOS keyboard suppression PoC

Build a minimal iOS app to validate:
- `override var inputView: UIView?` returning empty UIView suppresses system keyboard
- `pressesBegan`/`pressesEnded` captures physical keyboard with USB HID keycodes
- Custom UIView can be rendered in the keyboard area
- `canBecomeFirstResponder = true` is sufficient for key event reception

This parallels the macOS PoC and should confirm the iOS column of the platform comparison table above.

### 2. Per-tab engine architecture design

Before revising the contract, the team should sketch the per-tab ownership model:
- Engine lifecycle (create on tab creation, destroy on tab close)
- Focus-change preedit handoff (commit/cancel on pane focus change within same tab)
- Session persistence schema change (`input_method` moves from pane to tab level)
- Protocol impact (which protocol docs need updating beyond the IME contract)
