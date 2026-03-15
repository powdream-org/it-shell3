# Move Korean Composition Example from Protocol to Daemon

- **Date**: 2026-03-16
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: daemon design docs (internal architecture or integration
  boundaries)
- **Status**: open

---

## Context

During owner review of the protocol spec (v1.0-r12), the step-by-step Korean
"한" composition example in Doc 04 §2.1 was identified as daemon implementation
detail. The example describes server-side IME processing (HID keycode → jamo
mapping → composition → preedit emission), which is daemon-internal behavior.
The protocol spec only needs to define the KeyEvent wire format.

## Required Changes

1. Add a step-by-step Korean composition example showing the daemon's IME
   processing pipeline: KeyEvent reception → IME engine processKey() → preedit
   emission → FrameUpdate with preedit cells.

## Summary Table

| Target Doc            | Section/Message        | Change Type | Source Resolution             |
| --------------------- | ---------------------- | ----------- | ----------------------------- |
| Internal architecture | IME processing example | Add         | Protocol v1.0-r12 Doc 04 §2.1 |

## Reference: Original Protocol Text (removed from Doc 04 §2.1)

The following is the original text as it appeared in the protocol spec before
removal. Provided as reference for the daemon team — adapt as needed.

### Example: Typing Korean "한"

```
1. User presses 'H' key (HID 0x0B), input_method=korean_2set
   KeyEvent: {"keycode": 11, "action": 0, "modifiers": 0, "input_method": "korean_2set"}
   Server IME: maps H -> ㅎ, enters composing state, emits preedit "ㅎ"

2. User presses 'A' key (HID 0x04)
   KeyEvent: {"keycode": 4, "action": 0, "modifiers": 0, "input_method": "korean_2set"}
   Server IME: maps A -> ㅏ, composes ㅎ+ㅏ=하, emits preedit "하"

3. User presses 'N' key (HID 0x11)
   KeyEvent: {"keycode": 17, "action": 0, "modifiers": 0, "input_method": "korean_2set"}
   Server IME: maps N -> ㄴ, composes 하+ㄴ=한, emits preedit "한"

4. User presses Space (HID 0x2C), commits
   KeyEvent: {"keycode": 44, "action": 0, "modifiers": 0, "input_method": "korean_2set"}
   Server IME: commits "한" to PTY, clears preedit
```

Note: The client sends identical KeyEvent messages regardless of whether
composition is active. The server's IME engine tracks composition state
internally.
