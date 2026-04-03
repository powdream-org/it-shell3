# libitshell3 Plan 8 — Input Pipeline & Preedit Wire Messages

## Current State

- **Step**: 15 (Cleanup & ROADMAP Update)
- **Cycle Type**: modification (Plan 8 — Input Pipeline & Preedit Wire Messages)
- **Review Round**: 3
- **Active Team**: (none)
- **Team Directory**: (none)

## Spec

- **Target**: modules/libitshell3
- **Spec version(s)**:
  - daemon-architecture v1.0-r9
  - daemon-behavior v1.0-r9
  - server-client-protocols v1.0-r13
- **Previous spec version(s)**: daemon-architecture v1.0-r8, daemon-behavior
  v1.0-r8, server-client-protocols v1.0-r12
- **Plan**: docs/superpowers/plans/2026-04-02-libitshell3-input-pipeline.md
- **PoC**: none
- **Coverage exemption**: no

## Spec Gap Log

- SC-3, SC-4: Spec path annotations stale (server/state/ subdirectory) —
  dismissed, low impact
- SC-8: SessionEntry zoomed_pane — implementation detail, no spec change
- SC-11: Pane vt_stream — implementation detail, no spec change
- SC-1, SC-2, SC-5, SC-6, SC-7, SC-10: 6 CTRs filed → daemon-architecture inbox
  → Plan 11.5
- SC-9: routeKeyEvent → handleKeyEvent rename added to plan (Task 6)

## Fix Cycle State

- **Fix Iteration**: 1
- **Active Issues**: (none — CODE-1-4, TEST-1-6, CONV-1 all resolved)

## Progress — Round 1

- [x] Step 1: Requirements Intake
- [x] Step 2: Plan Writing
- [x] Step 3: Plan Verification
- [x] Step 4: Cycle Setup
- [x] Step 5: Scaffold & Build Verification
- [x] Step 6: Implementation Phase
- [x] Step 7: Code Simplify & Convention Compliance
- [x] Step 8: Spec Compliance Review
- [x] Step 9: Fix Cycle
- [x] Step 10: Coverage Audit (94.86% — 0.14% below 95% target, handler dispatch
      gap)
- [x] Step 11: Over-Engineering Review (code changed → returning to Step 8)
- [x] Step 12: Commit & Report
- [x] Step 13: Owner Review
- [x] Step 14: Retrospective (SIP-1~4 → redesign spec, no individual patches)
- [ ] Step 15: Cleanup & ROADMAP Update
