# libitshell3 Implementation TODO

## Current State

- **Step**: 10 (Owner Review)
- **Cycle Type**: modification
- **Review Round**: 1
- **Active Team**: (none — disbanded)
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
- Pane fields foreground_process, foreground_pid, silence_subscriptions,
  silence_deadline — spec defines them but not IME-related; likely Plan 6/7
- Phase 0 daemon shortcut handling — spec §5.2 step 2 defines it but shortcut
  keybinding system not yet designed; cannot implement without keybinding spec
- Pane vt_stream field — ghostty implementation detail (opaque pointer like
  terminal/render_state), not a spec-level concern; QA #15 was false positive

## Fix Cycle State

- **Fix Iteration**: 1
- **Active Issues**: #1, #2, #8, #9, #10, #12, #13 (7 issues from Step 5 R1)

## Progress — Round 1

- [x] Step 1: Requirements Intake
- [x] Step 2: Scaffold & Build Verification
- [x] Step 3: Implementation Phase
- [x] Step 4: Code Simplify
- [x] Step 5: Spec Compliance Review (R1: 9 issues, 3 spec gaps logged, 1
      skipped)
- [x] Step 6: Fix Cycle (R1: 7 fixed, 3 spec gaps, R2 clean)
- [x] Step 7: Coverage Audit (95.25% line, 100% function Plan 5)
- [x] Step 8: Over-Engineering Review (code changed → regression to Step 5)
- [ ] Step 9: Commit & Report
- [ ] Step 10: Owner Review
- [ ] Step 11: Retrospective & Cleanup

## Owner Review Notes

- Cyclic references found (Plan 1 legacy): event_loop.zig ↔
  handlers/pty_read.zig, event_loop.zig ↔ handlers/client_accept.zig. Root
  cause: ClientEntry defined in event_loop.zig. Fix: extract ClientEntry to
  server/client_entry.zig.
- handlers/signal.zig is thin re-export wrapper around signal_handler.zig —
  consider removing.
- Test directory restructuring: finalize testing/ layout (helpers.zig at root,
  mocks/ subdirectory, spec/ subdirectory). Apply consistently to all modules.
  Convention draft in docs/conventions/zig-testing.md — owner to review and
  confirm.
- PtyWriter interface misplaced in server/ime_consumer.zig — is an OS I/O
  abstraction (same level as PtyOps in os/interfaces.zig). Move to
  os/interfaces.zig to fix testing→server dependency cycle and enable clean mock
  placement. Plan 5 implementer dependency error.

## Progress — Round 2

- [ ] Step 5: Spec Compliance Review (regression + QA spec tests recovery)
- [ ] Step 6: Fix Cycle
- [ ] Step 7: Coverage Audit
- [ ] Step 8: Over-Engineering Review
- [ ] Step 9: Commit & Report
- [ ] Step 10: Owner Review
- [ ] Step 11: Retrospective & Cleanup
