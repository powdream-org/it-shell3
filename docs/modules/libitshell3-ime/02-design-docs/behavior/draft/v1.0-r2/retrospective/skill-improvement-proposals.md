# Skill Improvement Proposals — v1.0-r2 / v1.0-r10 Cycle

Procedural issues found during the behavior v1.0-r2 + interface-contract
v1.0-r10 joint revision cycle (2026-03-22).

---

## 1. Missing Owner Review Step

**Problem**: The skill goes Step 7 (Commit & Report) → Step 8 (Retrospective)
with no explicit owner review step. The owner should review committed docs and
raise issues before the cycle closes.

**Evidence**: The v1.0-r1 TODO had a "Phase 6: Review Cycle (4.x)" but the
step-driven skill restructure lost this as an explicit step.

**Proposed fix**: Add a new Step 7.5 or renumber: Step 7 (Commit) → Step 8
(Owner Review) → Step 9 (Retrospective). Step 8 should STOP and wait for the
owner to review. Any issues raised become review notes for the next revision.

---

## 2. Stale Shutdown Request Poisoning

**Problem**: When an agent is shut down in Step 3 and a new agent with the same
name is spawned in Step 4, the new instance can process the stale shutdown
request from Step 3, causing premature shutdown.

**Evidence**: sw-architect was respawned for Step 4 writing but immediately shut
down because it processed the Step 3 shutdown request
(`shutdown-1774177374876@sw-architect`).

**Proposed fix**: Document this as a known hazard in Step 4. Workaround: use
distinct names for agents across steps (e.g., `sw-architect-writer` in Step 4),
or instruct agents to ignore shutdown requests they didn't expect.

---

## 3. Same-Class Sweep Heuristic Missing

**Problem**: Stale cross-module links were found one file at a time across 3
verification rounds (R1: `10-hangul-engine-internals.md`, R3:
`11-hangul-ic-process-handling.md`). A comprehensive sweep should have been
triggered after the first instance.

**Evidence**: Round 3 could have been avoided entirely if a sweep had been done
after Round 1's V1-01 fix.

**Proposed fix**: Add a heuristic to Step 6 (Fix Round Decision): "If a
confirmed issue belongs to a class that could repeat across other files (e.g.,
stale cross-module links, stale section references), spawn a sweep agent to
check all files for the same class before the next verification round."

---

## 4. No Scope Guidance for Pre-existing Issues

**Problem**: Round 2 verifiers found 5 issues, all pre-existing from v1.0-r1.
The skill doesn't distinguish "issues introduced by this cycle" from
"pre-existing issues found during verification." No guidance exists for whether
to fix them or defer.

**Evidence**: All 5 Round 2 issues required owner escalation to decide. The deep
reviewer had to manually check git history to determine pre-existing status.

**Proposed fix**: Add verifier instructions to flag pre-existing issues
explicitly. Add Step 6 guidance: "Pre-existing issues MAY be deferred at owner
discretion without counting toward the round threshold. If the owner chooses to
fix them, they are treated as normal confirmed issues."

---

## 5. Cascade Analysis Not in Standard Flow

**Problem**: The cascade analysis performed before fixing Round 2 issues was the
owner's initiative, not part of the standard skill flow. It proved valuable —
identifying that all 5 fixes were safe and surfacing the `02-scenario-matrix.md`
cascade for SEM-4.

**Evidence**: Without the cascade analysis, Fix 5 (SEM-4) would have missed the
matching "Exception" text in `02-scenario-matrix.md`, causing a Round 3
re-raise.

**Proposed fix**: Add cascade analysis as a mandatory sub-step in Step 6 before
entering the fix round: "Before spawning fix writers, spawn a cascade analysis
agent (opus) to assess each confirmed issue's fix impact across all documents.
Include the cascade report in the fix writers' input."

---

## 6. Joint Verification Round Counting Mismatch

**Problem**: Both targets shared verification rounds, but the IC had far fewer
issues. The IC TODO's round counting is artificially inflated because it was
dragged along by behavior doc rounds.

**Evidence**: IC had 1 issue in Round 1, 0 in Round 2, 0 in Round 3. But the
TODO shows 3 full verification rounds.

**Proposed fix**: For joint revision cycles, allow independent round counts per
target. If one target is clean, it can proceed to commit independently while the
other continues fix rounds. Alternatively, accept that joint cycles share round
counts and document this as expected behavior.
