# Handover: IME Interface Contract v1.0-r10 to v1.0-r11

- **Date**: 2026-03-31
- **Author**: team lead

---

## Insights and New Perspectives

**v1.0-r10 was a focused, clean cycle**: One CTR from the protocol team (engine
decomposition boundary + preedit exclusivity invariant) was applied via 3
resolutions, verified in 3 rounds, and declared CLEAN. The verification found 1
minor issue (V1-01: isPrintablePosition docstring misclassified Backspace),
which was fixed in the first fix round. Rounds 2 and 3 found zero
interface-contract-specific issues (only a cascade fix from behavior docs).

**Engine decomposition boundary clarifies the "who transforms what" question**:
Resolution 1 established that only `init()` and `setActiveInputMethod()`
decompose the `input_method` string into engine-specific types (e.g., libhangul
keyboard IDs). No code outside the engine examines or transforms the string.
This was implicit before; now it is normative in Section 2.

**Preedit exclusivity is structural, not enforced**: Resolution 2 added Section
3 (Per-Session Engine Architecture) documenting that at most one pane per
session can have active preedit. The critical editorial insight: this is framed
as a consequence of the single-composition-context architecture ("the engine has
one jamo stack"), NOT as a daemon obligation. The engine is pane-agnostic.

**Implementation is mature and stable**: libitshell3-ime v0.7.0 (9 source files,
139 tests, 98.59% kcov coverage) has been finalized since before v1.0-r10
started. The implementation was used as the reference during Plans 5 and 5.5
(IME integration + spec alignment audit). No implementation changes were needed
for the v1.0-r10 spec updates.

## Design Philosophy

**Interface contract is caller-facing only**: The editorial policy (established
in v1.0-r9 CTR-03) continues to hold: the interface contract defines the vtable,
types, and behavioral guarantees visible to callers. Internal implementation
details (libhangul API call sequences, jamo stack mechanics, keyboard ID
mappings) live in the behavior docs. The input_method registry canonical
location stays in `10-hangul-engine-internals.md` (Resolution 3).

**CapsLock/NumLock are input classification modifiers, not composition
modifiers**: ADR 00059 established that CapsLock and NumLock affect key
_identity_ (character case, numpad printable vs navigation) but do NOT break
Hangul composition. This distinction is critical:
`hasCompositionBreakingModifier
()` must continue to check only ctrl, alt,
super_key.

## Owner Priorities

- **v1.0-r11 is part of a unified 4-topic cycle** (Plan 15): daemon-architecture
  (v1.0-r9), daemon-behavior (v1.0-r9), server-client- protocols (v1.0-r13), and
  IME interface-contract (v1.0-r11) are being revised simultaneously.
  Cross-module consistency is critical.
- **Single CTR to resolve**: `01-impl-capslock-numlock-modifiers.md` (ADR
  00059). This is a shared concern with protocol CTR-05
  (`05-impl-capslock-numlock-wire-preservation.md`). The wire modifier bits and
  the IME Modifiers struct must be consistent.
- **Implementation is stable**: libitshell3-ime v0.7.0 needs no code changes for
  the v1.0-r10 spec. v1.0-r11 spec changes (adding caps_lock/num_lock fields)
  will require corresponding code changes in Plan 16.

## New Conventions and Procedures

No new conventions from this cycle. All conventions established in v1.0-r9
(cross-document reference policy, editorial scope policy, metadata format)
remain in effect.

## Pre-Discussion Research Tasks

### CTR to resolve (1 total)

1. `01-impl-capslock-numlock-modifiers.md` — Add caps_lock and num_lock boolean
   fields to KeyEvent.Modifiers packed struct (ADR 00059). Confirm
   hasCompositionBreakingModifier() exclusion. Add NumLock guidance for
   isPrintablePosition(). All changes to `02-types.md`.

### Cross-module coordination

- Protocol CTR-05 (`05-impl-capslock-numlock-wire-preservation.md`) adds a
  normative preservation note for the same modifier bits on the wire side. The
  IME and protocol teams must ensure the bit positions and semantics match.
- Daemon CTR on ADR 00059 may affect `02-state-and-types.md`
  (KeyEvent.Modifiers). All three specs must agree on the modifier struct
  layout.

### Implementation note

The current
`KeyEvent.Modifiers = packed struct(u8) { ctrl, alt, super_key,
_padding: u5 }`
will become `{ ctrl, alt, super_key, caps_lock, num_lock,
_padding: u3 }`. This
is a wire-compatible change (bits 3-4 were previously padding/zero, now carry
CapsLock/NumLock from the protocol modifier byte).
