# Plan 16: Post-Design Code Alignment — Implementation TODO

## Current State

- **Step**: 14 (Retrospective)
- **Cycle Type**: modification (Plan 16 — align code with Plan 15 spec updates)
- **Review Round**: 2
- **Active Team**: impl-team
- **Team Directory**: `.claude/agents/impl-team/`

## Spec

- **Target**: modules/libitshell3 (primary), modules/libitshell3-protocol,
  modules/libitshell3-ime
- **Spec version(s)**:
  - daemon-architecture v1.0-r9
  - daemon-behavior v1.0-r9
  - server-client-protocols v1.0-r13
  - interface-contract (IME) v1.0-r11
- **Previous spec version(s)**:
  - daemon-architecture v1.0-r8
  - daemon-behavior v1.0-r8
  - server-client-protocols v1.0-r12
  - interface-contract (IME) v1.0-r10
- **Plan**:
  `docs/superpowers/plans/2026-04-02-libitshell3-post-design-code-alignment.md`
- **PoC**: N/A (modification cycle, no new architecture)
- **Coverage exemption**: no (standard kcov)

## Work Items (from research)

### WI-1: ADR 00015 — u64 Sequence / 20-byte Header

- header.zig: HEADER_SIZE 16→20, VERSION 1→2, sequence u32→u64
- connection_state.zig: send_sequence/recv_sequence_last u32→u64
- protocol_envelope.zig: sequence u32→u64
- All handlers (session, pane, lifecycle, input, render, flow_control, ime
  dispatchers): sequence u32→u64
- notification_builder.zig: sequence u32→u64
- frame_serializer.zig: remove u32 narrowing cast
- message_reader.zig: sequence u32→u64
- error.zig: ref_sequence u32→u64
- All spec/integration tests: update assertions, byte offsets, type annotations

### WI-2: ADR 00062 — Fixed-Point Resize Ratio

- split_tree.zig: SplitNodeData.ratio f32→u32, equalizeRatios 0.5→5000
- pane_handler.zig: direction→orientation, delta→delta_ratio, integer arithmetic
- session_pane_dispatcher.zig: wire parsing field names
- notification_builder.zig: JSON ratio format float→integer
- types.zig: add MIN_RATIO=500, RATIO_SCALE=10000 constants

### WI-3: RN-01/ADR 00003 — AttachOrCreate Merge

- message_type.zig: delete 0x010C/0x010D
- session.zig (protocol): delete AttachOrCreateRequest/Response, add fields to
  AttachSessionRequest/Response
- session_handler.zig: merge handleAttachOrCreate into handleAttachSession,
  delete old handler
- session_pane_dispatcher.zig: remove attach_or_create_request case
- Tests: rewrite AttachOrCreate tests for merged behavior

### WI-4: ADR 00059 — CapsLock/NumLock in KeyEvent

- ime_engine.zig: Modifiers add caps_lock, num_lock, padding u5→u3
- wire_decompose.zig: extract bits 4-5 into modifiers.caps_lock/num_lock
- wire_decompose tests + spec tests: fix assertions to verify preservation

## Spec Gap Log

- **SG-1** (pre-existing): `ime_engine.zig` `hid_keycode: u16` — spec says `u8`.
  Wire carries `u16` but daemon should truncate. Needs Plan 8 (input pipeline)
  to add validation at wire boundary.
- **SG-2** (pre-existing): Duplicate `KeyEvent`/`ImeResult` in `ime_engine.zig`
  vs `libitshell3-ime/types.zig`. Known architectural seam from vtable design.
  Consider shared types package in future.

## Fix Cycle State

- **Fix Iteration**: 0
- **Active Issues**: (none)

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
- [x] Step 10: Coverage Audit
- [x] Step 11: Over-Engineering Review (Round 2 regression clean)
- [x] Step 12: Commit & Report
- [x] Step 13: Owner Review
- [ ] Step 14: Retrospective
- [ ] Step 15: Cleanup & ROADMAP Update
