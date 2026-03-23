# Flowchart Missing Backspace Undo Path

- **Date**: 2026-03-23
- **Raised by**: owner
- **Severity**: HIGH
- **Affected docs**: `behavior/draft/v1.0-r2/01-processkey-algorithm.md`
- **Status**: open

---

## Problem

The mermaid flowchart in Section 2 "Decision Tree" (lines 22-49) does not
reflect the Backspace undo path documented in Section 2.3 "Backspace Handling in
Composing Mode."

The flowchart routes all non-printable keys through a single path:

```
print_check -- "No (arrow / F-key / etc.)" --> flush_np["flush composition + forward key"]
```

Backspace (HID 0x2A) is non-printable (excluded from `isPrintablePosition()`),
so it falls into this branch — but Backspace should NOT flush. It should be
delegated to the IME undo handler, which is the third non-printable path
described in the handover and documented in Section 2.3.

The three-path model for non-printable keys in composing mode:

1. Modifier keys (Ctrl/Alt/Cmd) → flush + forward — present in flowchart
2. Special keys (Enter, Escape, Tab, Space, arrows) → flush + forward — present
   in flowchart
3. Backspace → IME undo handler — **missing from flowchart**

The step-by-step algorithm (Section 2.1) correctly handles this via Step 3's
note (Backspace routed to Section 2.3), but the flowchart — the first thing a
reader sees — omits the path entirely.

## Analysis

An implementor who reads the flowchart first (as intended — it is the overview
before the step-by-step detail) would conclude that Backspace flushes
composition, contradicting Section 2.3. This is the same class of error as
R4-sem-1 from v1.0-r1 (Backspace incorrectly grouped with flush keys), but in
the visual diagram rather than the prose.

The flowchart was updated in v1.0-r2 to add the release event guard (Step 1 →
action check), but the Backspace path was not added at the same time.

## Proposed Change

Add a Backspace decision node between `print_check` and `flush_np` in the
flowchart:

```
print_check -- "No" --> backspace_check{"Backspace?"}
backspace_check -- "Yes" --> undo["IME undo handler<br/>(Section 2.3)"]
backspace_check -- "No" --> flush_np["flush composition +<br/>forward key"]
undo --> result
```

Alternatively, the `print_check` "No" branch label could be expanded to show the
split directly:

```
print_check -- "No, Backspace" --> undo[...]
print_check -- "No, other" --> flush_np[...]
```

Either approach makes the three-path model visible in the diagram.

## Owner Decision

Left to designers for resolution.

## Resolution

_(To be filled when resolved in draft/v1.0-r3.)_
