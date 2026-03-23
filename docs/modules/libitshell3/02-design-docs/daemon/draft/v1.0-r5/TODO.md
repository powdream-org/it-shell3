# Daemon Design v1.0-r5 TODO

> **Single-module revision** — daemon docs only. Primary topic: Apply cross-team
> request from IME behavior team (CTR-01) — simplify Phase 1 subgraph in
> `01-internal-architecture.md` to a black-box
> `processKey(KeyEvent) → ImeResult` view and add cross-reference to the
> behavior doc.

## Inputs

| # | Type                        | Source                                                                         |
| - | --------------------------- | ------------------------------------------------------------------------------ |
| 1 | Cross-team request (CTR-01) | `draft/v1.0-r4/cross-team-requests/01-ime-behavior-simplify-phase1-diagram.md` |
| 2 | Handover                    | `draft/v1.0-r4/handover/handover-to-v05.md`                                    |

## Phase 1: Discussion & Consensus

- [x] Assemble full daemon team (all 6 agents)
- [x] Team reviews CTR-01 requirements
- [x] Verify no other daemon docs require changes (CTR-01 scope check)
- [x] Consensus report delivered by principal-architect

## Phase 2: Assignment Negotiation

- [x] Spawn fresh agents
- [x] Agents negotiate assignments (no editing)
- [x] All agents report → team leader confirms or picks mapping
- [x] Shut down unassigned agents

## Phase 3: Document Writing

- [x] Update version header in `01-internal-architecture.md`
- [x] Replace Phase 1 subgraph (lines 94–112) with black-box
      `processKey → ImeResult`
- [x] Add cross-reference to
      `libitshell3-ime/02-design-docs/behavior/draft/v1.0-r1/01-processkey-algorithm.md`

## Phase 4: Verification

- [x] Round 1: spawn Phase 1 verifiers (consistency-verifier, semantic-verifier)
- [x] Round 1: spawn Phase 2 reviewers (issue-reviewer-fast,
      issue-reviewer-deep)
- [x] Round 1: fix SEM-01 (post-debounce idle suppression)
- [x] Round 2: fix CRX-02 (Disconnect notation), SEM-B (last-pane close
      sequence), CRX-A (active_keyboard_layout), CRX-B (stray colon)
- [x] Round 2: owner decisions — SEM-A deferred to v1.0-r6 (review note
      written), SEM-C dismissed
- [x] Round 3: fix CRX-01 (section ref), CRX-03/SEM-01 (state diagram), TERM-01
      (pane_a), SEM-02 (latest_client_id), SEM-03 (notification channels),
      SEM-05 (deactivate scope)
- [x] Round 4: fix CRX-01 (bare §6.2 links), SEM-01 (engine.reset() in SIGCHLD)
      — owner declared clean

## Phase 5: Commit & Report

- [x] Commit daemon v1.0-r5 documents (`e7fb13b`)
- [x] Handover written (`adf6bad`)
- [x] Report to owner

---

**DONE** — Cycle complete. See `handover/handover-to-r6.md` for v1.0-r6 inputs.
