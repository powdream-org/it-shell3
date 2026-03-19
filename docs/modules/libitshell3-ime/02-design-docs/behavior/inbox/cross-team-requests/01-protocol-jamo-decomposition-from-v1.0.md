# Backspace Role in Jamo Decomposition

- **Date**: 2026-03-18
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: IME behavior docs (processKey algorithm, Hangul engine
  internals)
- **Status**: open

---

## Context

During owner review of the protocol spec (v1.0-r12), the HID keycode table in
Doc 04 §2.1 was found to include an inline note marking Backspace (HID `0x2A`)
as "Critical for Jamo decomposition." This annotation is not a wire protocol
concern — it is IME engine behavior. The protocol spec only defines that
Backspace is a valid HID keycode that the client sends; what the engine does
with it is entirely the IME team's responsibility.

The note was removed from the protocol spec as part of the v1.0-r12 cleanup. The
IME behavior docs should explicitly document the Backspace handling role in Jamo
decomposition so this knowledge is not lost.

## Required Changes

1. **`01-processKey-algorithm.md` — Backspace handling**: Add an explicit
   section or callout documenting that Backspace (HID `0x2A`) is critical for
   Jamo decomposition. The processKey algorithm must handle Backspace as a
   decomposition trigger: when the engine receives Backspace while a jamo
   syllable is being composed, it decomposes the last composed jamo rather than
   deleting the preceding character. Document the exact decomposition behavior
   (e.g., final jamo removed first, then initial/medial, until the syllable
   block is fully decomposed and then a true delete occurs).

2. **`10-hangul-engine-internals.md` — Jamo stack and Backspace**: Document that
   the `HangulInputContext` jamo stack is affected by Backspace: receiving
   Backspace during active composition pops the jamo stack by one step. Clarify
   how the engine distinguishes "Backspace during composition" (jamo
   decomposition) from "Backspace with empty composition" (forwarded to PTY as a
   raw delete).

## Summary Table

| Target Doc                      | Section/Message            | Change Type | Source Resolution             |
| ------------------------------- | -------------------------- | ----------- | ----------------------------- |
| `01-processkey-algorithm.md`    | Backspace handling         | Add         | Protocol v1.0-r12 Doc 04 §2.1 |
| `10-hangul-engine-internals.md` | Jamo stack, Backspace path | Add         | Protocol v1.0-r12 Doc 04 §2.1 |

## Reference: Original Protocol Text (removed from Doc 04 §2.1)

The following is the original text as it appeared in the protocol spec before
removal. Provided as reference for the IME behavior team — adapt as needed.

### HID Keycode Table (excerpt from Doc 04 §2.1)

The Backspace row of the HID keycode table contained the following inline note:

| HID Code | Key       | Notes                           |
| -------- | --------- | ------------------------------- |
| `0x2A`   | Backspace | Critical for Jamo decomposition |
