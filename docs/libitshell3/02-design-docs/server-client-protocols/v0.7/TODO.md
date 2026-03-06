# Protocol v0.7 TODO

## Phase 1: Research (Issues 22-24 prior art)

- [x] tmux multi-client frame delivery research
- [x] zellij multi-client frame delivery research
- [x] ghostty dirty tracking & frame generation research

## Phase 2: Design Discussion & Resolution (Issues 22-24)

- [x] Core team discussion (Issue 24 → 23 → 22 order)
- [x] Resolution document written & verified by same team (5/5 APPROVED)
- [x] Disband discussion team

## Phase 3: Unified Writing (all changes in one pass)

- [x] Fresh team spawned, assignment negotiation
- [x] Doc 01: 0x0185 registry + resize/health overview + I/P-frame overview
- [x] Doc 02: `"stale_client"` disconnect reason
- [x] Doc 03: ClientHealthChanged, resize rewrite, AttachSessionResponse + IME per-session changes
- [x] Doc 04: I/P-frame model, frame_type field, per-pane dirty bitmap
- [x] Doc 05: per-session rewrite, preedit exclusivity, `"client_evicted"`, cosmetic fixes
- [x] Doc 06: Ring buffer, health escalation, FlowControlConfig, recovery unification, preedit bypass

## Phase 4: Cross-Document Verification

- [x] Round 1: 2 critical fixes (frame_sequence scope, ~110B), 3 dismissed
- [x] Round 2: 9 minor fixes (terminology, wire traces, naming), 2 dismissed
- [x] Round 3: 4 minor issues confirmed — design-level, deferred to review notes
- [x] Verification terminated at Round 3 (owner decision)

## Phase 5: Commit & Review

- [x] v0.7 commit (verification results + R1/R2 fixes)
- [x] Review notes created (3 files: scroll delivery, PreeditEnd reason, resolution doc text)

## Phase 6a: Open Questions Batch 1 (docs 03-04, ~12 questions)

- [ ] Core team triage doc 03 open questions (6 questions)
- [ ] Core team triage doc 04 open questions (6 questions)
- [ ] Resolution document
- [ ] Writing
- [ ] Verification
- [ ] Commit

## Phase 6b: Open Questions Batch 2 (docs 05-06, ~15 questions)

- [ ] Core team triage doc 05 open questions (6 questions)
- [ ] Core team triage doc 06 open questions (9 questions)
- [ ] Resolution document
- [ ] Writing
- [ ] Verification
- [ ] Commit

## Phase 6c: Per-Client Focus Indicators

- [ ] Core team discussion
- [ ] Resolution document
- [ ] Writing
- [ ] Verification
- [ ] Commit
