# Daemon Design v0.4 TODO

> **Single-module revision** — daemon docs only.
> Primary topics: (1) SessionDetachRequest→DetachSessionRequest rename (CRITICAL),
> (2) SessionEntry introduction / pane_slots migration (HIGH),
> (3) SplitNodeData typo fixes in v0.1 resolution doc (LOW),
> (4) pty_master_fd→pty_fd rename in pseudocode (LOW).

## Carry-Over from v0.3

| # | Review Note | Severity | Description |
|---|-------------|----------|-------------|
| RN-01 | 01-splitnode-remnants-in-v01-resolution | LOW | SplitNode→SplitNodeData typos in v0.1 resolution doc (R1 line 23, R3 line 80) |
| RN-02 | 02-pty-fd-naming-inconsistency | LOW | `pty_master_fd` vs `pty_fd` in doc 03 §1.1 Step 6 pseudocode |
| RN-03 | 03-pane-slots-placement-and-session-entry | HIGH | Remove `pane_slots` from `Session`; introduce `SessionEntry` in `server/`; owner decision given |
| RN-05 | 05-session-detach-request-naming | CRITICAL | `SessionDetachRequest` → `DetachSessionRequest` rename across all daemon docs |

## Phase 1: Pre-writing Planning (Discussion & Consensus)

- [ ] Assemble full daemon team (all 6 agents)
- [ ] Pre-discussion research:
  - [ ] Grep all daemon v0.4 docs for message type names → cross-check against protocol doc 03 normative table (RN-05 audit)
  - [ ] Research tmux/zellij session-state-tree organization (RN-03 prior art)
- [ ] Team discussion on RN-03 (SessionEntry design) — validate owner decision, resolve any open sub-questions
- [ ] Team discussion on RN-05 (naming audit) — confirm full list of occurrences to rename
- [ ] Consensus report delivered by principal-architect

## Phase 2: Assignment Negotiation

- [ ] Spawn fresh agents
- [ ] Agents negotiate assignments (no editing)
- [ ] All agents report → team leader confirms or picks mapping
- [ ] Shut down unassigned agents

## Phase 3: Document Writing

- [ ] RN-05: Rename SessionDetachRequest → DetachSessionRequest (all affected docs)
- [ ] RN-03: Remove pane_slots from Session; update SessionEntry in doc 01 §3
- [ ] RN-01: Fix SplitNode→SplitNodeData in v0.1 design-resolutions/01-daemon-architecture.md
- [ ] RN-02: Fix pty_master_fd → pty_fd in doc 03 §1.1 pseudocode

## Phase 4: Verification

- [ ] Round 1: spawn verification team (4 agents)
- [ ] Cross-validation
- [ ] Clean or fix → repeat

## Phase 5: Commit & Report

- [ ] Commit daemon v0.4 documents
- [ ] Report to owner
