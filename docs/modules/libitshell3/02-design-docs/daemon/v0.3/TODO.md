# Daemon Design v0.3 TODO

> **Cross-team revision** with Protocol v0.11 and IME Contract v0.8.
> Primary topic: absorb daemon behavioral content from protocol docs (P1-P20)
> and IME contract docs (I1-I9, A1-A2) into daemon design docs.
> Protocol TODO: `docs/modules/libitshell3-protocol/02-design-docs/server-client-protocols/v0.11/TODO.md`
> IME TODO: `docs/modules/libitshell3-ime/02-design-docs/interface-contract/v0.8/TODO.md`
>
> **Model policy**:
> - Phase 1 (planning): **opus** for all agents
> - ~~Phase 2 (negotiation): skipped — team leader assigns writers directly~~
> - Phase 3 (writing): **opus** for all agents
> - Phase 4 (verification): **opus** for history-guardian only; **sonnet** for other verifiers

## Carry-Over Notes (NOT addressed in v0.3 — deferred to v0.4)

- review note 01: SplitNode remnants in v0.1 resolution doc (LOW)
- review note 02: pty_master_fd vs pty_fd naming (LOW)
- review note 03: pane_slots placement / SessionEntry introduction (HIGH)
- ~~review note 04: AGENTS.md line 18 "session/tab/pane state" → resolved in v0.3~~
- review note 05: SessionDetachRequest vs DetachSessionRequest naming inconsistency (CRITICAL)

## Phase 1: Pre-writing Planning

- [x] Decide doc structure for 31 absorbed topics: extend docs 01-03 + create new doc 04
- [x] Produce deduplication map for 8 overlapping topics (single authoritative version per topic)
- [x] Draft AGENTS.md replacement paragraph (bundled binary + LaunchAgent + fork+exec only)
- [x] Consensus report delivered by principal-architect (unanimous, 6/6)

### Phase 1 Consensus: Topic-to-Document Mapping

- Doc 01 (extend — 8 items): I1, I4/I4a/I4b, P14, P15, P16, P20
- Doc 02 (extend — 7 items): I2, I3, I5, I6, I8, I9, P5
- Doc 03 (extend — 6 items): P1, P2, P6, P9, A1, A2
- Doc 04 (NEW `04-runtime-policies.md` — 12 items): P3, P4, P7, P8, P10, P11, P12, P13, P17+I7, P18, P19

### Phase 1 Consensus: Deduplication Map

1. Preedit flush on focus → I6 base
2. Per-session engine lifecycle → I5 base
3. Session persistence IME → P17 base (merged with I7)
4. Preedit on pane close → P12 base (CANCEL, not commit)
5. Version conflict → A1/A2 base
6. Multi-client preedit ownership → doc 05 §6.1-6.4 base
7. Stale eviction + preedit → P7 base
8. Coalescing + preedit immediate → full 4-tier model (protocol doc 06 §1)

## ~~Phase 2: Assignment Negotiation~~ — Skipped

> Team leader assigns writers directly (same opus team from Phase 1 continues to Phase 3).

## Phase 3: Document Writing (opus)

### Writer Assignments

| Writer | Assignment |
|--------|-----------|
| daemon-architect | Daemon doc 01 (I1, I4/I4a/I4b, P14, P15, P16, P20) |
| ime-expert | Daemon doc 02 (I2, I3, I5, I6, I8, I9, P5) + IME v0.8 (8 extractions) |
| system-sw-engineer | Daemon doc 03 (P1, P2, P6, P9, A1, A2) + AGENTS.md |
| protocol-architect | Protocol v0.11 (23 extraction changes) |
| ghostty-integration-engineer | Daemon doc 04 NEW (P3, P4, P7, P8, P10, P11, P12, P13, P17+I7, P18, P19) |
| principal-architect | Dedup consistency review + quality coordination |

### Daemon v0.3 — doc 01 (daemon-architect)

- [x] I1: 3-phase key pipeline (Phase 0+2 daemon-side) → §1.2 + §4.3
- [x] I4: ImeResult→ghostty API mapping, handleKeyEvent pseudocode → §4.3
- [x] I4a: MUST call ghostty_surface_preedit(null, 0) on preedit end → §4.4
- [x] I4b: NEVER use ghostty_surface_text() (bracketed paste bug) → §4.3
- [x] P14: PTY lifecycle (SIGHUP, TIOCSWINSZ, debounce) → §3 Pane struct
- [x] P15: Frame suppression (cols<2 or rows<1) → §4.5 Frame Export Pipeline
- [x] P16: Layout enforcement (tree depth limit 16) → §3 State Tree
- [x] P20: Pane metadata (OSC title, CWD, foreground process) → §3.3 Pane struct

### Daemon v0.3 — doc 02 (ime-expert)

- [x] I2: IME-before-keybindings rationale → §4.2
- [x] I3: Responsibility matrix (daemon side) → §4
- [x] I5: Per-session engine lifecycle (activate/deactivate/flush) → §4.1
- [x] I6: Focus change handling (intra-session flush) → §4.3/§4.4
- [x] I8: C API boundary (no public C header for libitshell3-ime) → §5
- [x] I9: Wire-to-KeyEvent decomposition → §4.2
- [x] P5: Unix socket auth (verify existing §1.5.4) → §1.5.4

### Daemon v0.3 — doc 03 (system-sw-engineer)

- [x] P1: Daemon auto-start (launchd, fork/exec, stale cleanup) → §1 + §6
- [x] P2: Crash recovery (SCM_RIGHTS FD passing) → §2.2
- [x] P6: Reconnection procedure (full I-frame resync) → §4
- [x] P9: Ring buffer details (2MB, keyframe 1s) → §5
- [x] A1: Local version conflict (kill+restart) → §6.3
- [x] A2: Remote version conflict (negotiation failure) → §7

### Daemon v0.3 — doc 04 NEW (ghostty-integration-engineer)

- [x] P3: Connection limits (≥256, ERR_RESOURCE_EXHAUSTED) → §1
- [x] P4: Resize policy (latest/smallest, hysteresis) → §2
- [x] P7: Health escalation (T=0→300s timeline) → §3
- [x] P8: Flow control (PausePane/ContinuePane) → §4
- [x] P10: Coalescing (4-tier model + WAN adaptation) → §5
- [x] P11: Preedit ownership (single-owner, 30s timeout) → §6
- [x] P12: Preedit lifecycle (focus, alt-screen, pane close, disconnect) → §7
- [x] P13: Preedit on eviction → §3 or §6
- [x] P17+I7: Session persistence (consolidated) → §8
- [x] P18: Notification defaults → §9
- [x] P19: Heartbeat policy → §3

### AGENTS.md (system-sw-engineer)

- [x] Update daemon lifecycle paragraph (keep high-level summary only, reference daemon docs)

### Protocol v0.11 — slim down (protocol-architect)

- [x] Apply 23 extraction changes across docs 01-06 (see protocol v0.11 TODO)

### IME Contract v0.8 — slim down (ime-expert)

- [x] Apply 8 extraction changes across docs 01-05 (see IME v0.8 TODO)
- [x] Note: design-resolutions-per-tab-engine.md is historical — MUST NOT be modified

### Dedup consistency (principal-architect)

- [x] Review all 8 dedup items for consistency across daemon, protocol, and IME docs

## Phase 4: Verification

### Round 1

- [x] Spawn verification team: history-guardian (**opus**), cross-reference-verifier (sonnet),
      semantic-verifier (sonnet), terminology-verifier (sonnet)
- [x] Each verifier independently reads ALL docs (daemon v0.3, protocol v0.11, IME v0.8)
      — intra-module, cross-module, and consistency with prior versions
- [x] Issue cross-validation among verifiers — dismiss false alarms, confirm true alarms
- [x] 9 issues confirmed, 2 dismissed → `verification/round-1-issues.md`
- [x] Fix all 9 issues (3 parallel sonnet agents)

### Round 2

- [x] Spawn verification team (same composition)
- [x] All 9 Round 1 fixes confirmed
- [x] 3 new issues confirmed (R2-03, R2-06, R2-07), 3 pre-existing deferred, 1 dismissed
      → `verification/round-2-issues.md`
- [x] Fix all 3 issues (trivial one-line fixes, applied directly)

### Pre-existing issues recorded as review notes

- review note 04: R2-01 — AGENTS.md line 18 "tab" reference (LOW)
- review note 05: R2-02 — SessionDetachRequest vs DetachSessionRequest (CRITICAL)
- IME v0.9 review note 01: R2-05 — Surface API references in comments (LOW)

## Phase 5: Commit & Report

- [ ] Commit daemon v0.3 documents
- [ ] Commit protocol v0.11 documents
- [ ] Commit IME contract v0.8 documents
- [ ] Commit AGENTS.md update
- [ ] Report to owner
