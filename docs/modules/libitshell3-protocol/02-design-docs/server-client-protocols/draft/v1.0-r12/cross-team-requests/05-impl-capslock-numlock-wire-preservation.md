# Clarify CapsLock/NumLock Preservation in Wire-to-IME Path

- **Date**: 2026-03-27
- **Source team**: impl (Plan 5.5 Spec Alignment Audit)
- **Source version**: libitshell3 implementation Plans 1-5
- **Source resolution**: ADR 00059 (CapsLock and NumLock Modifiers in IME
  KeyEvent)
- **Target docs**: `04-input-and-renderstate.md` (KeyEvent wire format)
- **Status**: open

---

## Context

ADR 00059 established that the daemon's native IME engine needs CapsLock (bit 4)
and NumLock (bit 5) from the wire modifier byte. The protocol spec correctly
defines these bits in the wire format. However, the spec does not explicitly
state that the daemon MUST preserve these bits when routing key events to the
IME engine — leaving room for implementations to silently drop them (which the
current code does in `wire_decompose.zig`).

## Required Changes

1. **`04-input-and-renderstate.md` — Add normative note about CapsLock/NumLock
   preservation.**
   - **Current**: The modifier byte table defines bits 4-5 but does not state
     preservation requirements for the daemon's key routing pipeline.
   - **After**: Add a note after the modifier byte table: "The daemon MUST
     preserve CapsLock (bit 4) and NumLock (bit 5) when routing KeyEvent to the
     IME engine. The native IME engine requires these modifiers for
     CapsLock-aware character resolution and NumLock-dependent numpad key
     classification (see ADR 00059)."
   - **Rationale**: ADR 00059. Without this normative statement, implementations
     may reasonably assume that CapsLock/NumLock are optional for the IME path
     (as they are in OS IME systems).

## Summary Table

| Target Doc                    | Section/Message     | Change Type | Source Resolution |
| ----------------------------- | ------------------- | ----------- | ----------------- |
| `04-input-and-renderstate.md` | Modifier byte table | Add note    | ADR 00059         |
