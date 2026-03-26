# libitshell3 Implementation TODO

## Current State

- **Step**: 3 (Implementation Phase)
- **Cycle Type**: modification
- **Review Round**: 0
- **Active Team**: (none)
- **Team Directory**: (none)

## Spec

- **Target**: modules/libitshell3
- **Spec version(s)**:
  - daemon-architecture v1.0-r8
  - daemon-behavior v1.0-r8
  - libitshell3-ime interface-contract v1.0-r10
  - libitshell3-ime behavior v1.0-r2
- **Previous spec version(s)**: same (modification cycle — adding IME
  integration to existing Plan 1-4 code)
- **Plan**: docs/superpowers/plans/2026-03-26-libitshell3-ime-integration.md
- **PoC**: none
- **Coverage exemption**: no

## Spec Gap Log

- PaneSlot u4 vs spec u8 — code is wrong, spec wins (no ADR for u4)
- keyboard_layout vs active_keyboard_layout — code is wrong, spec wins
- Default "us" vs "qwerty" — code is wrong, spec wins (protocol identifier)
- SessionEntry.latest_client_id missing — code is wrong, spec wins
- Session.creation_timestamp missing — code is wrong, spec wins
- focused_pane PaneSlot vs ?PaneSlot — code is wrong, spec wins
- Length field abbreviations (aim_len, kl_len) — code is wrong, naming
  convention says no abbreviations
- Slice vs inline buffer representation — ADR 00058 accepts inline buffers, CTR
  filed to update spec

## Fix Cycle State

- **Fix Iteration**: 0
- **Active Issues**: (none)

## Progress — Round 1

- [x] Step 1: Requirements Intake
- [x] Step 2: Scaffold & Build Verification
- [ ] Step 3: Implementation Phase
- [ ] Step 4: Code Simplify
- [ ] Step 5: Spec Compliance Review
- [ ] Step 6: Fix Cycle
- [ ] Step 7: Coverage Audit
- [ ] Step 8: Over-Engineering Review
- [ ] Step 9: Commit & Report
- [ ] Step 10: Owner Review
- [ ] Step 11: Retrospective & Cleanup
