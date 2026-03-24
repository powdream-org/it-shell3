# Handover: Daemon v1.0-r7 to v1.0-r8

- **Date**: 2026-03-24
- **Author**: team lead

---

## Insights and New Perspectives

**Resolution traceability gap**: CTR-13 (silence detection timer) defined 6
cleanup triggers in a normative table (doc04 §11.6). The initial writers
propagated these to the new §11 section but did NOT update the existing code
paths that each trigger references (doc03 §3.3 client disconnect, doc03 §4.2
session detach, doc04 §8.2 eviction). Round 3 verification caught all 4 missing
propagation sites. Lesson: when a resolution adds a normative table that
references other sections, the writer must visit those sections and update them
— the table alone is not sufficient.

**Intra-procedure ordering is a cascade blind spot**: The V2-01 fix deferred
`engine.deactivate()` from step 4 to step 12 in `executePaneDestroyCascade()`.
Cascade analysis checked cross-document impact (low) but missed that step 6
(`close(pane.pty_fd)`) sits between steps 4 and 12 — creating a use-after-close
defect (V3-07). This wasted a full verification round. SIP-03 was filed and the
skill now requires an intra-procedure ordering check for any fix that reorders
steps.

**Pre-existing issues dominate late rounds**: Round 3 found 13 issues, but 10
were pre-existing (preedit ownership gaps in focus change, InputMethodSwitch,
client disconnect; missing silence cleanup; stale terminology). These were not
introduced by r7 — they existed in r6 but were not caught because r6 focused on
different CTRs. When integrating new features that touch existing procedures,
the existing procedures' completeness should be verified against the full
contract.

**preedit.session_id increment symmetry**: Round 4 revealed that pane-close and
`commit_current=false` paths omit `session_id` increment, while all other
preedit-ending paths include it. The pattern is now consistent: every path that
clears `preedit.owner` also increments `session_id`, except session-destruction
paths (where the counter has no downstream consumer).

## Design Philosophy

**Response-before-notification is universal**: The owner confirmed V3-13 —
resize orchestration must send `WindowResizeAck` before `LayoutChanged`, not
after. The response-before-notification rule applies to all request-triggered
response/notification pairs, including resize. Previously this was only
established for navigation (`NavigatePaneResponse` before `LayoutChanged`).

**Cleanup trigger propagation is not optional**: When a normative table defines
N cleanup triggers referencing N code paths, ALL N code paths must be updated in
the same writing round. Verification should not be the first place these gaps
are discovered.

**Session-destruction paths are a special case for state cleanup**: Fields like
`preedit.owner`, `current_preedit`, and `preedit.session_id` do not need
incrementing/clearing in session-destruction paths because the entire
`SessionEntry` is freed immediately after. However, `owner` and
`current_preedit` should still be cleared for consistency (implementor
readability), even if functionally unnecessary. `session_id` increment is
explicitly excluded — it implies a "next session" which does not exist.

## Owner Priorities

- **r8 is the big shift**: Owner reserved r8 for restructuring — splitting
  architecture/behavior docs and beginning implementation. The r7 cycle was
  specifically scoped to "finish deferred CTRs before the restructure."
- **Efficiency over thoroughness in late rounds**: Owner chose Phase-1-only
  verification for Round 4 and declared CLEAN based on "3 minor issues, fix and
  done." The cycle had already run 3 full rounds — diminishing returns.
- **Concrete explanations over abstract reasoning**: Owner explicitly said
  "couldn't understand those rationale" for abstract confirm/dismiss arguments.
  Concrete timelines and step-by-step traces were immediately effective.
  (SIP-04)
- **One contested issue at a time**: Owner said "show me one-by-one. I cannot
  put them all at once into my head." Batching 4 contested issues was
  overwhelming. (Now enforced in skill §5e)

## New Conventions and Procedures

Five SIPs were filed and applied to skill files during the retrospective:

- **SIP-01+02+04** → `steps/05-verification.md` §5e: Contested issues must be
  presented one-at-a-time with a 5-item mandatory checklist (file path, document
  text, confirm reasoning, dismiss reasoning, concrete breakdown).
- **SIP-03** → `steps/06-fix-round.md` §6b.3: Intra-procedure ordering check is
  mandatory when a fix reorders steps or adds conditional branches.
- **SIP-05** → `steps/07-commit-and-report.md` + `.claude/skills/adr/SKILL.md`:
  ADR status determination logic; revision-cycle ADRs are always Accepted.

Step 5 restructured: 5b.1 promoted to 5c, linear flow (discover → fast-path →
double-check → apply rules → re-raise check).

Step 6 restructured: 6a (record) → 6b (pre-fix analysis: sweep + cascade +
ordering check) → 6c (decide).

## Pre-Discussion Research Tasks

### r8 Scope (owner-declared, carried from r6 handover)

r8 is a major structural shift: **split daemon docs into two topics and begin
implementation**. First stated in the r6→r7 handover (§Owner Priorities item 2),
confirmed by owner during r7 ("r8 is reserved for the big shift"). The r7 cycle
completed all deferred CTRs; r8 starts from a clean baseline.

**Two new doc topics:**

- **`daemon-architecture/`** — Module decomposition, state tree, type
  definitions, integration boundaries, transport design. Covers the "what" —
  structural decisions that are stable once agreed.
- **`daemon-behavior/`** — Policies, lifecycles, state machines, event handling,
  startup/shutdown. Covers "how it should behave" — behavioral specifications
  that constrain implementation.

The exact section-to-topic mapping from the r6 handover is a starting point
only. r7 added new sections and restructured existing ones. The r8 team must
audit and reassign sections during discussion.

**Implementation transition:** Implementation details (pseudocode, step-by-step
procedures) move to source code in this round — code becomes the source of truth
for "how." Architecture docs retain structural design; behavior docs retain
behavioral specifications and constraints. Docs describe intent and invariants;
code implements them.

This is NOT a content revision — it is a reorganization + implementation
kickoff. The restructuring warrants its own revision cycle.

### Inputs for r8

1. **r7 spec docs** (v1.0-r7, committed): 4 verified daemon design docs
   - `01-internal-architecture.md` — State tree, Pane/Session structs, split
     tree, pane navigation, focus change pseudocode
   - `02-integration-boundaries.md` — ghostty API, libhangul, PTY, kqueue
   - `03-lifecycle-and-connections.md` — Startup/shutdown, SIGCHLD two-phase,
     pane destroy cascade, session destroy cascade, client lifecycle
   - `04-runtime-policies.md` — Resize, coalescing, preedit ownership, IME
     procedures, silence timer, health/stale model
2. **Section mapping** (from r6 handover): The owner provided preliminary
   section assignments for the two-topic split (see above). These are starting
   points, not final — the r8 team should validate and adjust during discussion.
3. **Secondary findings from Round 4** (unfixed, carry forward):
   - doc01 §5.2 Mermaid diagram omits `session_id` increment in focus-change
     note (consistency verifier secondary finding)
   - doc04 §8.4 `commit_current=true` branch missing `owner` clear and
     `session_id` increment (semantic verifier secondary finding)
4. **ADR 00045–00047**: Three new ADRs from r7 (two-phase SIGCHLD, edge
   adjacency navigation, non-configurable wrap-around). Implementation should
   reference these.

### Research before discussion

1. **Audit and assign sections**: Read all 4 r7 spec docs and classify each
   section as architecture (structural design) or behavior (procedures, state
   machines, ordering rules). Produce a concrete split proposal for the two new
   doc topics. The r6 handover's preliminary mapping is a starting point but may
   be outdated after r7 changes.

2. **Implementation readiness assessment**: Which sections are detailed enough
   to implement directly? Which need more specificity (e.g., exact error codes,
   buffer sizes, timeout values)?

3. **Code structure proposal**: How does the two-topic doc split map to Zig
   source layout? (e.g., `server/` for architecture types, `server/handlers/`
   for behavior procedures?)

4. **ghostty API gap analysis**: The daemon depends on ghostty APIs (Terminal,
   RenderState, bulkExport/importFlatCells, vtStream, etc.) that may not all be
   exported from `vendors/ghostty` yet. Audit which APIs the daemon design docs
   reference, check which are already exported in libghostty's public C API, and
   identify any that need new exports or wrappers. This work happens in
   `vendors/ghostty` and may require upstream coordination. Start from:
   - `docs/insights/ghostty-api-extensions.md` — API extensions from PoC 06–08
     (render_export.zig, bulkExport, importFlatCells, preedit overlay). Includes
     known gaps table and patch file references.
   - PoC 06 (RenderState extraction), PoC 07 (bulk export benchmark), PoC 08
     (re-injection + GPU rendering verification) — validated the export/import
     pipeline end-to-end.
