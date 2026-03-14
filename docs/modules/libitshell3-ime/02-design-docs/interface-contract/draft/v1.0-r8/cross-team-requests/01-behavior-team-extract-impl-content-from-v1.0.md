# Extract Implementation Behavior from Interface Contract

**Date**: 2026-03-14
**Source team**: ime-behavior
**Source version**: behavior draft/v1.0-r1
**Source resolution**: [PLAN.md](../../../behavior/draft/v1.0-r1/PLAN.md) Section 3 (Content Extraction Map)
**Target docs**: 01-overview.md, 02-types.md, 03-engine-interface.md, 04-ghostty-integration.md
**Status**: open

---

## Context

The behavior team has created a new `behavior/` topic (`behavior/draft/v1.0-r1/`) to house implementation-specific content that was previously embedded in the interface contract. This content describes engine internals (decision trees, libhangul API call sequences, buffer layout, concrete struct fields) that only the IME engine implementor needs -- not the server/daemon team who consumes the caller-facing API.

The interface contract should retain only caller-facing specs (method signatures, input/output types, invariants, preconditions, postconditions) and replace the extracted content with cross-references to the corresponding behavior docs.

This request does NOT mean deleting information -- it means moving implementation details to their proper home and leaving cross-references in place.

## Required Changes

### 1. 01-overview.md lines 57-67 -- Remove processKey() internal decision tree

- **Current**: Code block showing engine-internal decision tree (modifier check -> printable check -> libhangul -> compose -> ImeResult construction)
- **After**: Replace with a one-line summary and cross-reference:
  > The engine internally processes the key through a decision tree (modifier check, printable check, composition). See [behavior/draft/v1.0-r1/01-processkey-algorithm.md](../../../behavior/draft/v1.0-r1/01-processkey-algorithm.md) for the full algorithm.
- **Rationale**: The decision tree is implementation behavior, not caller-facing API. The caller only needs to know: `processKey(KeyEvent) -> ImeResult`.

### 2. 01-overview.md lines 71-92 -- Remove hangul_ic_process() return-false handling

- **Current**: Detailed algorithm for handling `hangul_ic_process()` returning false, including step-by-step call sequence, worked example (typing "ㅎ" then "."), and PoC reference
- **After**: Replace with cross-reference:
  > When `hangul_ic_process()` returns false (key rejected by libhangul), the engine follows the return-false handling algorithm. See [behavior/draft/v1.0-r1/11-hangul-ic-process-handling.md](../../../behavior/draft/v1.0-r1/11-hangul-ic-process-handling.md) for the full algorithm and worked examples.
- **Rationale**: libhangul API call sequences are engine implementation details. The caller does not interact with `hangul_ic_process()` directly.

### 3. 02-types.md lines 125-158 -- Remove ImeResult scenario matrix and direct mode behavior

- **Current**: Full scenario matrix table (28 rows covering direct mode and Korean composition cases) plus direct mode behavior description
- **After**: Keep the `ImeResult` field definitions (the struct and field documentation above line 125). Replace the scenario matrix with a one-line reference:
  > For the full scenario matrix showing all valid `ImeResult` field combinations across direct mode and Korean composition, see [behavior/draft/v1.0-r1/02-scenario-matrix.md](../../../behavior/draft/v1.0-r1/02-scenario-matrix.md).
- **Rationale**: The scenario matrix is behavioral documentation showing how the engine populates `ImeResult` in various situations. The caller-facing contract needs only the struct definition and field semantics.

### 4. 02-types.md lines 160-186 -- Remove Modifier Flush Policy section body

- **Current**: Section 3.3 "Modifier Flush Policy" with full policy table, example (Ctrl+C during preedit), and ibus-hangul/fcitx5-hangul verification notes
- **After**: Keep the section heading (as an anchor for existing cross-references). Replace the body with:
  > The modifier flush policy (which keys trigger flush vs. participate in composition) is defined in [behavior/draft/v1.0-r1/03-modifier-flush-policy.md](../../../behavior/draft/v1.0-r1/03-modifier-flush-policy.md).
- **Rationale**: The flush policy table describes engine-internal decision logic. The caller only needs to know that modifiers cause flush (which is already stated in the `ImeResult` field docs).

### 5. 03-engine-interface.md lines 128-153 -- Remove setActiveInputMethod internal step sequence

- **Current**: Detailed internal steps for `setActiveInputMethod()` (call `hangul_ic_flush()`, read flushed string, set `active_input_method`, update engine mode, return `ImeResult`), plus `hangul_ic_flush()` cleanup notes and `discard-and-switch` pattern
- **After**: Keep the observable behavior spec (what the caller observes: "flushes pending composition atomically, returns `ImeResult` with committed text if composing, error if unsupported"). Remove the internal step-by-step procedure. Add cross-reference:
  > For the internal step sequence and libhangul cleanup details, see [behavior/draft/v1.0-r1/10-hangul-engine-internals.md](../../../behavior/draft/v1.0-r1/10-hangul-engine-internals.md) Section 4.
- **Rationale**: The caller needs to know what `setActiveInputMethod()` does (flush + switch), not how it does it internally.

### 6. 03-engine-interface.md lines 159-248 -- Remove HangulImeEngine concrete struct entirely

- **Current**: Section 3.7 "HangulImeEngine (Concrete Implementation)" with full Zig struct definition, field descriptions, `EngineMode` enum, `libhangulKeyboardId()` mapping function, canonical input method registry table, mapping ownership rationale, `processKeyImpl` note, and session persistence note
- **After**: Remove the entire section. The interface contract only needs `ImeEngine` (the vtable interface). Add a one-line reference at the end of the `ImeEngine` section:
  > For the concrete `HangulImeEngine` implementation (struct fields, engine mode, libhangul keyboard mapping, buffer layout), see [behavior/draft/v1.0-r1/10-hangul-engine-internals.md](../../../behavior/draft/v1.0-r1/10-hangul-engine-internals.md).
- **Rationale**: Concrete implementation types do not belong in the interface contract. The server/daemon depends on `ImeEngine` (the vtable), never on `HangulImeEngine` directly.

> **Dangling cross-reference fix (caused by this removal):** Section 3.6 `setActiveInputMethod()` (line 145) contains "The server MUST only send input method strings from the canonical registry (Section 3.7)." After Section 3.7 is removed, this reference becomes dangling. Update it to point to the behavior doc where the canonical registry table will reside:
> "The server MUST only send input method strings from the canonical registry (see [behavior/draft/v1.0-r1/10-hangul-engine-internals.md](../../../behavior/draft/v1.0-r1/10-hangul-engine-internals.md), Section: Canonical Input Method Registry)."

### 7. 04-ghostty-integration.md lines 17-31 -- Remove buffer layout and sizing rationale

- **Current**: Section 6 "Memory Ownership" contains buffer layout (`committed_buf: [256]u8`, `preedit_buf: [64]u8`), sizing rationale, and libhangul memory model reference
- **After**: Keep the caller-facing rule as a one-liner: "ImeResult slices point to internal engine buffers, valid until the next mutating call (`processKey()`, `flush()`, `reset()`, `deactivate()`, `setActiveInputMethod()`). Zero heap allocation per keystroke." Add cross-reference:
  > For buffer layout, sizing rationale, and libhangul memory model details, see [behavior/draft/v1.0-r1/10-hangul-engine-internals.md](../../../behavior/draft/v1.0-r1/10-hangul-engine-internals.md) Section 3.
- **Rationale**: The caller needs the lifetime rule (when slices are invalidated). The buffer sizes and implementation rationale are engine internals.

## Summary Table

| Target Doc | Section | Change Type | Behavior Doc Reference |
|-----------|---------|-------------|----------------------|
| 01-overview.md | lines 57-67 (processKey decision tree) | Remove -> cross-reference | 01-processkey-algorithm.md |
| 01-overview.md | lines 71-92 (hangul_ic_process return-false) | Remove -> cross-reference | 11-hangul-ic-process-handling.md |
| 02-types.md | lines 125-158 (scenario matrix + direct mode) | Remove -> cross-reference | 02-scenario-matrix.md |
| 02-types.md | lines 160-186 (modifier flush policy) | Remove body -> cross-reference | 03-modifier-flush-policy.md |
| 03-engine-interface.md | lines 128-153 (setActiveInputMethod internals) | Keep observable spec, remove internals -> cross-reference | 10-hangul-engine-internals.md |
| 03-engine-interface.md | lines 159-248 (HangulImeEngine concrete struct) | Remove entirely -> cross-reference | 10-hangul-engine-internals.md |
| 03-engine-interface.md | line 145 (Section 3.6 registry cross-ref) | Update dangling "Section 3.7" reference | 10-hangul-engine-internals.md |
| 04-ghostty-integration.md | lines 17-31 (buffer layout + sizing) | Keep one-liner rule -> cross-reference | 10-hangul-engine-internals.md |

> **Note on `## 2. Processing Pipeline` heading (01-overview.md)**: Items 1 and 2 above both remove content from under this heading. After both removals, the heading has no remaining body. **Remove the heading entirely** -- an empty stub heading serves no reader purpose and creates a misleading table-of-contents entry. If the heading is an anchor target for external cross-references, update those references to point to the behavior docs instead.
