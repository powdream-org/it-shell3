# Migration Plan: Design Doc Structure Alignment

**Date**: 2026-03-14
**Scope**: All three design doc topics — server-client-protocols, interface-contract, daemon

---

## Background

The document artifact convention (`docs/conventions/artifacts/documents/01-overview.md`) was
established after several revision cycles had already been completed. Existing docs do not
conform to the new structure or naming rules.

**Key model clarification**: `v0.1`–`v0.11` (protocol), `v0.1`–`v0.8` (IME), `v0.1`–`v0.4`
(daemon) are all **draft rounds of v1.0**, not independent versioned specs. No stable version
has been declared. Therefore:

- No `inbox/` directory exists yet — created only when stable is declared
- No `v1.0/` stable directory exists yet
- Mapping: `v0.X/` → `draft/v1.0-rX/`

---

## Change Categories

### A — Top-level directory structure (all modules)

```
{topic}/v0.X/  →  {topic}/draft/v1.0-rX/
```

### B — Subdirectory structure (early rounds have flat files)

Early rounds placed process artifacts directly at version root. These need subdirectories:
`handover/`, `review-notes/`, `design-resolutions/`, `research/`

### C — File renaming (naming convention violations)

1. **Handover**: `handover-to-v0.X.md` / `handover-for-vXX-revision.md` → `handover-to-rX.md`
2. **Design-resolutions**: embedded-verb filenames or missing numeric prefix → `NN-{topic}.md`
3. **Review-notes**: missing numeric prefix, inconsistent format → `NN-{topic}.md`
4. **Misclassified artifacts**: files with wrong artifact type (see section below)

### D — Misplaced files (wrong team's folder)

One file in IME r5 is a cross-team request that belongs in the protocol team's folder.

---

## Misclassified / Ambiguous Files — Confirmed Classification

| File | Current location | Actual artifact type | Migration target |
|------|-----------------|----------------------|-----------------|
| `review-resolutions.md` | protocol r1, r3 (root) | **design-resolutions** — team consensus on review issues | `design-resolutions/01-review-resolutions.md` |
| `review-report.md` | IME r3 (root) | **design-resolutions** — cross-document consistency review (protocol v0.4 × IME v0.3) | `design-resolutions/01-cross-review-protocol-r4.md` |
| `review-notes-01.md` | IME r4 (root) | **review-notes** — 5 open issues for v0.5, single file covering multiple topics | `review-notes/01-interface-contract-issues.md` |
| `protocol-changes-for-v06.md` | IME r5 (root) | **cross-team-request** FROM IME team TO protocol team — misplaced in source team's folder | Move to `protocol/draft/v1.0-r6/cross-team-requests/01-ime-composition-state-changes.md` and remove from IME r5 |

---

## Module 1: server-client-protocols

Base path: `docs/modules/libitshell3-protocol/02-design-docs/server-client-protocols/`

### A — Directory renames

| Current | New |
|---------|-----|
| `v0.1/` | `draft/v1.0-r1/` |
| `v0.2/` | `draft/v1.0-r2/` |
| `v0.3/` | `draft/v1.0-r3/` |
| `v0.4/` | `draft/v1.0-r4/` |
| `v0.5/` | `draft/v1.0-r5/` |
| `v0.6/` | `draft/v1.0-r6/` |
| `v0.7/` | `draft/v1.0-r7/` |
| `v0.8/` | `draft/v1.0-r8/` |
| `v0.9/` | `draft/v1.0-r9/` |
| `v0.10/` | `draft/v1.0-r10/` |
| `v0.11/` | `draft/v1.0-r11/` |

### B+C — Subdirectory creation + file moves + renames

**r1 (was v0.1):**
- `review-notes-01-protocol-overview.md` → `review-notes/01-protocol-overview.md`
- `review-resolutions.md` → `design-resolutions/01-review-resolutions.md`

**r2 (was v0.2):**
- `review-notes-02-encoding-and-fps.md` → `review-notes/01-encoding-and-fps.md` *(01- not 02- — it's the first note in r2)*

**r3 (was v0.3):**
- `review-notes-01-protocol-overview.md` → `review-notes/01-protocol-overview.md`
- `review-resolutions.md` → `design-resolutions/01-review-resolutions.md`

**r4 (was v0.4):**
- `handover-for-v05-revision.md` → `handover/handover-to-r5.md`
- `review-notes-01-protocol-overview.md` → `review-notes/01-protocol-overview.md`
- `review-notes-cross-review-ime.md` → `review-notes/02-cross-review-ime.md`

**r5 (was v0.5):**
- `handover-for-v06-revision.md` → `handover/handover-to-r6.md`
- `handover-identifier-consensus.md` → `handover/handover-identifier-consensus.md` *(supplementary — keep as-is under handover/)*
- `review-notes-01-per-client-focus-indicators.md` → `review-notes/01-per-client-focus-indicators.md`
- `review-notes-consistency.md` → `review-notes/02-consistency.md`
- *(receive incoming CTR from IME r5)* → `cross-team-requests/01-ime-composition-state-changes.md` *(moved FROM IME r5)*

**r6 (was v0.6):**
- `design-resolutions-resize-health.md` → `design-resolutions/01-resize-health.md`
- `research-tmux-resize-health.md` → `research/01-tmux-resize-health.md`
- `research-zellij-resize-health.md` → `research/02-zellij-resize-health.md`
- `handover/handover-to-v0.7.md` → `handover/handover-to-r7.md`

**r7 (was v0.7):**
- `handover/handover-to-v0.8.md` → `handover/handover-to-r8.md`

**r8 (was v0.8):**
- `handover/handover-to-v0.9.md` → `handover/handover-to-r9.md`

**r9 (was v0.9):**
- `handover/handover-to-v0.10.md` → `handover/handover-to-r10.md`

**r10 (was v0.10):**
- `handover/handover-to-v0.11.md` → `handover/handover-to-r11.md`

**r11 (was v0.11):**
- `handover/handover-to-v012.md` → `handover/handover-to-r12.md` *(also fixes typo: v012 → r12)*

---

## Module 2: interface-contract

Base path: `docs/modules/libitshell3-ime/02-design-docs/interface-contract/`

### A — Directory renames

| Current | New |
|---------|-----|
| `v0.1/` | `draft/v1.0-r1/` |
| `v0.2/` | `draft/v1.0-r2/` |
| `v0.3/` | `draft/v1.0-r3/` |
| `v0.4/` | `draft/v1.0-r4/` |
| `v0.5/` | `draft/v1.0-r5/` |
| `v0.6/` | `draft/v1.0-r6/` |
| `v0.7/` | `draft/v1.0-r7/` |
| `v0.8/` | `draft/v1.0-r8/` |

### B+C — Subdirectory creation + file moves + renames

**r3 (was v0.3):**
- `handover-for-v04-revision.md` → `handover/handover-to-r4.md`
- `review-notes-cross-review.md` → `review-notes/01-cross-review.md`
- `review-report.md` → `design-resolutions/01-cross-review-protocol-r4.md` *(reclassified: cross-doc consistency review findings)*

**r4 (was v0.4):**
- `handover-for-v05-revision.md` → `handover/handover-to-r5.md`
- `handover-identifier-consensus.md` → `handover/handover-identifier-consensus.md` *(supplementary — keep as-is under handover/)*
- `review-notes-01.md` → `review-notes/01-interface-contract-issues.md`

**r5 (was v0.5):**
- `handover/handover-to-v06.md` → `handover/handover-to-r6.md`
- `protocol-changes-for-v06.md` → **DELETE from IME r5** *(this is a CTR targeting protocol team — moved to protocol/draft/v1.0-r6/cross-team-requests/01-ime-composition-state-changes.md)*

**r6 (was v0.6):**
- `design-resolutions-per-tab-engine.md` → `design-resolutions/01-per-tab-engine.md`
- `handover/handover-to-v0.7.md` → `handover/handover-to-r7.md`

**r7 (was v0.7):**
- `handover/handover-to-v0.8.md` → `handover/handover-to-r8.md`

**r8 (was v0.8):**
- `handover/handover-to-v09.md` → `handover/handover-to-r9.md` *(also fixes missing dot)*

---

## Module 3: daemon

Base path: `docs/modules/libitshell3/02-design-docs/daemon/`

### A — Directory renames

| Current | New |
|---------|-----|
| `v0.1/` | `draft/v1.0-r1/` |
| `v0.2/` | `draft/v1.0-r2/` |
| `v0.3/` | `draft/v1.0-r3/` |
| `v0.4/` | `draft/v1.0-r4/` |

### C — File renames only (subdirectory structure already correct)

**r1 (was v0.1):**
- `handover/handover-to-v0.2.md` → `handover/handover-to-r2.md`

**r2 (was v0.2):**
- `design-resolutions/01-v0.2-review-note-resolutions.md` → `design-resolutions/01-review-note-resolutions.md` *(drop version prefix)*
- `handover/handover-to-v0.3.md` → `handover/handover-to-r3.md`

**r3 (was v0.3):**
- `handover/handover-to-v04.md` → `handover/handover-to-r4.md` *(also fixes missing dot)*

**r4 (was v0.4):**
- `design-resolutions/design-resolutions-v04.md` → `design-resolutions/01-v04-resolutions.md` *(add numeric prefix)*
- `handover/handover-to-v05.md` → `handover/handover-to-r5.md` *(also fixes missing dot)*

---

## Additional: `docs/daemon/` Loose Files

Three files exist outside any module structure:
- `docs/daemon/01-session-persistence.md`
- `docs/daemon/02-pty-management.md`
- `docs/daemon/03-multiplexer-keybindings.md`

These appear to be legacy docs predating `modules/libitshell3/02-design-docs/daemon/`.
**Action needed**: Verify whether content is superseded by daemon module docs. If yes, delete.
If still referenced, evaluate whether to keep in place or remove. **Do not migrate until verified.**

---

## Files NOT Changed (already compliant)

- All spec docs (`01-*.md` through `06-*.md`, `99-*.md`) — filenames correct
- All `verification/round-N-issues.md` files — already follow convention
- `TODO.md` files — already follow convention
- Protocol r7–r11 `review-notes/NN-{topic}.md` — already in subdirectory with correct naming
- Daemon r1–r4 `review-notes/NN-{topic}.md` — already correct
- Most `cross-team-requests/NN-{source-team}-{topic}.md` — already correct in r6+

---

## Complete Change Summary

| Module | Dir renames | File moves | File renames | Deletions |
|--------|-------------|------------|--------------|-----------|
| protocol | 11 | 11 | 17 | 0 |
| IME | 8 | 9 | 8 | 1 |
| daemon | 4 | 0 | 7 | 0 |
| **Total** | **23** | **20** | **32** | **1** |

---

## Execution Order

1. **Protocol module** (largest, most complex):
   - Create `draft/` directory
   - `git mv v0.1 → draft/v1.0-r1` ... `git mv v0.11 → draft/v1.0-r11` (11 moves)
   - Create missing subdirectories inside r1–r6
   - Move flat files into subdirectories
   - Rename files per C table above

2. **IME module**:
   - Create `draft/` directory
   - `git mv v0.1 → draft/v1.0-r1` ... `git mv v0.8 → draft/v1.0-r8` (8 moves)
   - Create missing subdirectories inside r3–r6
   - Move flat files + reclassify ambiguous artifacts
   - Delete `protocol-changes-for-v06.md` from r5 (already added to protocol r6)

3. **Daemon module**:
   - Create `draft/` directory
   - `git mv v0.1 → draft/v1.0-r1` ... `git mv v0.4 → draft/v1.0-r4` (4 moves)
   - Rename files per C table above

4. **Verify `docs/daemon/` loose files** — decide keep/delete separately

5. **Commit**: `chore(docs): migrate design docs to draft/v1.0-rX structure`
