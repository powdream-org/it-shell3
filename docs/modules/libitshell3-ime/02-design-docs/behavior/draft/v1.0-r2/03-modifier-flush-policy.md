# Modifier Flush Policy

**Version**: v1.0-r1
**Date**: 2026-03-14
**Scope**: Language-agnostic flush policy for modifier keys and special keys during active composition

---

## 1. Overview

When the IME engine has an active preedit (composition in progress) and a
modifier+key combination or special key arrives, the engine **flushes (commits)**
the in-progress composition, then forwards the key to the terminal. The preedit
is never silently discarded.

This policy is language-agnostic — it applies to all composition engines (Korean,
Japanese, Chinese, etc.), not just Hangul. The verification section uses Korean
(ibus-hangul, fcitx5-hangul) as reference implementations because Korean is the
first supported composition language.

## 2. Flush Policy Table

| Key Type | Preedit Action | Rationale |
|---|---|---|
| Ctrl+key | **Flush** (commit preedit) | Preserve user's typed text before command execution |
| Alt+key | **Flush** (commit preedit) | Same as Ctrl |
| Super/Cmd+key | **Flush** (commit preedit) | Same as Ctrl |
| Enter | **Flush** (commit preedit) | User intends to submit what they typed |
| Tab | **Flush** (commit preedit) | User is moving forward (tab completion) |
| Escape | **Flush** (commit preedit) | Commit what user typed, then forward Escape |
| Arrow keys | **Flush** (commit preedit) | User is navigating — commit what they have |
| Space | **Flush** (commit preedit) | Word separator — commit syllable, then insert space |
| Shift+key | **No flush** (jamo selection) | Shift selects jamo variants (e.g., ㄱ→ㄲ in Korean), not a composition-breaking modifier |
| Backspace | **IME handles** | Language-specific undo (e.g., `hangul_ic_backspace()` undoes last jamo); if composition is empty, forward to terminal |

### 2.1 Design Principle: Flush, Never Discard

The engine always **commits** the in-progress composition before forwarding the
interrupting key. It never resets (discards) the preedit. This preserves the
user's typed text in all cases — the user sees their partial input committed to
the terminal, followed by the effect of the modifier/special key.

### 2.2 Shift Exception

Shift is not a composition-breaking modifier. In CJK input methods, Shift
selects character variants (e.g., Korean jamo ㄱ→ㄲ, ㅂ→ㅃ). Flushing on Shift
would break normal composition flow. Shift+key is passed directly to the
composition engine for processing.

### 2.3 Backspace Handling

Backspace is handled by the composition engine's language-specific undo logic,
not by the flush policy. For Korean, `hangul_ic_backspace()` removes the last
jamo from the current syllable. If the composition is already empty (no preedit),
the backspace is forwarded to the terminal as a normal key.

## 3. ImeResult Construction

When flush occurs, the engine produces an `ImeResult` with:

- `committed_text`: the flushed composition text
- `preedit_text`: null (composition cleared)
- `forward_key`: the original modifier+key or special key
- `preedit_changed`: true (preedit transitioned from non-null to null)

### 3.1 Example: Ctrl+C During Preedit

User is composing Korean preedit "하" and presses Ctrl+C:

```
ImeResult{ .committed_text = "하", .preedit_text = null,
           .forward_key = Ctrl+C, .preedit_changed = true }
```

The engine returns committed text "하" alongside the forwarded Ctrl+C key,
ensuring composition is flushed before the modifier is passed downstream.

### 3.2 Scope Boundary

> **Note**: The order in which the daemon consumes `ImeResult` fields (PTY
> writes, preedit cache updates, key forwarding) is a Phase 2 concern and out of
> scope for this document. See the daemon architecture docs for Phase 2
> consumption details.

## 4. Verification Against Reference Implementations

### 4.1 ibus-hangul

`ibus_hangul_engine_process_key_event()` calls `hangul_ic_flush()` when it
detects `IBUS_CONTROL_MASK | IBUS_MOD1_MASK` (Ctrl or Alt). The flushed text is
committed via `ibus_engine_commit_text()`, then the key is forwarded. This
matches the flush policy defined above.

### 4.2 fcitx5-hangul

`HangulState::keyEvent()` calls `flush()` on modifier detection. The committed
text is sent to the client, then the key event is forwarded. This also matches
the flush policy.

### 4.3 Historical Correction

The earlier `interface-design.md` (Section 1.4) specified RESET (discard) for
Ctrl/Alt/Super modifiers. That was incorrect — it claimed to match ibus-hangul,
but ibus-hangul actually flushes (commits). This behavior document and the
interface contract correct that error.
