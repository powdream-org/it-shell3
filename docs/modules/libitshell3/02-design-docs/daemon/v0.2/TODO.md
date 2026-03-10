# Daemon Design v0.2 TODO

## Phase 1: Discussion & Resolution (3 review notes)

- [x] Spawn all 6 daemon-team members
- [x] Discuss review note 01: pane limit & fixed-size optimization (HIGH)
- [x] Discuss review note 02: IME module naming confusion (MEDIUM)
- [x] Discuss review note 03: protocol library scope misstatement (MEDIUM)
- [x] Resolution document written & verified by same team (6/6 APPROVED)
- [x] Disband discussion team

## Phase 2: Assignment Negotiation

- [x] Spawn fresh team with resolution doc
- [x] Negotiate doc assignments (Owner Rule: DA:1,2,5 / ISE:3,4 / PA:6)
- [x] Shut down unassigned agents (GIE, principal, system-sw)

## Phase 3: Document Writing

- [x] Apply R1 (pane limit, fixed-size structures, PaneId) to doc 01 Sections 1.5, 1.6, 3.2, 3.3 (daemon-architect)
- [x] Apply R1 to doc 03 Section 4.3 — ClientState ring_cursors (daemon-architect)
- [x] Apply R2 (input/ rename, libitshell3-ime diagram) to doc 01 Sections 1.1, 1.2, 1.3, 1.6 (ime-system-sw-engineer)
- [x] Apply R2 to doc 02 Sections 4.2, 4.7 (ime-system-sw-engineer)
- [x] Apply R2 to v0.1 design-resolutions/01 — R1, R6 references (ime-system-sw-engineer)
- [x] Apply R3 (protocol scope fix) to doc 01 Section 1.4 (protocol-architect)
- [x] Disband writing team

## Phase 4: Verification (Round 1)

- [x] Spawn verification team (4 agents: cross-ref, semantic, terminology, history-guardian)
- [x] Independent cross-document verification (Phase 1)
- [x] Issue cross-validation (Phase 2) — 7 confirmed, 2 dismissed
- [x] Record issues → `verification/round-1-issues.md`
- [x] Disband verification team

## Phase 4b: Fix Cycle (Round 1 issues)

- [ ] Spawn fresh fix team (Step 3.4 — assignment negotiation)
- [ ] Apply 7 fixes (3 critical, 4 minor)
- [ ] Disband fix team

## Phase 4c: Verification (Round 2)

- [ ] Spawn fresh verification team
- [ ] Verify fixes are clean

## Phase 5: Commit & Report

- [ ] Commit v0.2 documents
- [ ] Report to owner
