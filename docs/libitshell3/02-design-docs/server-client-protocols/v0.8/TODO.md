# Protocol v0.8 TODO

> **Cross-team revision** with IME Contract v0.7. Single topic: preedit protocol overhaul.
> IME Contract TODO: `docs/libitshell3-ime/02-design-docs/interface-contract/v0.7/TODO.md`

## Phase 1: Discussion & Consensus (cross-team, 7 core members)

- [x] Analyze review note `04-preedit-protocol-overhaul` (protocol) and cross-team request `01-protocol-composition-state-removal` (IME)
- [x] Reach unanimous consensus on all changes across both document sets
- [x] Write resolution document (covers both protocol and IME changes)
- [x] All members verify resolution document
- [x] Disband discussion team

## Phase 2: Assignment Negotiation (fresh team)

- [x] Spawn fresh team, present resolution document
- [x] Negotiate document ownership (protocol docs 04, 05, 06 + IME contract files 02, 03, 04, 05)
- [x] Shutdown unassigned agents (principal-architect, ime-architect, ime-swe)

## Phase 3: Document Writing

- [x] Leader gates writing start
- [x] Protocol doc 04 (Input and RenderState): remove ring buffer bypass, frame_type=0
- [x] Protocol doc 05 (CJK Preedit Protocol): remove composition_state, FrameUpdate preedit JSON, dual-channel, cursor/width fields, Section 3, Section 10.1
- [x] Protocol doc 06 (Flow Control and Auxiliary): remove bypass references
- [x] IME 02-types.md: remove ImeResult.composition_state, scenario matrix column
- [x] IME 03-engine-interface.md: remove CompositionStates struct, naming convention, setActiveInputMethod examples
- [x] IME 04-ghostty-integration.md: remove composition_state memory model note
- [x] IME 05-extensibility-and-deployment.md: add itshell3_preedit_cb revision note
- [x] Disband writing team

## Phase 4: Cross-Document Verification — Round 1 (verification team, 4 members)

- [x] Spawn verification team
- [x] Independent verification by all 4 verifiers
- [x] Issue cross-validation (peer debate)
- [x] Record issues: 5 true alarms (V1-01 through V1-05), 3 dismissed. See `v0.8/verification/round-1-issues.md`
- [x] Disband verification team

## Phase 4b: Fix Cycle (Round 1 issues)

- [x] Spawn fix team, present round-1-issues.md + resolution document
- [x] Negotiate fix ownership
- [x] V1-01 (ime-expert): Update 01-overview.md version refs + create Appendix I in 99-appendices.md for IME v0.7
- [x] V1-02 (cjk-specialist): Fix doc 05 Section 14.2 stale ordering statement
- [x] V1-03 (cjk-specialist): Fix doc 05 Section 4.3 line 311 cross-reference label
- [x] V1-04 (protocol-architect): Update doc 02 preedit capability semantics
- [x] V1-05 (protocol-swe): Fix doc 06 overview duplicate "doc 04" reference
- [x] Disband fix team

## Phase 4c: Cross-Document Verification — Round 2

- [x] Spawn verification team
- [x] Independent verification by all 4 verifiers
- [x] Issue cross-validation (peer debate)
- [x] Record result: 3 true alarms (V2-01 through V2-03), 3 dismissed. See `v0.8/verification/round-2-issues.md`

## Phase 4d: Fix Cycle (Round 2 issues)

- [x] Spawn fix team, present round-2-issues.md + resolution document
- [x] Negotiate fix ownership
- [x] V2-01 (protocol-architect): Update doc 01 to v0.8 (14 stale preedit/bypass/dual-channel/frame_type locations)
- [x] V2-02 (protocol-swe): Update doc 03 to v0.8 (lines 947, 1062 stale preedit bypass references)
- [x] V2-03 (ime-expert): Update IME contract 01-overview.md responsibility matrix line 162
- [x] Disband fix team

## Phase 4e: Cross-Document Verification — Round 3

- [x] Spawn verification team
- [x] Independent verification by all 4 verifiers
- [x] Issue cross-validation (peer debate)
- [x] Record result: 2 true alarms (V3-01, V3-02), 5 dismissed. See `v0.8/verification/round-3-issues.md`

## Phase 4f: Fix Cycle (Round 3 issues)

- [x] Spawn fix team, present round-3-issues.md + resolution document
- [x] Negotiate fix ownership
- [x] V3-01 (protocol-architect): Add doc 02 cross-reference to doc 04 Section 7.3 MUST-ignore rule
- [x] V3-02 (cjk-specialist): Remove "preedit state" from doc 04 Section 4.1 unchanged rule
- [x] Disband fix team

## Phase 4g: Cross-Document Verification — Round 4

- [x] Spawn verification team
- [x] Independent verification by all 4 verifiers
- [x] Issue cross-validation (peer debate)
- [x] Record result: 2 minor issues (V4-01, V4-02), 0 dismissed. See `v0.8/verification/round-4-issues.md`

## Phase 4h: Fix Cycle (Round 4 issues)

- [x] Spawn fix team, present round-4-issues.md + resolution document
- [x] Negotiate fix ownership
- [x] V4-01 (protocol-swe): Add doc 03 Section 1.6 cross-reference to doc 04 Section 7.3 MUST-ignore rule
- [x] V4-02 (cjk-specialist): Remove "no preedit changes" from doc 04 Section 7.3
- [x] Disband fix team

## Phase 4i: Cross-Document Verification — Round 5

- [x] Spawn verification team
- [x] Independent verification by all 4 verifiers
- [x] Issue cross-validation (peer debate)
- [x] Record result: 3 minor issues (V5-01, V5-02, V5-03), 1 dismissed. See `v0.8/verification/round-5-issues.md`

## Phase 4j: Fix Cycle (Round 5 issues)

- [x] Spawn fix team, present round-5-issues.md + resolution document
- [x] Negotiate fix ownership
- [x] V5-01 (protocol-swe): Add doc 03 Section 1.14 MUST-ignore cross-reference
- [x] V5-02 (protocol-swe): Qualify doc 06 Section 2.3 "no bypass paths" with scroll-response exception
- [x] V5-03 (protocol-swe): Fix PreeditSync ordering in doc 03 Section 1.6 and doc 06 Section 2.3
- [x] Disband fix team

## Phase 4k: Cross-Document Verification — Round 6

- [x] Spawn verification team
- [x] Independent verification by all 4 verifiers
- [x] Issue cross-validation (peer debate)
- [x] Record result: 2 minor issues (V6-01, V6-02), 2 dismissed. See `v0.8/verification/round-6-issues.md`

## Phase 4l: Fix Cycle (Round 6 issues)

- [x] Spawn fix team, present round-6-issues.md + resolution document
- [x] Negotiate fix ownership
- [x] V6-01 (protocol-architect): Update doc 02 Section 9.2 PreeditSync ordering to match doc 03 Section 1.6
- [x] V6-02 (protocol-swe): Remove "PreeditSync-triggered frames" from doc 06 Section 2.3
- [x] Disband fix team

## Phase 4m: Cross-Document Verification — Round 7

- [x] Spawn verification team
- [x] Independent verification by all 4 verifiers
- [x] Issue cross-validation (peer debate)
- [x] Record result: 1 true alarm (V7-01), 1 dismissed. See `v0.8/verification/round-7-issues.md`

## Phase 4n: Fix Cycle (Round 7 issues)

- [x] Spawn fix team, present round-7-issues.md + resolution document
- [x] Negotiate fix ownership (pre-assigned: protocol-architect owns doc 01)
- [x] V7-01 (protocol-architect): Update doc 01 Section 9.1 binary frame header size and component descriptions
- [x] Disband fix team

## Phase 4o: Cross-Document Verification — Round 8

- [x] Spawn verification team
- [x] Independent verification by all 4 verifiers
- [x] Issue cross-validation (peer debate)
- [x] Record result: 1 true alarm (V8-01), 2 dismissed. See `v0.8/verification/round-8-issues.md`

## Phase 4p: Fix Cycle (Round 8 issues)

- [x] Spawn fix team, present round-8-issues.md
- [x] Negotiate fix ownership (pre-assigned: protocol-architect owns doc 02)
- [x] V8-01 (protocol-architect): Replace "preedit overlays" with "preedit cell data" in doc 02 Section 10.1
- [x] Disband fix team

## Phase 4q: Cross-Document Verification — Round 9

- [x] Spawn verification team
- [x] Independent verification by all 4 verifiers
- [x] Issue cross-validation (peer debate)
- [x] Record result: 1 true alarm (V9-01), 0 dismissed. See `v0.8/verification/round-9-issues.md`

## Phase 4r: Fix Cycle (Round 9 issues)

- [x] Spawn fix team, present round-9-issues.md
- [x] Negotiate fix ownership (pre-assigned: protocol-architect owns doc 02)
- [x] V9-01 (protocol-architect): Fix doc 02 Section 10.1 preedit_sync fallback table row 2
- [x] Disband fix team

## Phase 4s: Cross-Document Verification — Round 10

- [x] Spawn verification team
- [x] Independent verification by all 4 verifiers
- [x] Issue cross-validation (peer debate)
- [x] Record result: 1 true alarm (V10-01), 0 dismissed. See `v0.8/verification/round-10-issues.md`

## Phase 4t: Fix Cycle (Round 10 issues)

- [x] Spawn fix team, present round-10-issues.md
- [x] Negotiate fix ownership (pre-assigned: protocol-architect owns doc 02)
- [x] V10-01 (protocol-architect): Fix doc 02 Section 10.1 preedit_sync fallback table row 3
- [x] Disband fix team

## Phase 4u: Cross-Document Verification — Round 11

- [x] Spawn verification team
- [x] Independent verification by all 4 verifiers
- [ ] Issue cross-validation (peer debate) — STOPPED by owner
- [ ] Record result
- **Note**: 3 of 4 verifiers reported CLEAN (cross-reference, history-guardian, semantic). terminology-verifier raised 1 marginal issue (R11-T01: "per pane" qualifier on preedit_session_id in doc 05 §2.1) unrelated to preedit overhaul scope. Owner stopped verification loop here.

## Phase 5: Commit & Report

- [x] Clean verification pass achieved (3/4 CLEAN in round 11; owner stopped loop)
- [x] Commit protocol v0.8 + IME contract v0.7 (`670e105`)
- [x] Carry forward 15 unclosed review notes to v0.9 (renumbered by severity)
- [ ] Report to owner
