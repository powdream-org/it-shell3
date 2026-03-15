# Mouse Event and Preedit Interaction Gap

- **Date**: 2026-03-16
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: daemon design docs
- **Status**: open

---

## Context

The protocol spec (Doc 04 §2.3 and Doc 05 §6.10) defined a rule: when a
MouseButton event arrives while preedit is active, the server MUST commit
preedit before processing the mouse event. This rule has been removed from the
protocol spec as it is daemon implementation behavior.

However, the current daemon design docs state that "mouse events bypass IME
entirely" (Doc 01 internal architecture, Doc 02 integration boundaries §4.8).
This creates a gap — if mouse events truly bypass IME, then the preedit commit
on MouseButton click does not happen, and the user's in-progress composition
would remain active after clicking elsewhere in the terminal.

The daemon team should resolve this gap: either mouse events need to check for
active preedit and commit before processing, or the "bypass IME entirely"
statement needs qualification.

## Required Changes

1. Resolve the gap between "mouse bypasses IME" and "MouseButton should commit
   preedit". The expected behavior is that MouseButton commits preedit (cursor
   position changes), while MouseScroll does not (viewport-only operation).
2. Update the mouse event data flow to include a preedit check before PTY
   forwarding.

## Summary Table

| Target Doc             | Section/Message       | Change Type | Source Resolution             |
| ---------------------- | --------------------- | ----------- | ----------------------------- |
| Internal architecture  | Mouse event data flow | Update      | Protocol v1.0-r12 Doc 04 §2.3 |
| Integration boundaries | §4.8 Mouse Event Flow | Update      | Protocol v1.0-r12 Doc 04 §2.3 |

## Reference: Original Protocol Text (removed from Doc 04 §2.3)

The following is the original text as it appeared in the protocol spec before
removal. Provided as reference for the daemon team — adapt as needed.

### Preedit interaction (MouseButton)

> **Normative — Preedit interaction**: If preedit is active when a MouseButton
> event arrives, the server MUST commit preedit before processing the mouse
> event. The server sends `PreeditEnd` with `reason="committed"` and the
> committed text is written to the PTY, then forwards the mouse event. See doc
> 05 Section 6 for the normative rules on mouse event interaction with active
> preedit.

### MouseScroll behavior (from Doc 05 §6.10)

MouseScroll (0x0204) is a viewport-only operation. The server MUST NOT commit
preedit on scroll. The user's in-progress composition MUST be preserved.
