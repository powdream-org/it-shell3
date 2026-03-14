# Design Resolutions: IME Interface Contract v0.9 Changes

**Date**: 2026-03-14
**Team**: ime-expert, principal-architect, sw-architect, system-sw-engineer (4 members)
**Scope**: Review note 01 (Surface API references), CTR-02 (extract implementation content), CTR-03 (editorial policy), CTR-04 (section renumbering), owner requirement (consistency check)
**Execution order**: CTR-02 (remove content) -> CTR-04 (renumber) -> CTR-03 (editorial policy + scope statement)

**Source materials**:
- Review note 01: `draft/v1.0-r8/review-notes/01-surface-api-references-in-comments.md`
- CTR-02: `inbox/cross-team-requests/01-behavior-team-extract-impl-content-from-v1.0.md`
- CTR-03: `inbox/cross-team-requests/02-behavior-team-editorial-policy-from-v1.0.md`
- CTR-04: `inbox/cross-team-requests/03-behavior-team-renumber-sections-from-v1.0.md`

---

## Resolution 1: Apply CTR-02 — Extract Implementation Content (4/4 unanimous)

**Source**: CTR-02 (behavior team)
**Affected docs**: 01-overview.md, 02-types.md, 03-engine-interface.md, 04-ghostty-integration.md

### Decision

Apply all 7 removals specified in CTR-02. Replace each removed block with a cross-reference to the corresponding behavior doc (`behavior/draft/v1.0-r1/`). The removals are:

| # | Target Doc | Content Removed | Replacement Cross-Reference |
|---|-----------|-----------------|----------------------------|
| 1 | 01-overview.md (lines 57-67) | processKey() internal decision tree | `01-processkey-algorithm.md` |
| 2 | 01-overview.md (lines 71-92) | hangul_ic_process() return-false handling | `11-hangul-ic-process-handling.md` |
| 3 | 02-types.md (lines 125-158) | ImeResult scenario matrix + direct mode behavior | `02-scenario-matrix.md` |
| 4 | 02-types.md (lines 160-186) | Modifier flush policy body | `03-modifier-flush-policy.md` |
| 5 | 03-engine-interface.md (lines 128-153) | setActiveInputMethod internal step sequence | `10-hangul-engine-internals.md` Section 4 |
| 6 | 03-engine-interface.md (lines 159-248) | HangulImeEngine concrete struct (entire section) | `10-hangul-engine-internals.md` |
| 7 | 04-ghostty-integration.md (lines 17-31) | Buffer layout and sizing rationale | `10-hangul-engine-internals.md` Section 3 |

### Rationale

The interface contract is the caller-facing API spec consumed by the server/daemon team. Implementation details (libhangul API call sequences, internal decision trees, concrete struct fields, buffer layout) belong in the behavior docs. This separation was established in v0.8 and is now completed by removing the remaining implementation content.

### Additional Impacts

**1.1 Empty `## 2. Processing Pipeline` heading removal (4/4 unanimous)**

After removing items 1 and 2, the `## 2. Processing Pipeline` heading in `01-overview.md` has no remaining body content. Remove the heading entirely. The introductory one-liner (lines 53-54: "The daemon routes keys through a 3-phase pipeline...") provides useful reader context about where the IME engine fits in the overall pipeline. Fold this sentence into Section 1 (Overview) as a brief note, rather than discarding it.

**1.2 Dangling cross-reference fix in `03-engine-interface.md` (4/4 unanimous)**

Line 145 of `03-engine-interface.md` (Section 3.6 `setActiveInputMethod`) says "from the canonical registry (Section 3.7)". After Section 3.7 (HangulImeEngine) is removed by CTR-02 item 6, this reference becomes dangling. Update to: "from the canonical registry (see [behavior/draft/v1.0-r1/10-hangul-engine-internals.md](../../../behavior/draft/v1.0-r1/10-hangul-engine-internals.md), Section: Canonical Input Method Registry)."

**1.3 Canonical registry placement rationale (4/4 unanimous)**

The full canonical input method registry table (10-entry mapping to libhangul keyboard IDs) moves to the behavior doc with the rest of `HangulImeEngine`. The caller-facing information (naming convention, v1 scope of `"direct"` + `"korean_2set"`, management protocol) remains in `02-types.md` Section 3.4 (Input Method Identifiers). The server does not need the full libhangul keyboard ID mapping -- it only needs to know which input method strings are valid, and that is documented in Section 3.4.

**1.4 No impact on `99-appendices.md` (4/4 unanimous)**

The appendices are historical change logs. They reference old section numbers (e.g., "Section 3.7" in Appendix E.8, F.4) as retrospective records of what the section was called at the time of each change. These are frozen records and MUST NOT be updated with new section numbers.

**1.5 No impact on `05-extensibility-and-deployment.md` (4/4 unanimous)**

CTR-02 does not target any content in this file. The session persistence reference to `HangulImeEngine.init(allocator, input_method)` references the caller-facing constructor, not the concrete struct internals being removed.

**1.6 Shared Engine Invariant stays (4/4 unanimous)**

The "Shared Engine Invariant" paragraph in `04-ghostty-integration.md` (lines 36-39) is a caller-facing runtime invariant, not implementation detail. CTR-02 item 7 does not target it. It remains in the document.

---

## Resolution 2: Review Note 01 — Remove Surface API References (4/4 unanimous)

**Source**: Review note 01 (v0.8 verification team)
**Affected docs**: 02-types.md, 03-engine-interface.md

### Decision

Remove both Surface API references. Replace ghostty-specific API names with generic language. Do not delete the surrounding guidance -- the information is valuable, only the API names are out of place.

**Fix 1: `02-types.md` line 129 (`preedit_changed` doc comment)**

Current: "Callers MAY ignore this flag and call `ghostty_surface_preedit()` unconditionally as a safety fallback during debugging. This is always correct but wasteful -- see [Section 5](04-ghostty-integration.md#5-ghostty-integration) for details."

Change to: "Callers MAY ignore this flag and update preedit unconditionally as a safety fallback during debugging. This is always correct but wasteful." Remove the cross-reference to Section 5 (which is already a reference stub pointing to daemon docs) or update it to point to the daemon doc directly.

**Fix 2: `03-engine-interface.md` line 289 (MockImeEngine test example)**

Current: `test "committed text is sent to ghostty_surface_key"`

Change to: `test "committed text is forwarded to terminal"` (or similar -- no ghostty API name).

### Rationale

The interface contract established a clear headless architecture boundary in v0.8 -- the IME engine has no ghostty dependency. Surface API references, even in explanatory comments, create confusion about who calls ghostty APIs (the daemon, not the engine or the interface contract).

---

## Resolution 3: Apply CTR-04 — Renumber All Sections Per-Document Sequential (4/4 unanimous)

**Source**: CTR-04 (behavior team)
**Affected docs**: 01-overview.md, 02-types.md, 03-engine-interface.md, 04-ghostty-integration.md, 05-extensibility-and-deployment.md

### Decision

After CTR-02 is applied, renumber all sections in each document to start from 1 with sequential numbering. Each document is independent -- no cross-file numbering spans. All heading levels are promoted to `##` (H2) for top-level sections where currently at `###` (H3) due to the old cross-file "Section 3" parent heading.

**Target numbering scheme:**

**`01-overview.md`** (after CTR-02 removes Section 2):
```
## 1. Overview
### Design Principles
## 2. Responsibility Matrix
```

**`02-types.md`** (after CTR-02, headings promoted from ### to ##):
```
## 1. KeyEvent (Input to IME)
## 2. ImeResult (Output from IME)
## 3. Modifier Flush Policy
## 4. Input Method Identifiers
```

**`03-engine-interface.md`** (after CTR-02 removes HangulImeEngine, headings promoted from ### to ##):
```
## 1. ImeEngine (Interface for Dependency Injection)
## 2. setActiveInputMethod Behavior
## 3. MockImeEngine (For Testing)
```

**`04-ghostty-integration.md`** (after CTR-02 reduces buffer layout):
```
## 1. ghostty Integration
## 2. Memory Ownership
```

**`05-extensibility-and-deployment.md`**:
```
## 1. Future Extensibility
## 2. C API Boundary
## 3. Session Persistence
```

### 3.1 `03-engine-interface.md` — Flat Peer Sections, Not Nested (4/4 unanimous)

`setActiveInputMethod Behavior` and `MockImeEngine` are peer sections (§1, §2, §3), not subsections (§1, §1.1, §1.2) of ImeEngine.

Rationale:
- `setActiveInputMethod Behavior` is a substantial standalone specification with multiple cases, rationale, atomicity rules, and string ownership semantics. It is not subordinate to the vtable definition.
- `MockImeEngine` is a separate type definition that implements `ImeEngine`, not an elaboration of the `ImeEngine` definition.
- The daemon interacts with `setActiveInputMethod()` as a first-class operation (Phase 0 language toggle -> flush + switch). It deserves top-level section status.

### 3.2 `02-types.md` — Flat Peer Sections (4/4 unanimous)

By the same principle, the four sections in `02-types.md` are promoted to flat peer sections (§1, §2, §3, §4). The old "Section 3: Interface Types" parent heading that spanned both `02-types.md` and `03-engine-interface.md` is removed. Each document is self-contained.

### 3.3 Internal Cross-References to Update

After renumbering, the following internal cross-references within the interface-contract docs must be updated:

| Location | Current Reference | New Reference |
|----------|------------------|---------------|
| `02-types.md` (direct mode behavior) | "see Section 3.3" | "see Section 3" (Modifier Flush Policy in same doc) |
| `02-types.md` (preedit_changed comment) | "see [Section 5](04-ghostty-integration.md#5-ghostty-integration)" | Updated per Resolution 2 (reference removed or pointed to daemon docs) |
| `03-engine-interface.md` (setActiveInputMethod) | "(Section 3.7)" | Updated per Resolution 1.2 (pointed to behavior doc) |
| `01-overview.md` Document Index table | Old section descriptions | Updated to match new structure |
| All docs | Old anchor links (e.g., `#3-interface-types`, `#35-imeengine`) | Updated to match new heading anchors |

### 3.4 `99-appendices.md` Unaffected (4/4 unanimous)

The appendices use "Appendix A/B/C..." lettering, not section numbers. Historical section number references within appendix entries are NOT updated -- they document what the numbers were at the time of each change.

---

## Resolution 4: External Cross-Reference Breakage Catalogue (4/4 unanimous)

**Scope**: Documentation only (out of scope for v1.0-r9 edits)

### Decision

The following external documents contain plain-text "Section X.Y" references to interface-contract sections that will become stale after CTR-02 (removal) and CTR-04 (renumbering). These are out of scope for v1.0-r9 and must be documented in the handover for the daemon and protocol teams to fix in their next revision cycles.

**Protocol docs (v1.0-r12):**

| File | Line | Current Reference | Impact |
|------|------|------------------|--------|
| `04-input-and-renderstate.md` | 136 | "see IME contract Section 3.1" | Section 3.1 -> Section 1 in `02-types.md` |
| `04-input-and-renderstate.md` | 139 | "See IME Interface Contract Section 3.1" | Same as above |
| `04-input-and-renderstate.md` | 173 | "IME Interface Contract, Section 3.7" | Section 3.7 removed by CTR-02; point to `02-types.md` Section 4 (Input Method Identifiers) or behavior doc |
| `05-cjk-preedit-protocol.md` | 42 | "IME Interface Contract Section 3.7" | Same as line 173 |
| `05-cjk-preedit-protocol.md` | 52 | "IME Interface Contract, Section 3.7" | Same as line 173 |
| `05-cjk-preedit-protocol.md` | 304 | "IME Interface Contract, Sections 3.5-3.7" | Section 3.5 -> Section 1 in `03-engine-interface.md`; Section 3.7 removed |
| `05-cjk-preedit-protocol.md` | 314 | "IME Interface Contract, Section 3.7 (HangulImeEngine)" | Section 3.7 removed by CTR-02 |
| `05-cjk-preedit-protocol.md` | 735 | "IME Interface Contract v0.7, Section 3.3" | Historical ref to v0.7 -- may not need update |
| `06-flow-control-and-auxiliary.md` | 982 | "IME Interface Contract, Section 3.7" | Section 3.7 removed by CTR-02 |

**Daemon docs (v1.0-r3 through r5):**

| File | Line | Current Reference | Impact |
|------|------|------------------|--------|
| `04-runtime-policies.md` | 415 | "IME Interface Contract, Section 3.7" | Section 3.7 removed by CTR-02 |
| `02-integration-boundaries.md` | 369 | "IME contract v0.8 Section 6" | Section 6 -> Section 2 in `04-ghostty-integration.md` |
| `02-integration-boundaries.md` | 476 | "IME contract v0.8 Section 4 (Responsibility Matrix)" | Section 4 -> Section 2 in `01-overview.md` |
| `01-internal-architecture.md` | 452, 644 | "IME contract v0.8 Section 6", "IME contract v0.7 Section 5" | Section 6 -> Section 2 in `04-ghostty-integration.md`; Section 5 -> Section 1 in `04-ghostty-integration.md` |

**Behavior docs (v1.0-r1):**

References to v1.0-r8 section numbers (e.g., "§3.2") in provenance metadata are historical and do not need updating.

### Rationale

Each team owns their own documents. The interface-contract team should not modify protocol or daemon docs. The handover provides the stale reference catalogue so those teams can fix them efficiently in their next revision.

---

## Resolution 5: Apply CTR-03 — Editorial Policy and Scope Statement (4/4 unanimous)

**Source**: CTR-03 (behavior team)
**Affected docs**: 01-overview.md
**Constraint**: Apply AFTER CTR-02 and CTR-04

### Decision

Add a scope statement to `01-overview.md` immediately after the Document Index table:

> **Scope**: This document set covers the caller-facing API only. For engine implementation details (internal algorithms, libhangul API usage, buffer layout, struct fields), see [behavior/](../../../behavior/).

Make the `behavior/` reference a relative link for navigability.

The normative editorial policy (CTR-03 Section 2) is an authoring/review-time rule. It should be stated once in `01-overview.md` as a brief note following the scope statement, not repeated in every file.

### Rationale

Readers and future authors need an upfront statement of what belongs in the interface contract vs. the behavior docs. The scope statement prevents implementation details from re-entering the interface contract in future revisions.

---

## Resolution 6: Section Numbering Consistency Check (4/4 unanimous)

**Source**: Owner additional requirement

### Decision

After all CTRs are applied, verify that the 5 interface-contract docs satisfy all of the following:

1. Each document starts from Section 1 with sequential numbering (no gaps, no duplicates)
2. Subsections use dot notation (1.1, 1.2, etc.) where applicable
3. All internal cross-references (within and across the 5 docs) use the new section numbers
4. All markdown anchor links match the new heading text
5. The Document Index table in `01-overview.md` accurately reflects the final structure (section numbers and titles)
6. No stale references to removed sections (e.g., "Section 3.7")

**Scope**: The 5 interface-contract docs only (`01` through `05`). `99-appendices.md` uses appendix lettering and is unaffected. External documents (daemon, protocol, behavior) are out of scope -- stale references are catalogued in Resolution 4.

**Process**: The consistency check should be performed by a team member who did NOT write the docs they are checking (fresh eyes catch what authors miss).

---

## Resolution 7: Document Assignment for Writing (Step 3.5) (4/4 unanimous)

### Decision

| Document | Assigned To | Scope of Changes |
|----------|-------------|-----------------|
| `02-types.md` | ime-expert | CTR-02 items 3-4 (scenario matrix + flush policy removal), Review Note 01 fix 1, CTR-04 renumbering + heading promotion |
| `03-engine-interface.md` | ime-expert | CTR-02 items 5-6 (setActiveInputMethod internals + HangulImeEngine removal + dangling ref fix), Review Note 01 fix 2, CTR-04 renumbering + heading promotion |
| `04-ghostty-integration.md` | system-sw-engineer | CTR-02 item 7 (buffer layout -> one-liner + cross-ref), CTR-04 renumbering |
| `01-overview.md` | To be assigned | CTR-02 items 1-2 (decision tree + return-false removal + heading removal + pipeline one-liner fold), CTR-04 renumbering, CTR-03 scope statement + editorial policy |
| `05-extensibility-and-deployment.md` | To be assigned | CTR-04 renumbering only |
| `99-appendices.md` | No changes | Frozen historical records |
| Version headers (all docs) | All writers | Update version from v0.8 to v0.9, update date |
| Document Index update | `01-overview.md` writer | Update table to match new structure |
| Consistency check | Non-writer (fresh eyes) | Per Resolution 6 criteria |

### Rationale

- ime-expert owns the IME contract and has deep domain expertise with the engine vtable, libhangul internals, and the caller-facing vs. implementation boundary -- critical for the heaviest changes in `02-types.md` and `03-engine-interface.md`.
- system-sw-engineer has runtime integration expertise well-suited for the memory ownership and buffer lifetime content in `04-ghostty-integration.md`.
- `01-overview.md` and `05-extensibility-and-deployment.md` are available for sw-architect or principal-architect.
- sw-architect recommended that whoever takes `03-engine-interface.md` should also take `02-types.md` since the old "Section 3" numbering spanned both files.

---

## Items Deferred

None. All input items (Review Note 01, CTR-02, CTR-03, CTR-04, owner consistency check requirement) are addressed in this revision cycle.
