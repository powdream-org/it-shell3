# 00040. Modifier Flush Policy: Flush Not Reset

- Date: 2026-03-23
- Status: Accepted

## Context

When a modifier key combination (Ctrl+C, Alt+F, Cmd+V) or a special key (Enter,
Tab, Escape, Arrow, Space) arrives while the IME engine has an active preedit,
the engine must decide what to do with the in-progress composition before
forwarding the key.

Two approaches exist in practice:

- **Flush (commit)**: Write the partial composition to the terminal as committed
  text, then forward the interrupting key. The user sees their typed text
  preserved.
- **Reset (discard)**: Silently discard the partial composition, then forward
  the interrupting key. The user's in-progress input vanishes.

The project's early design document (`interface-design.md` Section 1.4)
specified RESET for Ctrl/Alt/Super modifiers, claiming this matched ibus-hangul
behavior. This claim was incorrect.

Source verification of reference implementations:

- **ibus-hangul**: `ibus_hangul_engine_process_key_event()` calls
  `hangul_ic_flush()` on `IBUS_CONTROL_MASK | IBUS_MOD1_MASK`. The flushed text
  is committed via `ibus_engine_commit_text()`. It flushes, not resets.
- **fcitx5-hangul**: `HangulState::keyEvent()` calls `flush()` on modifier
  detection. Same behavior — commit, not discard.

Both major Korean IME frameworks flush (commit) on modifier keys. No reference
implementation discards user input on modifier interruption.

This decision complements ADR-00026 (Preedit Interrupt Policy: Commit Unless
Impossible), which covers daemon-level interrupting events. This ADR covers the
engine-internal policy for key-driven interruptions during composition.

## Decision

The IME engine always **flushes (commits)** the in-progress composition when a
non-composing key arrives. It never resets (discards) the preedit.

Specifically:

- Modifier keys (Ctrl, Alt, Cmd/Super): flush + forward
- Special keys (Enter, Tab, Escape, Arrow keys, Space): flush + forward
- Shift: no flush — Shift selects character variants (e.g., ㄱ→ㄲ in Korean) and
  is passed to the composition engine
- Backspace: no flush — delegated to the engine's language-specific undo handler

## Consequences

- User input is never silently lost during composition. A user composing "하"
  who presses Ctrl+C sees "하" committed to the terminal before the interrupt
  signal.
- The `ImeResult` for flush scenarios always has `committed_text` (the flushed
  composition), `forward_key` (the interrupting key), `preedit_text = null`, and
  `preedit_changed = true`.
- `preedit_text` and `forward_key` are mutually exclusive — they can never both
  be non-null. A forwarded key always triggers flush first (clearing preedit).
- The early `interface-design.md` RESET specification is superseded. Any code or
  documentation referencing RESET for modifier handling is incorrect.
- This policy is language-agnostic — it applies to all composition engines, not
  just Korean Hangul.
