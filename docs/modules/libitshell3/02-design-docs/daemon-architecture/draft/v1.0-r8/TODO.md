# Daemon Architecture v1.0-r8 TODO

> **Restructuring cycle**: Split from `daemon/` topic (v1.0-r7). This topic
> covers structural design: module decomposition, state tree, type definitions,
> integration boundaries, transport design. Shares a revision cycle with
> `daemon-behavior/`.

## Inputs

| # | Type     | Source                                                 |
| - | -------- | ------------------------------------------------------ |
| 1 | Handover | `daemon/draft/v1.0-r7/handover/handover-to-r8.md`      |
| 2 | Spec     | `daemon/draft/v1.0-r7/01-internal-architecture.md`     |
| 3 | Spec     | `daemon/draft/v1.0-r7/02-integration-boundaries.md`    |
| 4 | Spec     | `daemon/draft/v1.0-r7/03-lifecycle-and-connections.md` |
| 5 | Spec     | `daemon/draft/v1.0-r7/04-runtime-policies.md`          |
| 6 | Insight  | `docs/insights/ghostty-api-extensions.md`              |

## Current State

- **Step**: 5 (Verification)
- **Verification Round**: 1
- **Active Team**: (none)
- **Team Directory**: (none)

## Progress

- [x] Step 1: Requirements Intake — done
- [x] Step 2: Team Discussion & Consensus — 6/6 unanimous, 12 resolutions
      (unified round: classification + QA behavior philosophy + code structure)
- [x] Step 3: Resolution & Verification — 12 resolutions + normative authority,
      6/6 confirmed after fix cycle, all agents shut down
- [x] Step 4: Assignment & Writing — 6 writers, 3 arch + 3 behavior + 5
      impl-constraints, all complete, old baselines removed
- [x] Step 4b: Owner Review — ADRs 00048-00051, doc cleanups (removed duplicated
      rationale, impl-level detail to impl-constraints, ADR refs)
- [ ] Step 5: Verification (Round 1)
- [ ] Step 6: Fix Round Decision
- [ ] Step 7: Commit & Report
- [ ] Step 8: Owner Review
- [ ] Step 9: Retrospective
