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

## Phase 4b: Fix Cycle (Round 1 issues — 6 after owner dismissed V1-02)

- [x] Spawn fresh fix team (6 agents, Owner Rule pick: ISE/DA mapping)
- [x] V1-01: Version headers v0.1→v0.2 in docs 02/03 (ghostty-integration-engineer)
- [x] V1-03: Apply R1/R3/R9 to v0.1 resolution doc (daemon-architect)
- [x] V1-04: Fix broken link in doc 02 header (ghostty-integration-engineer)
- [x] V1-05: Update doc 03 Section 1.6 v0.2 terms (daemon-architect)
- [x] V1-06: dirty_mask "server/"→"core/" in resolution doc (protocol-architect)
- [x] V1-07: SplitNode→tree_nodes array in doc 03 Section 3.2 (ime-system-sw-engineer)
- [x] Disband fix team

## Phase 4c: Verification (Round 2)

- [x] Spawn fresh verification team (4 agents: cross-ref, semantic, terminology, history-guardian)
- [x] Independent cross-document verification (Phase 1)
- [x] Issue cross-validation (Phase 2) — 3 confirmed, 1 dismissed
- [x] Record issues → `verification/round-2-issues.md`
- [x] Disband verification team

## Owner Review (Round 2 issues)

- [x] V2-01 (LOW): SplitNode remnants in v0.1 resolution doc → deferred as review note 01
- [x] V2-02 (LOW): pty_master_fd vs pty_fd → deferred as review note 02
- [x] V2-03 (HIGH): pane_slots placement contradiction → deferred as review note 03 (requires design discussion: SessionEntry introduction)
- [x] All 3 issues recorded as `draft/v1.0-r2/review-notes/01–03` for v0.3 resolution

## Owner Review (Cross-Document Analysis)

- [x] Review note 04: daemon behavior migration from protocol (20 topics) and IME (9 topics)
- [x] Cross-team request → protocol v0.10: `01-daemon-behavior-extraction.md` (23 changes)
- [x] Cross-team request → IME v0.7: `01-daemon-behavior-extraction.md` (9 changes)
- [x] Convention update: `07-cross-team-requests.md` — placement clarification + handover mention rule
- [x] Handover: `draft/v1.0-r2/handover/handover-to-v0.3.md` created
- [x] Handover: protocol `draft/v1.0-r10/handover/handover-to-v0.11.md` updated (cross-team request mention)
- [x] Handover: IME `draft/v1.0-r7/handover/handover-to-v0.8.md` created

## Phase 5: Commit & Report

- [ ] Commit v0.2 documents
- [ ] Report to owner
