# Handover: Daemon v1.0-r6 to v1.0-r7

- **Date**: 2026-03-24
- **Author**: team leader

---

## Insights and New Perspectives

**Parallel fix writers diverge on cross-doc judgment calls.** When two writers
independently fix the same conceptual issue (e.g., mouse API naming) across
different docs, they make different judgment calls — one checked the ghostty
API, the other assumed it didn't exist. This produced a Round 3 cascade. The
lesson: cross-doc fixes must be assigned to a single writer per issue cluster,
not per doc. Same-class sweeps are mandatory before spawning fix writers, even
for "simple" fixes.

**Resolution documents are process artifacts, not specs.** Three Round 1 issues
(wrong section reference, wrong target doc, stale count) were in the resolution
doc, not the spec. They went through the full Phase 2 confirm/dismiss cycle,
wasting tokens. Resolution doc issues should be fast-pathed to the owner for
immediate fix/dismiss, bypassing Phase 2.

**Owner needs actual content to judge contested issues.** One-line summary
tables are insufficient for contested verification issues. The owner cannot make
a correct judgment without seeing the actual document text and both reviewers'
reasoning. This was surfaced when TRM-01 and SEM-05 required the owner to ask
for clarification before they could decide.

**ghostty has more mouse APIs than expected.** Investigation during Round 3
confirmed ghostty provides `mouse_button()`, `mouse_scroll()`, `mouse_pos()`,
and `mouse_pressure()` (Force Touch). The daemon docs initially assumed only
`mousePress()` existed. Pressure is macOS-only Force Touch for word selection —
no PTY output, no protocol relevance.

## Design Philosophy

**Single-threaded means no locks, anywhere.** The CTR-11 writer introduced
"per-session lock" language in doc04 §8, contradicting the single-threaded
architecture stated in doc01/02/03. Three verification rounds were needed to
fully remove all lock references across all docs. Any future procedure writing
must use "the single-threaded event loop provides implicit serialization" —
never mention locks, mutexes, or atomicity primitives.

**Preedit ownership is session-level, not pane-level.** The SEM-A resolution
eliminated `PanePreeditState` and moved ownership to a `PreeditState` sub-struct
on `Session`. The per-session IME engine prevents multi-pane simultaneous
composition; `PreeditState.owner` handles multi-client contention on the focused
pane. These are orthogonal concerns that were previously conflated.

## Owner Priorities

1. **v1.0-r7: Deferred CTRs.** 4 CTRs deferred from r6:
   - CTR-13: Silence detection timer
   - CTR-14: Session destroy cascade and rename broadcast
   - CTR-18: Pane process exit cascade — sequence diagram
   - CTR-19: Pane navigation algorithm

2. **v1.0-r8: Doc restructuring + implementation start.** The owner wants to
   split daemon docs into two topics and begin coding:
   - `daemon-architecture/` — Module decomposition, state tree, type
     definitions, integration boundaries, transport design (currently doc01 §1-4
     §6-7, doc02 all, doc03 §4-5 §7-8)
   - `daemon-behavior/` — Policies, lifecycles, state machines, event handling,
     startup/shutdown (currently doc03 §1-3 §6, doc04 all)
   - Strip implementation details (pseudocode, procedures) from docs as actual
     code is written — code becomes the source of truth for "how", docs retain
     "what" (architecture) and "how it should behave" (behavioral specs)
   - This is a major restructuring that warrants its own revision cycle

## New Conventions and Procedures

- **ADR candidates tagged in resolutions.** The resolution writer tags
  architectural decisions with `[ADR-CANDIDATE]`; the team leader harvests them
  via `/adr` at commit time (Step 3 + Step 7 of design-doc-revision skill).
- **Resolution doc issues fast-pathed.** After Phase 1 verification, resolution
  doc issues go directly to the owner for fix/dismiss — no Phase 2 needed (Step
  5 of design-doc-revision skill).
- **Contested issues shown with full context.** The team leader must show actual
  document text and both reviewers' reasoning for contested issues, not one-line
  summaries (Step 5 anti-pattern).
- **Fix writers grouped by issue cluster.** In fix rounds, assignments are by
  issue cluster (not by doc) with file conflict scheduling. Mandatory same-class
  sweep for cross-doc issues (Steps 4 + 6 of design-doc-revision skill).
- **ADR 00043** (binary split tree as sole pane layout model) written during
  this cycle.

## Pre-Discussion Research Tasks

1. **CTR-19 pane navigation**: The algorithm needs to handle binary split tree
   navigation (directional: up/down/left/right from focused pane). Research
   tmux's `window_pane_find_up/down/left/right` implementation and ghostty's
   split navigation for precedent.

2. **CTR-18 pane exit cascade**: Verify the complete sequence from SIGCHLD
   through pane removal, tree compaction, focus transfer, and client
   notification. The sequence diagram should cover both "last pane in session"
   (session destroy) and "non-last pane" (tree rebalance) cases.
