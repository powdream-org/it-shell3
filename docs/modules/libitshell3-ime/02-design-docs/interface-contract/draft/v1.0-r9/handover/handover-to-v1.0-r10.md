# Handover: IME Interface Contract v1.0-r9 to v1.0-r10

- **Date**: 2026-03-22 (updated; originally 2026-03-15)
- **Author**: team leader

---

## What Was Done in v1.0-r9

v1.0-r9 applied three cross-team requests from v1.0-r8:

- **CTR-02**: Removed implementation content (internal decision trees, libhangul
  API call sequences, concrete struct fields) from the interface contract and
  replaced with cross-references to the behavior docs.
- **CTR-03**: Added editorial policy scope statement (caller-facing API only;
  impl details → behavior docs).
- **CTR-04**: Renumbered all sections per-document sequentially (removed the old
  3.1–3.8 monolithic numbering).

Two issues were found and fixed in verification (Round 1): a broken cross-module
link (C-MINOR-01) and a libhangul-internal note violating editorial policy
(S-MINOR-01). Round 2 was CLEAN after one contested issue (MockImeEngine
deactivate no-op) was dismissed by owner as non-normative.

## Post-Commit Editorial Cleanup (This Session)

After the formal v1.0-r9 commit, significant editorial cleanup was applied
directly to the v1.0-r9 files:

- **Metadata blocks removed**: Version/Date/Part of/Changes from blocks removed
  from all 6 spec docs. No value, hard to maintain.
- **Version labels removed from titles**: `v1.0-r9` removed from all h1
  headings. Version is encoded in the directory path.
- **Out-of-scope content removed**: Pipeline context note (daemon 3-phase
  routing), daemon responsibility reference from the Responsibility Matrix
  intro.
- **Fragile links replaced**: All cross-module and cross-revision-cycle links
  (exact file paths with revision numbers) replaced with loose prose references.
  See new convention in AGENTS.md.
- **Appendices pruned and renumbered**: Removed stale/superseded content
  (Appendix A stale doc tracking, Appendix D ghostty integration changelog,
  E.4–E.9, G.2–G.6, C.5/C.6/C.9/C.10). Renumbered A–K → A–H.
- **deno fmt applied**: PostToolUse hook added; all 6 spec docs formatted.

## Insights and New Conventions

**Cross-document reference policy** (now in AGENTS.md): The deciding factor for
link style is whether two documents share a revision cycle, not whether they are
in the same module.

- Same revision cycle (files within the same `draft/vX.Y-rN/`): relative paths
  OK.
- Independent revision cycles (interface-contract → behavior, or any
  cross-module reference): use loose prose. Name the target doc without a path;
  omit section numbers.

**Appendices as ADR candidates**: Several appendices contain content well-suited
for ADRs — B.2 (Modifier Flush Policy: FLUSH not RESET), D.1–D.7 (Single string
identifier consensus), F.1 (Per-session engine ownership), F.5 (Hanja
exclusion), F.6 (Dead keys as separate engine), G.1 (composition_state removal).
ADR tooling is under evaluation; see ADR research notes from this session.

## Owner Priorities

- **Incoming CTR from protocol team must be applied in r10.** The protocol team
  filed `cross-team-requests/01-protocol-engine-decomposition.md` (from protocol
  v1.0-r12) with two required changes:
  1. **Engine constructor — decomposition responsibility**: Document in
     `03-engine-interface.md` that the engine constructor is the sole location
     where `input_method` string is decomposed into engine-specific types. The
     string flows unchanged from client → server → engine constructor. No code
     outside the constructor examines or transforms it.
  2. **Per-session engine — preedit exclusivity invariant**: Document that at
     most one pane in a session can have active preedit at any time (single
     `HangulInputContext` with one jamo stack per engine instance).

- The appendix pruning removed historical changelog entries that referenced
  features subsequently removed (composition_state, LanguageId, ghostty
  integration detail). If future contributors need that history, it is
  recoverable from git log.

- **Stale external cross-references**: Resolution 4 of
  `design-resolutions/01-v09-changes.md` catalogues all external documents
  (protocol, daemon) that reference old section numbers. The protocol and daemon
  teams should fix these in their next revision cycles. This is informational
  for r10, not actionable by the interface-contract team.

## Pre-Discussion Research Tasks

None beyond the CTR. The CTR content is self-contained with reference text from
the removed protocol sections — no additional research needed.
