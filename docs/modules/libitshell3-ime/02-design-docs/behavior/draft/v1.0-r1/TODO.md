# IME Behavior v1.0-r1 TODO

## ~~Phase 1: Discussion & Resolution~~ — Skipped

PLAN.md serves as the resolution document. Owner approved skip to 3.4.

## Phase 2: Assignment Negotiation (3.4)

- [x] Spawn fresh ime-team (all 4 agents)
- [x] Provide PLAN.md as resolution document
- [x] All agents report assignments
- [x] Shutdown unassigned agents

## Phase 3: Document Writing (3.5)

**New behavior docs:**
- [x] 01-processkey-algorithm.md — system-sw-engineer (merged daemon Phase 1 subgraph + interface-contract lines 57–67)
- [x] 02-scenario-matrix.md — sw-architect (from interface-contract `02-types.md` lines 125–158)
- [x] 03-modifier-flush-policy.md — system-sw-engineer (from interface-contract `02-types.md` lines 160–186)
- [x] 10-hangul-engine-internals.md — ime-expert (from interface-contract `03-engine-interface.md` lines 128–248 + `04-ghostty-integration.md` lines 17–31)
- [x] 11-hangul-ic-process-handling.md — ime-expert (from interface-contract `01-overview.md` lines 71–92)

**Cross-team requests:**
- [x] CTR-01 → daemon: system-sw-engineer — `daemon/draft/v1.0-r4/cross-team-requests/01-ime-behavior-simplify-phase1-diagram.md`
- [x] CTR-02 → ime-contract: ime-expert — `interface-contract/inbox/cross-team-requests/01-behavior-team-extract-impl-content-from-v1.0.md`
- [x] CTR-03 → ime-contract: principal-architect — `interface-contract/inbox/cross-team-requests/02-behavior-team-editorial-policy-from-v1.0.md`
- [x] CTR-04 → ime-contract: sw-architect — `interface-contract/inbox/cross-team-requests/03-behavior-team-renumber-sections-from-v1.0.md`

## Phase 4: Verification (3.6 + 3.7)

- [x] Spawn consistency-verifier + semantic-verifier (Phase 1)
- [x] Collect issue lists
- [x] Spawn history-guardian + issue-reviewer (Phase 2)
- [x] Determine confirmed / dismissed / contested

## Phase 5: Issue Fix (3.8) — if needed

- [x] Record issues to verification/round-1-issues.md
- [ ] Owner resolves 3 contested issues (ISSUE-4, 6, 7)
- [ ] Spawn fresh team for fix round (confirmed issues: 1, 2, 3, 5 + any contested accepted)

## Phase 6: Commit (3.9)

- [ ] Remove PLAN.md (planning artifact, not a spec document)
- [ ] Commit all new documents
- [ ] Report to owner
