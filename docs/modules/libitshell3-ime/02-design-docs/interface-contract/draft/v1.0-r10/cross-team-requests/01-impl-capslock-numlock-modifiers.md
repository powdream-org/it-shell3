# Add CapsLock and NumLock to KeyEvent.Modifiers

- **Date**: 2026-03-27
- **Source team**: impl (Plan 5.5 Spec Alignment Audit)
- **Source version**: libitshell3 implementation Plans 1-5
- **Source resolution**: ADR 00059 (CapsLock and NumLock Modifiers in IME
  KeyEvent)
- **Target docs**: `02-types.md` (KeyEvent.Modifiers), `03-engine-interface.md`
  (if affected)
- **Status**: open

---

## Context

ADR 00059 established that the native IME engine must receive CapsLock and
NumLock state in `KeyEvent.Modifiers`. Unlike OS IME systems (ghostty/cmux)
where macOS resolves CapsLock into text before delivery, it-shell3's daemon-side
IME engine receives raw HID keycodes and must resolve CapsLock/NumLock itself.

The wire protocol already defines CapsLock (bit 4) and NumLock (bit 5) in the
modifier byte. The current `KeyEvent.Modifiers` packed struct only has ctrl,
alt, super_key (3 bits + 5 padding), dropping CapsLock/NumLock at the wire
decomposition boundary.

## Required Changes

1. **`02-types.md` — Add caps_lock and num_lock fields to KeyEvent.Modifiers.**
   - **Current**:
     `Modifiers = packed struct(u8) { ctrl, alt, super_key,
     _padding: u5 }`
   - **After**:
     `Modifiers = packed struct(u8) { ctrl, alt, super_key,
     caps_lock, num_lock, _padding: u3 }`
   - **Rationale**: ADR 00059. The IME engine needs CapsLock for direct/English
     mode character case resolution, and NumLock for numpad key classification
     (printable vs navigation).

2. **`02-types.md` — Confirm hasCompositionBreakingModifier() excludes
   CapsLock/NumLock.**
   - CapsLock and NumLock do not break Korean composition. The method should
     continue checking only ctrl, alt, super_key.
   - **Rationale**: CapsLock affects character output but does not interrupt
     Hangul composition. NumLock changes key identity (digit vs navigation) but
     does not break composition either.

3. **`02-types.md` — Add NumLock-aware guidance for isPrintablePosition().**
   - Numpad HID keycodes (0x54-0x63) are printable when NumLock is on,
     navigation when off. The spec should clarify how NumLock interacts with the
     printable position check.
   - **Rationale**: ADR 00059. NumLock determines whether a numpad key enters
     the IME path or bypasses it.

## Summary Table

| Target Doc    | Section/Message                  | Change Type  | Source Resolution |
| ------------- | -------------------------------- | ------------ | ----------------- |
| `02-types.md` | KeyEvent.Modifiers struct        | Add fields   | ADR 00059         |
| `02-types.md` | hasCompositionBreakingModifier() | Confirm      | ADR 00059         |
| `02-types.md` | isPrintablePosition() / NumLock  | Add guidance | ADR 00059         |
