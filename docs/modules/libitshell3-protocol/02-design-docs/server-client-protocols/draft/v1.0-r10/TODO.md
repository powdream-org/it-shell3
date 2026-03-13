# Protocol v0.10 TODO

## Scope

Top-severity review notes only + cross-team request + mechanical fix.

### Inputs

- RN-01 (CRITICAL): Scroll I-frame delivery — revert per-client text, route through ring buffer
- RN-02 (HIGH): PreeditEnd reason cleanup — remove `input_method_changed`
- Cross-team (daemon v0.1): `PANE_LIMIT_EXCEEDED` error in SplitPaneResponse (Doc 03)
- R3-T01 (handover): Doc 03 §1.6/§1.14 `frame_type=2` → `frame_type=1 or frame_type=2`

## Phase 1: Discussion & Resolution

- [x] Spawn protocol team (all 5 members)
- [x] Team confirms understanding of 4 scoped changes
- [x] Team checks for interactions between changes — discovered Doc 02 frame_type ripple (4 locations) and Doc 06 scroll exception ripple
- [x] Consensus reporter delivers resolution (5/5 unanimous)
- [x] Resolution document written & verified (5/5 APPROVED)
- [x] Disband discussion team

## Phase 2: Assignment Negotiation & Writing

- [x] Spawn fresh team, negotiate assignments (5/5 identical mapping)
- [x] Shutdown unassigned agents (ime-expert, principal-architect)
- [x] Writing gate — 3 agents edit v0.10 spec docs
  - [x] protocol-architect: Doc 02 R4 (4 locations)
  - [x] system-sw-engineer: Doc 03 R3+R4 (4 edits) + Doc 06 R1 ripple (1 edit)
  - [x] cjk-specialist: Doc 04 R1 (1 edit) + Doc 05 R2 (4 edits)
- [x] Disband writing team

## Phase 3: Verification

- [x] Round 1: 3 minor issues found (S-1, S-2, CR-01) — all fixed
- [x] Round 2: Clean pass (4/4 verifiers confirm all fixes correct, no new issues)

## Phase 4: Commit & Report

- [x] Commit v0.10
- [x] Report to owner
