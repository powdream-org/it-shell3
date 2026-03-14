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
- [x] 01-processkey-algorithm.md — system-sw-engineer
- [x] 02-scenario-matrix.md — sw-architect
- [x] 03-modifier-flush-policy.md — system-sw-engineer
- [x] 10-hangul-engine-internals.md — ime-expert
- [x] 11-hangul-ic-process-handling.md — ime-expert

**Cross-team requests:**
- [x] CTR-01 → daemon: `daemon/draft/v1.0-r4/cross-team-requests/01-ime-behavior-simplify-phase1-diagram.md`
- [x] CTR-02 → ime-contract: `interface-contract/inbox/cross-team-requests/01-behavior-team-extract-impl-content-from-v1.0.md`
- [x] CTR-03 → ime-contract: `interface-contract/inbox/cross-team-requests/02-behavior-team-editorial-policy-from-v1.0.md`
- [x] CTR-04 → ime-contract: `interface-contract/inbox/cross-team-requests/03-behavior-team-renumber-sections-from-v1.0.md`

## Phase 4: Verification (3.6–3.8) — 4 rounds

### Round 1
- [x] Phase 1 (consistency + semantic verifiers) — 5 confirmed, 3 dismissed
- [x] Phase 2 (history-guardian + issue-reviewer) — contested issues escalated to owner
- [x] Owner resolved contested items (ISSUE-4, 6, 7)
- [x] round-1-issues.md written

### Round 2
- [x] Phase 1 — 4 confirmed (A, F, R2-2, R2-6), 8 dismissed
- [x] Phase 2 — all confirmed
- [x] round-2-issues.md written
- [x] Fixes applied (A, F, R2-2, R2-6 + interface-contract 02-types.md isPrintablePosition fix)

### Round 3
- [x] Phase 1 — 2 confirmed critical (R3-sem-1, R3-sem-2), 2 dismissed
- [x] Phase 2 — both confirmed
- [x] round-3-issues.md written
- [x] Fixes applied: isPrintablePosition() range corrected; prev_preedit_buf content tracking

### Round 4
- [x] Phase 1 — R4-cons-1 (minor), R4-sem-1 (critical)
- [x] Phase 2 — R4-cons-1 contested, R4-sem-1 confirmed
- [x] Owner triage: R4-cons-1 dismissed, R4-sem-1 deferred to v1.0-r2
- [x] round-4-issues.md written

## Phase 5: Commit (3.9)

- [x] Commit all spec docs, verification records, CTRs (commit 6a68975)

## Phase 6: Review Cycle (4.x)

- [x] review-notes/01-backspace-flush-path-grouping.md — R4-sem-1 deferred to v1.0-r2 (commit after 6a68975)
