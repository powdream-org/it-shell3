# Daemon Architecture v1.0-r9 TODO

> **Unified cycle (Plan 15)**: This revision runs simultaneously with
> daemon-behavior v1.0-r9, server-client-protocols v1.0-r13, and IME
> interface-contract v1.0-r11. Shared team, shared discussion, shared
> verification.

## Inputs

| # | Type     | Source                                                                   |
| - | -------- | ------------------------------------------------------------------------ |
| 1 | Handover | `daemon-architecture/draft/v1.0-r8/handover/handover-to-r9.md`           |
| 2 | CTR      | `daemon-architecture/draft/v1.0-r8/cross-team-requests/01-*.md` (6)      |
| 3 | CTR      | `daemon-behavior/draft/v1.0-r8/cross-team-requests/01-*.md` (3)          |
| 4 | CTR      | `server-client-protocols/draft/v1.0-r12/cross-team-requests/01-*.md` (6) |
| 5 | CTR      | `interface-contract/draft/v1.0-r10/cross-team-requests/01-*.md` (1)      |
| 6 | Handover | `server-client-protocols/draft/v1.0-r12/handover/handover-to-r13.md`     |
| 7 | Handover | `interface-contract/draft/v1.0-r10/handover/handover-to-r11.md`          |
| 8 | Review   | `server-client-protocols/draft/v1.0-r12/review-notes/01,02,03,05-*.md`   |
| 9 | Review   | `daemon-architecture/draft/v1.0-r8/review-notes/mouse-encode-api-gap.md` |

## Current State

- **Step**: Complete
- **Verification Round**: 4 (CLEAN)
- **Active Team**: (none)
- **Team Directory**: (none)

## Progress

- [x] Step 1: Requirements Intake — done (unified 4-topic cycle, 9 agents, 16
      CTRs + 4 deferred review notes)
- [x] Step 2: Team Discussion & Consensus — 9/9 unanimous, 20 resolutions + 6
      corrections + 2 owner decisions. Addenda: mouse encoder in ghostty/, JSON
      ratio as integer, impl-constraints folded, ADR 00060 separate pass.
- [x] Step 3: Resolution & Verification — 8/8 confirmed, 2 corrections during
      verification (Doc 06 filename, Resolution 8 Mermaid). All agents shut
      down.
- [x] Step 4: Assignment & Writing — 5 writers (daemon-arch, daemon-behavior,
      protocol, cjk, ime). 13 docs updated, 3 stale cross-refs fixed. All
      writers shut down.
- [x] Step 5: Verification (Round 1) — 6 confirmed (3 critical, 3 minor), 2
      dismissed. No contested issues.
- [x] Step 4 (Fix Round 1): 2 writers, 6 fixes across 5 docs
- [x] Step 5: Verification (Round 2) — 2 confirmed (R2-1 critical, R2-2 minor),
      1 dismissed
- [x] Step 6: Fix Round Decision — Round 2, automatic fix round
- [x] Step 4 (Fix Round 2): team lead direct fix, 1 file (Doc 04 offset table +
      performance analysis)
- [x] Step 5: Verification (Round 3) — 1 confirmed (R3-1 hex dump), 1 dismissed,
      1 pre-existing fix. Owner triage: fix both.
- [x] Step 6: Fix Round Decision — Round 3, owner triage (fix)
- [x] Step 4 (Fix Round 3): team lead direct fix, 1 file (Doc 04 hex dump +
      cross-ref)
- [x] Step 5: Verification (Round 4) — CLEAN (both verifiers)
- [x] Step 6: Fix Round Decision — declared clean
- [x] Step 7: Commit & Report — committed 09c2ade
- [x] Step 8: Owner Review — done (no review notes, no additional fixes)
- [x] Step 9: Retrospective — 3 SIPs applied (step 6 threshold, triage quality
      gate with sub-agent, CLEAN auto-declare). Skill files committed.
- [x] Step 10: Handover — `handover/handover-to-r10.md` written
