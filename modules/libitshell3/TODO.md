# libitshell3 Implementation TODO

## Current State

- **Step**: 8 (Over-Engineering Review)
- **Cycle Type**: modification (Plan 2: ghostty integration on Plan 1
  foundation)
- **Review Round**: 1
- **Active Team**: (none)
- **Team Directory**: (none)

## Spec

- **Target**: modules/libitshell3
- **Spec version(s)**:
  - daemon-architecture v1.0-r8
  - daemon-behavior v1.0-r8
- **Previous spec version(s)**: Same (Plan 1 implemented foundation from same
  specs)
- **Plan**: docs/superpowers/plans/2026-03-25-libitshell3-ghostty-integration.md
- **PoC**: none (render_export.zig PoC patches not in repo — must be authored)
- **Coverage exemption**: yes — Zig Mach-O DWARF bug (ziglang/zig#31428),
  scenario-matrix approach

## Spec Gap Log

1. **Pane struct location**: Spec §1.5 says Pane belongs in `server/` (owns
   ghostty + OS resources), but Plan 1 placed it in `core/`. Currently using
   `?*anyopaque` with `@ptrCast` in server/ handlers. Deferred refactoring.
2. **mouse_encoder.zig test gap**: Only type-check tests, no actual SGR sequence
   verification. Minor — mouse encoding is a thin ghostty wrapper.

## Fix Cycle State

- **Fix Iteration**: 0
- **Active Issues**: (none)

## Progress — Round 1

- [x] Step 1: Requirements Intake — modification cycle, Plan 2 (ghostty
      integration), specs verified CLEAN
- [x] Step 2: Scaffold & Build Verification — existing build passes (152/152
      Debug + ReleaseSafe)
- [x] Step 3: Implementation Phase — 8 tasks, 7 new ghostty/ files, 189/189
      tests pass, 2 spec gaps logged
- [x] Step 4: Code Simplify — 3 fixes applied (hasStyling cache, Unicode width
      table, PTY drain loop) + 1 correctness bug found (vtStream split-sequence
      state loss → persistent stream)
- [x] Step 5: Spec Compliance Review — 3 dead-code issues found, fixed, re-check
      clean
- [x] Step 6: Fix Cycle — 3 fixes applied (trivial dead-code removal)
- [x] Step 7: Coverage Audit — exempted (Zig Mach-O DWARF bug, scenario-matrix)
- [ ] Step 8: Over-Engineering Review
- [ ] Step 9: Commit & Report
- [ ] Step 10: Owner Review
- [ ] Step 11: Retrospective & Cleanup
