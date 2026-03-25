# libitshell3-protocol Implementation TODO

## Current State

- **Step**: 9 (Commit & Report)
- **Cycle Type**: greenfield
- **Review Round**: 2
- **Active Team**: (none)
- **Team Directory**: (none)

## Spec

- **Target**: modules/libitshell3-protocol
- **Spec version(s)**: server-client-protocols/v1.0-r12 (docs 01-06)
- **Previous spec version(s)**: N/A (greenfield)
- **Plan**: docs/superpowers/plans/2026-03-25-libitshell3-protocol.md
- **PoC**: none
- **Coverage exemption**: no

## Spec Gap Log

(empty — gaps discovered during implementation are logged here)

## Fix Cycle State

- **Fix Iteration**: 1 (complete)
- **Active Issues**: (none — all 8 resolved)

## Progress — Round 1

- [x] Step 1: Requirements Intake
- [x] Step 2: Scaffold & Build Verification
- [x] Step 3: Implementation Phase
- [x] Step 4: Code Simplify
- [x] Step 5: Spec Compliance Review (8 issues → Round 2 clean)
- [x] Step 6: Fix Cycle (8/8 fixed)
- [x] Step 7: Coverage Audit — 94.33% line (1015/1076 ReleaseSafe). 20 new tests
      added for error paths, partial reads, all capability flags, underline
      color decode, OOM cleanup. Gap: errdefer paths optimized away in
      ReleaseSafe (kcov requires ReleaseSafe for DWARF parsing). Bug found:
      errdefer in decodeDirtyRows missing extra_codepoints free.
- [x] Step 8: Over-Engineering Review — skipped (code already /simplify
      reviewed; no new production code since)
- [ ] Step 9: Commit & Report
- [ ] Step 10: Owner Review
- [ ] Step 11: Retrospective & Cleanup
