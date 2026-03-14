# Behavior Doc Creation Plan — libitshell3-ime v1.0-r1

**Date**: 2026-03-14
**Status**: Planning — not yet executed

---

## 1. Background

The IME interface contract (`interface-contract/draft/v1.0-r8/`) mixes two distinct
concerns:

- **Interface contract**: caller-facing API — method signatures, input/output types,
  invariants, preconditions, postconditions. The server/daemon needs this.
- **Implementation behavior**: how the engine works internally — internal decision
  trees, libhangul API call sequences, buffer sizing, concrete struct layout. Only
  the IME implementor needs this.

This plan creates a new `behavior/` topic to house the implementation-specific
content, then files cross-team requests to remove it from the interface contract.

---

## 2. New Documents to Create

Path: `docs/modules/libitshell3-ime/02-design-docs/behavior/draft/v1.0-r1/`

All docs are flat under `behavior/draft/v1.0-r1/`. Number ranges distinguish
language-agnostic from language-specific content:

| Range | Scope |
|-------|-------|
| 01–09 | Language-agnostic (general pipeline, all engines) |
| 10–19 | Korean (Hangul / libhangul) |
| 20–29 | Japanese (future) |
| 30–39 | Chinese (future) |

**Language-agnostic (01–09):**

| File | Contents |
|------|----------|
| `01-processkey-algorithm.md` | `processKey()` general decision tree: modifier check → printable check → compose → `ImeResult`; direct mode branching logic |
| `02-scenario-matrix.md` | `ImeResult` scenario matrix (direct mode cases + Korean composition cases as reference examples) |
| `03-modifier-flush-policy.md` | Modifier flush policy table with rationale; ibus-hangul / fcitx5-hangul verification (policy is language-agnostic; verification uses Korean as reference) |

**Korean (10–19):**

| File | Contents |
|------|----------|
| `10-hangul-engine-internals.md` | `HangulImeEngine` concrete struct fields; `EngineMode`; libhangul keyboard ID mapping; `setActiveInputMethod` internal step sequence; `hangul_ic_flush()` internals; buffer layout and sizing rationale; libhangul memory model reference |
| `11-hangul-ic-process-handling.md` | `hangul_ic_process()` return-false handling algorithm; correct call sequence for commit/preedit string extraction |

---

## 3. Content Extraction Map

### 3.1 From `interface-contract/draft/v1.0-r8/01-overview.md`

| Lines | Content | Destination |
|-------|---------|-------------|
| 57–67 | `processKey()` internal decision tree (code block) | `01-processkey-algorithm.md` |
| 71–92 | `hangul_ic_process()` return-false handling algorithm | `11-hangul-ic-process-handling.md` |

**After extraction**: Replace both blocks with cross-references to the respective
behavior docs.

### 3.2 From `interface-contract/draft/v1.0-r8/02-types.md`

| Lines | Content | Destination |
|-------|---------|-------------|
| 125–158 | `ImeResult` scenario matrix + direct mode behavior | `02-scenario-matrix.md` |
| 160–186 | Section 3.3 Modifier Flush Policy (entire section) | `03-modifier-flush-policy.md` |

**After extraction**:
- 3.2: Keep the field definitions; replace scenario matrix with one-line reference.
- 3.3: Replace section body with cross-reference; keep section heading as anchor.

### 3.3 From `interface-contract/draft/v1.0-r8/03-engine-interface.md`

| Lines | Content | Destination |
|-------|---------|-------------|
| 128–153 | `setActiveInputMethod` internal step sequence + `hangul_ic_flush()` internals | `10-hangul-engine-internals.md` |
| 159–248 | `HangulImeEngine` concrete struct (fields, `EngineMode`, libhangul mapping, `processKeyImpl` note) | `10-hangul-engine-internals.md` |

**After extraction**: Section 3.6 keeps the observable behavior spec (what the caller
observes); the internal steps move out. Section 3.7 `HangulImeEngine` is removed
entirely — the interface contract only needs `ImeEngine` (vtable).

### 3.4 From `interface-contract/draft/v1.0-r8/04-ghostty-integration.md`

| Lines | Content | Destination |
|-------|---------|-------------|
| 17–31 | Internal buffer layout (`committed_buf`, `preedit_buf`); sizing rationale; libhangul memory model reference | `10-hangul-engine-internals.md` |

**After extraction**: Keep the caller-facing rule ("slices valid until next mutating
call; zero heap allocation per keystroke") as a one-liner.

---

## 4. Cross-Team Requests to File

Three CTRs are needed: one to the daemon team, two to the interface-contract team.
All are filed after the behavior doc is created (so cross-reference links are valid).

### CTR-01: Simplify Phase 1 subgraph in daemon architecture diagram

**Source team**: ime-behavior (this team)
**Target team**: daemon (libitshell3)
**File location**: `libitshell3/02-design-docs/daemon/draft/v1.0-r4/cross-team-requests/01-ime-behavior-simplify-phase1-diagram.md`
  _(filed into inbox if v1.0-r5 not yet started:_
  `libitshell3/02-design-docs/daemon/inbox/cross-team-requests/01-ime-behavior-simplify-phase1-diagram-from-v1.0.md`)

**Context**: The behavior team has moved the `processKey()` internal decision tree
(modifier check → printable check → libhangul → ImeResult) into
`behavior/draft/v1.0-r1/01-processkey-algorithm.md`. The daemon's Phase 1 subgraph
now duplicates this content.

**Required changes**:

| Target Doc | Section | Change Type |
|-----------|---------|-------------|
| `01-internal-architecture.md` | Phase 1 subgraph (3-phase input pipeline diagram) | Simplify to `processKey(KeyEvent) → ImeResult` black-box; remove internal nodes; add cross-reference to behavior doc |

**Simplified Phase 1 subgraph**:
```mermaid
subgraph P1["Phase 1: IME Engine (libitshell3-ime)"]
    P1_process["processKey(KeyEvent)"]
    P1_result(["ImeResult"])
    P1_process --> P1_result
end
```

---

### CTR-02: Extract implementation behavior from interface-contract

**Source team**: ime-behavior (this team)
**Target team**: ime-interface-contract
**File location**: `interface-contract/draft/v1.0-r9/cross-team-requests/01-behavior-team-extract-impl-content.md`
  _(filed into inbox if v1.0-r9 not yet started:_
  `interface-contract/inbox/cross-team-requests/01-behavior-team-extract-impl-content-from-v1.0.md`)

**Context**: Implementation behavior content has been moved to `behavior/draft/v1.0-r1/`.
The interface-contract should retain only caller-facing specs and replace the moved
content with cross-references.

**Required changes**:

| Target Doc | Section | Change Type |
|-----------|---------|-------------|
| `01-overview.md` | Phase 1 algorithm block (lines 57–67) | Remove → cross-reference to behavior doc 01 |
| `01-overview.md` | `hangul_ic_process()` return-false section (lines 71–92) | Remove → cross-reference to behavior doc 01 |
| `02-types.md` | 3.2 scenario matrix + direct mode behavior (lines 125–158) | Remove → cross-reference to behavior doc 02 |
| `02-types.md` | 3.3 Modifier Flush Policy entire section (lines 160–186) | Remove → cross-reference to behavior doc 03 |
| `03-engine-interface.md` | 3.6 internal step sequence (lines 128–153) | Remove → observable spec only |
| `03-engine-interface.md` | 3.7 `HangulImeEngine` concrete struct (lines 159–248) | Remove entirely; cross-reference to behavior doc 04 |
| `04-ghostty-integration.md` | Buffer layout + sizing rationale (lines 17–31) | Remove → one-liner rule + cross-reference to behavior doc 04 |

### CTR-03: Editorial policy — keep interface-contract caller-facing only

**Source team**: ime-behavior (this team)
**Target team**: ime-interface-contract
**File location**: `interface-contract/draft/v1.0-r9/cross-team-requests/02-behavior-team-editorial-policy.md`
  _(filed into inbox if v1.0-r9 not yet started:_
  `interface-contract/inbox/cross-team-requests/02-behavior-team-editorial-policy-from-v1.0.md`)

**Context**: The interface contract is the caller-facing API spec consumed by the
server/daemon team. It must not contain implementation internals that only the IME
engine implementor needs. The `behavior/` topic now owns all such content.

**Policy rule** (normative, applies to all future revisions of `interface-contract/`):

> The interface contract MUST NOT include:
> - Internal implementation details of any `ImeEngine` concrete type
>   (struct fields, buffer layout, allocation strategy, algorithmic decision trees).
> - Language-specific internals (libhangul API call sequences, hangul_ic_process()
>   handling, keyboard ID mapping, etc.).
>
> All such content belongs in the corresponding `behavior/` document.
> The interface contract MAY cross-reference behavior docs for implementors,
> but MUST remain self-contained for callers who do not read behavior docs.

**Required changes**:

| Target Doc | Change Type |
|-----------|-------------|
| `00-index.md` (or equivalent README) | Add one-line scope statement: "This doc set covers the caller-facing API only. For engine implementation details, see `behavior/`." |
| All future revisions | Enforce above policy at authoring time; flag violations in review |

---

## 5. Execution Order

1. Create behavior doc files (`01`–`11`) with extracted content.
2. File CTR-01 to daemon team (Phase 1 diagram simplification).
3. File CTR-02 to interface-contract team (content removal).
4. File CTR-03 to interface-contract team (editorial policy).
5. Daemon team applies CTR-01 in their next revision cycle.
6. Interface-contract team applies CTR-02 + CTR-03 in their next revision cycle.

Step 1 must complete before steps 2–4 (cross-reference links must exist).
Steps 2, 3, and 4 are independent of each other.
CTR-02 and CTR-03 target the same team and may be bundled into one revision cycle.
