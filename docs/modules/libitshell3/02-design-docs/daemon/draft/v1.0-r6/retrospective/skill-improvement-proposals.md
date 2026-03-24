# Skill Improvement Proposals — Daemon v1.0-r6

## Proposal 1: Systematic ADR extraction from resolution documents

**Problem**: Design discussions produce architectural decisions (e.g., SEM-A
resolved "Session-level preedit ownership, not per-pane") that are ADR-worthy
but get buried in resolution docs. ADRs only get written when someone manually
notices, which is ad hoc and lossy.

**Proposed change to `design-doc-revision` skill**:

1. **Step 3 (Resolution)**: The resolution writer tags decisions as
   `[ADR-CANDIDATE]` when the decision is architectural (changes a data
   structure, selects between named alternatives, or establishes a permanent
   constraint).
2. **Step 7 (Commit & Report)**: The team leader reviews tagged candidates and
   runs `/adr` for each confirmed candidate before or after committing.

**Raised by**: owner (during v1.0-r6 Step 2→3 transition)

## Proposal 2: Fast-path resolution doc issues during verification

**Problem**: Verification Phase 1/2 agents flag errors in the resolution
document (wrong section references, stale counts, wrong target doc names) as
spec issues. These go through the full confirm/dismiss cycle and clutter the fix
round, but resolution docs are process artifacts — not shipped specs. Fixing
them is trivial and doesn't need a full verification round.

**Proposed change to `design-doc-revision` skill**:

Keep resolution docs in the verification scope (they can still have real
errors), but add a fast-path for resolution doc issues:

1. **Step 5 (Verification)**: After Phase 1, the team leader separates
   resolution doc issues from spec doc issues before passing to Phase 2.
2. **Resolution doc issues**: Report to owner immediately with a "fix now or
   dismiss?" prompt. The team leader applies the owner's decision on the spot —
   no Phase 2 review needed. Record as "resolution doc fix — fast-pathed" in the
   issues file.
3. **Spec doc issues**: Continue through Phase 2 as normal.

**Raised by**: owner (during v1.0-r6 Round 1 verdict review)

## Proposal 3: Show actual content when presenting contested issues to owner

**Problem**: When the team leader presents verification verdicts to the owner
for contested issues, the summary table shows only a one-line abstract
description (e.g., "doc02 §4.1 pseudocode uses wrong field names"). The owner
cannot make a correct judgment from this — they need to see the actual captured
content from the documents to understand what the issue is and why the reviewers
disagree.

**Proposed change to `design-doc-revision` skill**:

When presenting contested or owner-decision issues in Step 5/6:

1. **Show the actual text** from the document (quoted, with line numbers) for
   each contested issue — not just a summary.
2. **Show both reviewers' reasoning** side by side (the confirm argument and the
   dismiss argument with their specific evidence).
3. **Only then** ask the owner for a decision.

The one-line summary table is fine for confirmed/dismissed issues (no owner
action needed), but contested items require full context for the owner to judge
correctly.

**Raised by**: owner (during v1.0-r6 Round 2 verdict review)

## Proposal 4: Fix round writers grouped by issue cluster, not by doc

**Problem**: In fix rounds (Round 2+), the team leader assigned one writer per
doc — the same pattern as the initial writing phase. When a single issue spans
multiple docs (e.g., SEM-05 touching mouse diagrams in doc01 §5.2 and doc02
§4.8), parallel writers make independent judgment calls that diverge. In v1.0-r6
Round 2, fix2-doc01 changed MouseScroll/MouseMove to `terminal.mouse*(event)`
while fix2-doc02 kept `write(pty_fd, ...)` based on a belief that ghostty lacks
a scroll API. This created a new inconsistency caught in Round 3.

**Proposed change to `design-doc-revision` skill**:

1. **Step 4 (initial writing)**: Keep one writer per doc — CTRs are independent.
2. **Step 4 (fix rounds, Round 2+)**: Group fixes by **issue cluster**, not by
   doc. One writer per cluster, even if the cluster spans multiple docs. A
   cluster is a set of issues that share a topic or where fixing one affects the
   others (e.g., all mouse diagram issues, all lock language issues).
3. **Same-class sweep**: After confirming a cross-doc fix issue, the team leader
   must identify all related locations across all docs and assign them to the
   same writer. Do not skip the sweep for "simple" fixes — SEM-05 looked simple
   but required a design judgment that diverged across writers.

**Raised by**: owner (during v1.0-r6 Round 3 cascade analysis)
