# Design Resolutions — CTR-01: IME Phase 1 Simplification

**Date**: 2026-03-14
**Input**: Cross-team request CTR-01 from ime-behavior team
**Source**: `docs/modules/libitshell3/02-design-docs/daemon/draft/v1.0-r4/cross-team-requests/01-ime-behavior-simplify-phase1-diagram.md`
**Participants**: daemon-architect, ghostty-integration-engineer, ime-system-sw-engineer, principal-architect, protocol-architect, protocol-system-sw-engineer

---

## R1: Replace Phase 1 Subgraph with Black-Box View

**Consensus**: 6/6

**Decision**: Replace the 8 internal nodes in the Phase 1 subgraph of `01-internal-architecture.md` (Section 1.2, lines 94–112) with a black-box subgraph containing only the entry point and result:

```mermaid
subgraph P1["Phase 1: IME Engine (libitshell3-ime)"]
    P1_process["processKey(KeyEvent)"]
    P1_result(["ImeResult"])
    P1_process --> P1_result
end
```

**Removed nodes**: `P1_mod`, `P1_print`, `P1_hangul`, `P1_ic`, `P1_flush_mod`, `P1_flush_np`, `P1_flush_rej` and all internal edges between them.

**Rationale**: The daemon's integration boundary with the IME engine is `processKey(KeyEvent) -> ImeResult`. The internal decision tree (modifier check, printable check, libhangul dispatch, `hangul_ic_process()` return handling) is an IME engine concern, now documented in the dedicated behavior doc (`01-processkey-algorithm.md`). Replicating it in the daemon architecture doc creates a DRY violation and maintenance burden. The `input/` module depends on the `ImeEngine` vtable (defined in `core/`), not on engine internals — the diagram should reflect this abstraction level.

**Scope boundaries**: Phase 0 and Phase 2 subgraphs are unchanged. The "Why IME runs before keybindings" paragraph (line 126) and Phase 0/Phase 1 module placement note (line 128) are unchanged — they describe daemon-level architectural decisions, not engine internals. The existing subgraph label `"Phase 1: IME Engine (libitshell3-ime)"` is retained as-is (pre-existing; out of scope for this CTR).

---

## R2: Add Cross-Reference to IME Behavior Doc (Corrected Path)

**Consensus**: 6/6

**Decision**: After the 3-phase pipeline diagram in `01-internal-architecture.md` (in the existing explanatory paragraph area), add a cross-reference:

> For the internal `processKey()` decision algorithm (modifier handling, printable key dispatch, libhangul composition), see [IME behavior: processKey algorithm](../../../../../libitshell3-ime/02-design-docs/behavior/draft/v1.0-r1/01-processkey-algorithm.md).

**Path correction**: CTR-01 specified `../../../../../../libitshell3-ime/...` (6 levels of `../`). This is incorrect from the insertion point (`01-internal-architecture.md` in `v1.0-r5/`). The correct path uses 5 levels of `../`:

| `../` level | Resolves from | Resolves to |
|---|---|---|
| 1 | `v1.0-r5/` | `draft/` |
| 2 | `draft/` | `daemon/` |
| 3 | `daemon/` | `02-design-docs/` |
| 4 | `02-design-docs/` | `libitshell3/` |
| 5 | `libitshell3/` | `modules/` |

From `modules/`, `libitshell3-ime/02-design-docs/behavior/draft/v1.0-r1/01-processkey-algorithm.md` resolves correctly.

**Root cause of error**: The 6-level path in CTR-01 was correct from the CTR file's own location (inside `cross-team-requests/`, one directory deeper than `v1.0-r5/`), but incorrect for the target insertion point in `01-internal-architecture.md`.

---

## R3: Update Version Headers in All Four Docs

**Consensus**: 6/6

**Decision**: Update the version header in all four v1.0-r5 documents from `v0.4` to `v0.5` as the mandatory first step of the writing phase:

| Document | Current header | Updated header |
|---|---|---|
| `01-internal-architecture.md` | `Draft v0.4` | `Draft v0.5` |
| `02-integration-boundaries.md` | `v0.4` | `v0.5` |
| `03-lifecycle-and-connections.md` | `v0.4` | `v0.5` |
| `04-runtime-policies.md` | `v0.4` | `v0.5` |

**Rationale**: Per v1.0-r4 handover lesson: "Update version headers as a mandatory first step in the writing phase." This applies to all docs in the revision, not just docs with content changes.

---

## Wire Protocol Changes

None. CTR-01 is a documentation-only change affecting the daemon architecture diagram. No wire format, message types, or encoding changes.

## Items Deferred

| Item | Rationale |
|---|---|
| Phase 1 subgraph label precision (`libitshell3-ime` vs `input/`) | Pre-existing inaccuracy. The label identifies the library providing the engine implementation; the call site (`input/`) is documented in prose (line 128). Changing label semantics would exceed CTR-01 scope and could trigger broader discussion about all three phase labels. Defer to a future revision if needed. |

## Prior Art References

- IME behavior doc: `libitshell3-ime/02-design-docs/behavior/draft/v1.0-r1/01-processkey-algorithm.md` (the target of the cross-reference)
- Daemon module dependency rule: `01-internal-architecture.md` Section 1.1 (dependency inversion: `input/` depends on `core/` ImeEngine vtable, not concrete implementation)
