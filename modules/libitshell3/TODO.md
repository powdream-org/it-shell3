# libitshell3 Implementation TODO — Plan 9

## Current State

- **Step**: 8 (Spec Compliance Review — Round 5)
- **Cycle Type**: modification (Plan 9 — Frame Delivery & Runtime Policies)
- **Review Round**: 5
- **Active Team**: plan9-impl
- **Team Directory**: .claude/agents/impl-team/

## Spec

- **Target**: modules/libitshell3
- **Spec version(s)**:
  - daemon-behavior v1.0-r9
  - daemon-architecture v1.0-r9
  - server-client-protocols v1.0-r13
- **Previous spec version(s)**: same (Plan 8 built against these versions)
- **Plan**: docs/superpowers/plans/2026-04-04-libitshell3-frame-delivery.md
- **PoC**: none
- **Coverage exemption**: no

## Spec Gap Log

(empty — gaps discovered during implementation are logged here)

## Fix Cycle State

- **Fix Iteration**: 4
- **Active Issues**:
  - R4-001 [CODE] metadata_serializer.zig:286 — writeTerminalModes hardcoded
    leading comma causing invalid JSON — RESOLVED (comma removed from helper,
    I-frame call site updated to handle comma explicitly)
  - R4-002 [CONV] metadata_serializer.zig + resize_handler.zig — 9 spec section
    number references replaced with topic-name references — RESOLVED
  - R4-003 [TEST] metadata_serializer.zig — P-frame terminal_modes tests added
    (only-field and alongside-cursor cases) — RESOLVED

## Progress — Round 1

- [x] Step 1: Requirements Intake
- [x] Step 2: Plan Writing
- [x] Step 3: Plan Verification
- [x] Step 4: Cycle Setup
- [x] Step 5: Scaffold & Build Verification
- [x] Step 6: Implementation Phase
- [x] Step 7: Code Simplify & Convention Compliance
- [x] Step 8: Spec Compliance Review (Round 3)
- [x] Step 9: Fix Cycle (R3 — 1 CONV issue resolved)
- [x] Step 10: Coverage Audit
- [x] Step 11: Over-Engineering Review (Round 4 regression fixes)
- [x] Step 8: Spec Compliance Review (Round 4 — post-Step 11 re-review)
- [x] Step 9: Fix Cycle (Round 4 — 3 issues resolved)
- [x] Step 8: Spec Compliance Review (Round 5 — CLEAN)
- [ ] Step 10: Coverage Audit
- [ ] Step 12: Commit & Report
- [ ] Step 13: Owner Review
- [ ] Step 14: Retrospective
- [ ] Step 15: Cleanup & ROADMAP Update
