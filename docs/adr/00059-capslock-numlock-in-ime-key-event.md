# 00059. CapsLock and NumLock Modifiers in IME KeyEvent

- Date: 2026-03-27
- Status: Accepted

## Context

it-shell3 uses a native Zig IME engine (libitshell3-ime) that receives raw HID
keycodes over the wire protocol. This is fundamentally different from OS IME
systems (used by ghostty and cmux) where macOS resolves CapsLock into the
delivered text before the application sees it — `NSEvent.characters` already
contains 'A' when CapsLock is active.

In it-shell3's architecture:

1. The client app captures the raw key event from the OS
2. The client sends HID keycode + modifier byte over the wire to the daemon
3. The daemon's native IME engine processes the raw keycode
4. The IME engine must produce the correct character output

The wire protocol defines a modifier byte with 6 bits including CapsLock (bit 4)
and NumLock (bit 5). However, the IME interface contract (`KeyEvent.Modifiers`)
only defines 3 modifier fields: ctrl, alt, super_key. CapsLock and NumLock are
absent.

Without CapsLock in KeyEvent, the IME engine cannot distinguish:

- 'a' key + CapsLock on → should produce 'A' (direct/English mode)
- 'a' key + CapsLock on + Shift → should produce 'a' (toggle inversion)

Without NumLock in KeyEvent, the IME engine cannot distinguish:

- Numpad 1 (HID 0x59) + NumLock on → '1' (printable, IME processes)
- Numpad 1 (HID 0x59) + NumLock off → End key (navigation, IME bypasses)

The wire decomposition code (`wire_decompose.zig`) currently drops bits 4-5,
making these distinctions impossible at the IME layer.

Investigation of ghostty's source confirmed that ghostty's `Mods` packed struct
includes `caps_lock` (bit 4) and `num_lock` (bit 5), with the wire protocol bit
positions being identical. ghostty drops these for keybinding and legacy
encoding but preserves them for Kitty protocol. However, ghostty relies on the
OS to resolve CapsLock into text — a luxury the daemon-side IME engine does not
have.

## Decision

Add `caps_lock: bool` and `num_lock: bool` fields to `KeyEvent.Modifiers` in the
IME interface contract. The packed struct changes from 3 used bits to 5:

- bit 0: ctrl
- bit 1: alt
- bit 2: super_key
- bit 3: caps_lock
- bit 4: num_lock
- bits 5-7: padding

This aligns with the wire protocol modifier byte layout (bits 1-5 map to the
same modifiers, with bit 0 being Shift which is already a separate field on
KeyEvent).

The IME engine must use these fields for:

- Direct/English mode character resolution (CapsLock affects letter case)
- NumLock-aware numpad key classification (printable vs navigation)
- `hasCompositionBreakingModifier()` does NOT include CapsLock/NumLock (they do
  not break Korean composition)

## Consequences

**What gets easier:**

- Correct English/direct mode output — CapsLock produces uppercase letters
  without relying on OS text resolution
- Numpad key handling — NumLock state determines whether a numpad key is
  printable (IME processes) or navigation (IME bypasses)
- Wire-to-KeyEvent mapping becomes lossless — all 6 defined modifier bits are
  preserved

**What gets harder:**

- IME engine complexity increases — must implement CapsLock toggle logic
  (CapsLock + Shift = lowercase) and NumLock-dependent key classification
- More test surface — CapsLock × Shift × letter keys, NumLock × numpad keys

**New obligations:**

- IME interface-contract spec must be revised to add the fields
- `wire_decompose.zig` must preserve bits 4-5 instead of dropping them
- libitshell3-ime engine must implement CapsLock/NumLock-aware key resolution
- `isPrintablePosition()` may need NumLock-aware logic for numpad HID range
