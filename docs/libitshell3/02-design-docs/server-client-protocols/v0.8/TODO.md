# Protocol v0.8 TODO

> **Cross-team revision** with IME Contract v0.7. Single topic: preedit protocol overhaul.
> IME Contract TODO: `docs/libitshell3-ime/02-design-docs/interface-contract/v0.7/TODO.md`

## Phase 1: Discussion & Consensus (cross-team, 7 core members)

- [ ] Analyze review note `04-preedit-protocol-overhaul` (protocol) and cross-team request `01-protocol-composition-state-removal` (IME)
- [ ] Reach unanimous consensus on all changes across both document sets
- [ ] Write resolution document (covers both protocol and IME changes)
- [ ] All members verify resolution document
- [ ] Disband discussion team

## Phase 2: Assignment Negotiation (fresh team)

- [ ] Spawn fresh team, present resolution document
- [ ] Negotiate document ownership (protocol docs 04, 05, 06 + IME contract sections)
- [ ] Shutdown unassigned agents

## Phase 3: Document Writing

- [ ] Leader gates writing start
- [ ] Protocol doc 04 (Input and RenderState): remove ring buffer bypass, frame_type=0
- [ ] Protocol doc 05 (CJK Preedit Protocol): remove composition_state, FrameUpdate preedit JSON, dual-channel, cursor/width fields, Section 3, Section 10.1
- [ ] Protocol doc 06 (Flow Control and Auxiliary): remove bypass references
- [ ] IME contract: remove ImeResult.composition_state, CompositionStates struct, scenario matrix column, memory model note, naming convention, setActiveInputMethod examples
- [ ] Disband writing team

## Phase 4: Cross-Document Verification (verification team, 4 members)

- [ ] Spawn verification team
- [ ] Independent verification by all 4 verifiers
- [ ] Issue cross-validation (peer debate)
- [ ] Record issues if any, loop back to Phase 2

## Phase 5: Commit & Report

- [ ] Clean verification pass achieved
- [ ] Commit protocol v0.8 + IME contract v0.7
- [ ] Report to owner
