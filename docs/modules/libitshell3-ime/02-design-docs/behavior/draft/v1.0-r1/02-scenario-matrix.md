# ImeResult Scenario Matrix

> **Scope**: Language-agnostic framework with Korean composition as reference examples
> **Version**: v1.0-r1
> **Date**: 2026-03-14
> **Extracted from**: interface-contract/draft/v1.0-r8/02-types.md §3.2 — content moved to this document; §3.2 will cross-reference back here after CTR-02 is applied

---

## 1. Overview

This document catalogs every `ImeResult` field combination that `processKey()` can produce. The matrix serves as the authoritative reference for:

- IME engine implementors validating their output
- Daemon integration (Phase 2) testing all consumption paths
- Protocol/client teams understanding what `ImeResult` patterns to expect

All four `ImeResult` fields are orthogonal — any combination is valid.

---

## 2. ImeResult Fields

```zig
pub const ImeResult = struct {
    committed_text: ?[]const u8 = null,   // UTF-8, committed to terminal
    preedit_text: ?[]const u8 = null,     // UTF-8, overlay display
    forward_key: ?KeyEvent = null,        // Key to forward to ghostty
    preedit_changed: bool = false,        // Whether preedit state changed
};
```

**Field independence**: Each field is set based on its own criteria. `committed_text` and `forward_key` can both be present (flush + forward). `preedit_text` can coexist with `committed_text` (syllable break produces committed text and starts new preedit). The engine MUST set `preedit_changed` accurately for dirty tracking.

---

## 3. Scenario Matrix

### 3.1 Direct Mode

In direct mode (`input_method = "direct"`), no composition occurs. `preedit_text` is always `null` and `preedit_changed` is always `false`.

| Scenario | committed_text | preedit_text | forward_key | preedit_changed |
|----------|----------------|--------------|-------------|-----------------|
| Printable 'a' | `"a"` | null | null | false |
| Printable Shift+'a' | `"A"` | null | null | false |
| Enter | null | null | Enter key | false |
| Space | null | null | Space key | false |
| Ctrl+C | null | null | Ctrl+C key | false |
| Arrow key | null | null | Arrow key | false |
| Escape | null | null | Escape key | false |
| Backspace | null | null | Backspace key | false |
| Release event | null | null | null | false |

**Direct mode rules** (from [01-processkey-algorithm.md](01-processkey-algorithm.md) Section 3):

- Printable key without modifiers: HID-to-ASCII lookup, committed as text. No forward key.
  - **Exception**: Space is always forwarded, not committed as text.
- Non-printable, modified, or unmapped key: forwarded. No committed text.
- `preedit_changed` is always `false` — no composition exists.

### 3.2 Composing Mode — Korean Composition (Reference Examples)

These examples use Korean 2-set (`input_method = "korean_2set"`) to illustrate composing mode behavior. The ImeResult patterns apply to any composing input method.

#### Normal Composition

| Scenario | committed_text | preedit_text | forward_key | preedit_changed |
|----------|----------------|--------------|-------------|-----------------|
| Start composing: ㄱ | null | `"ㄱ"` | null | true |
| Add vowel: 가 | null | `"가"` | null | true |
| Add tail consonant: 한 | null | `"한"` | null | true |
| Double tail: 없 (ㅂㅅ tail) | null | `"없"` | null | true |
| Syllable break: 간 -> new ㄱ | `"간"` | `"ㄱ"` | null | true |

**Syllable break** is the only normal composition scenario where both `committed_text` and `preedit_text` are non-null. The completed syllable is committed, and the new leading consonant starts a new preedit.

#### Flush Scenarios (Composition Interrupted)

When a non-composing key arrives during active composition, the engine flushes (commits) the in-progress preedit and forwards the triggering key. See [03-modifier-flush-policy.md](03-modifier-flush-policy.md) for the complete policy rationale.

| Scenario | committed_text | preedit_text | forward_key | preedit_changed |
|----------|----------------|--------------|-------------|-----------------|
| Arrow during composition | `"한"` (flush) | null | Arrow key | true |
| Ctrl+C during composition | `"하"` (flush) | null | Ctrl+C key | true |
| Enter during composition | `"ㅎ"` (flush) | null | Enter key | true |
| Escape during composition | `"한"` (flush) | null | Escape key | true |
| Tab during composition | `"한"` (flush) | null | Tab key | true |
| Space during composition | `"한"` (flush) | null | Space key | true |

All flush scenarios share the same pattern: `committed_text` contains the flushed composition, `preedit_text` is null (composition ended), `forward_key` is the triggering key, and `preedit_changed` is true (preedit transitioned from non-null to null).

#### Backspace

| Scenario | committed_text | preedit_text | forward_key | preedit_changed |
|----------|----------------|--------------|-------------|-----------------|
| Backspace removes tail (한 -> 하) | null | `"하"` (undo) | null | true |
| Backspace on empty composition | null | null | Backspace key | false |

Backspace during composition undoes the last jamo via `hangul_ic_backspace()`. When composition is empty, backspace is forwarded to the terminal.

#### No-Op and Edge Cases

| Scenario | committed_text | preedit_text | forward_key | preedit_changed |
|----------|----------------|--------------|-------------|-----------------|
| Space with empty composition | null | null | Space key | false |
| Ctrl+C with no composition | null | null | Ctrl+C key | false |
| Release event | null | null | null | false |

When no composition is active, modifier and special keys behave the same as direct mode — they are forwarded without producing committed text, and `preedit_changed` is false (preedit remains null throughout).

### 3.3 Input Method Switch

| Scenario | committed_text | preedit_text | forward_key | preedit_changed |
|----------|----------------|--------------|-------------|-----------------|
| Switch with active composition (korean_2set -> direct) | `"한"` (flush) | null | null | true |
| Switch without active composition (korean_2set -> direct) | null | null | null | false |

Input method switch via `setActiveInputMethod()` flushes atomically if composition is active. `forward_key` is always null — the toggle key was consumed by Phase 0.

---

## 4. ImeResult Field Combination Summary

The following truth table summarizes which field combinations are valid:

| committed_text | preedit_text | forward_key | preedit_changed | When |
|:-:|:-:|:-:|:-:|---|
| null | null | null | false | Release event, no-op, switch without composition |
| non-null | null | null | false | Direct mode printable (no composition existed) |
| non-null | null | null | true | Switch with active composition (flush: preedit non-null → null) |
| null | non-null | null | true | Composing (new jamo added to preedit) |
| non-null | non-null | null | true | Syllable break (commit old + start new preedit) |
| null | null | non-null | false | Non-composing key with no active composition |
| non-null | null | non-null | true | Flush + forward (modifier, arrow, Enter, etc.) |

Two combinations never occur in practice:

| committed_text | preedit_text | forward_key | preedit_changed | Why not |
|:-:|:-:|:-:|:-:|---|
| null | non-null | non-null | — | A forwarded key during composition always triggers flush first |
| non-null | non-null | non-null | — | Syllable break does not forward a key; flush does not start new preedit |

---

## 5. preedit_changed Semantics

`preedit_changed` tracks whether the preedit state transitioned between calls:

| Previous preedit | Current preedit | preedit_changed |
|:---:|:---:|:---:|
| null | null | false |
| null | non-null | true |
| non-null | null | true |
| non-null | different non-null | true |
| non-null | same non-null | false (rare — typically composition always changes) |

The engine MUST set this flag accurately. The daemon uses it for dirty tracking — preedit updates are sent to clients only when `preedit_changed` is true.
