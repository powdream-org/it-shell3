# Daemon Design v0.3 TODO

> **Cross-team revision** with Protocol v0.11 and IME Contract v0.8.
> Primary topic: absorb daemon behavioral content from protocol docs (P1-P20)
> and IME contract docs (I1-I9, A1-A2) into daemon design docs.
> Protocol TODO: `docs/modules/libitshell3-protocol/02-design-docs/server-client-protocols/v0.11/TODO.md`
> IME TODO: `docs/modules/libitshell3-ime/02-design-docs/interface-contract/v0.8/TODO.md`
>
> **Model policy**:
> - Phase 1-3 (planning, negotiation, writing): **sonnet** for all agents
> - Phase 4 (verification): **opus** for history-guardian only; **sonnet** for other verifiers

## Carry-Over Notes (NOT addressed in v0.3 — deferred to v0.4)

- review note 01: SplitNode remnants in v0.1 resolution doc (LOW)
- review note 02: pty_master_fd vs pty_fd naming (LOW)
- review note 03: pane_slots placement / SessionEntry introduction (HIGH)

## Phase 1: Pre-writing Planning

- [ ] Decide doc structure for 31 absorbed topics: extend doc 03 or create new doc 04?
- [ ] Produce deduplication map for 8 overlapping topics (single authoritative version per topic)
- [ ] Draft AGENTS.md replacement paragraph (bundled binary + LaunchAgent + fork+exec only)

## Phase 2: Assignment Negotiation (sonnet — no editing)

- [ ] Spawn 6-member team (daemon-architect, ime-expert, protocol-architect,
      principal-architect, ghostty-integration-engineer, system-sw-engineer) — **sonnet**
- [ ] Provide: review note 04, protocol cross-team request, IME cross-team request, v0.3 spec files
- [ ] Negotiate assignments across all three modules (daemon v0.3 + protocol v0.11 + IME v0.8)
- [ ] Shut down unassigned agents

## Phase 3: Document Writing (sonnet)

### Daemon v0.3 — absorb from protocol (P-series)

- [ ] P1-P2: Daemon auto-start (launchd/fork-exec), crash recovery (FD passing via SCM_RIGHTS)
- [ ] P3, P5: Connection limits, Unix socket auth
- [ ] P4: Multi-client resize policy (latest/smallest, latest_client_id, fallback, hysteresis)
- [ ] P6, P19: Reconnection procedure, heartbeat initiation policy
- [ ] P7: Health escalation timeline (T=0→300s), stale trigger conditions
- [ ] P8-P9: Flow control (PausePane/ContinuePane semantics, FlowControlConfig policy),
      ring buffer architecture (2MB per-pane, per-client cursors, I/P-frame storage)
- [ ] P10, P15: Event-driven coalescing tiers/timing, preedit immediate flush, frame suppression
- [ ] P11: Preedit ownership model (single-owner, concurrent attempt, 30s timeout, disconnect)
- [ ] P12: Preedit lifecycle on state changes (focus, alt-screen, pane close, owner disconnect)
- [ ] P13: Preedit cleanup on client eviction
- [ ] P14: PTY lifecycle (SIGHUP, TIOCSWINSZ, debounce, parent split reflow)
- [ ] P16, P20: Layout enforcement (tree depth limit), pane metadata tracking
- [ ] P17: Session persistence (IME engine restore, composition state not restored)
- [ ] P18: Notification defaults after AttachSession

### Daemon v0.3 — absorb from IME contract (I-series) and AGENTS.md (A-series)

- [ ] I1-I3: 3-phase key routing pipeline (Phase 0/1/2), IME-before-keybindings rationale,
      daemon responsibility matrix
- [ ] I4, I4a, I4b: ImeResult→ghostty API mapping (handleKeyEvent pseudocode,
      preedit clearing rule, ghostty_surface_text prohibition)
- [ ] I5-I6: Per-session engine lifecycle (create/destroy, activate/deactivate, flush on focus),
      focus change handling (flush, preserve language, same engine)
- [ ] I7-I8: Session persistence (IME: save/restore input_method + keyboard_layout),
      C API boundary (libitshell3-ime has no public C header)
- [ ] I9: Wire-to-KeyEvent decomposition (modifier bitmask → KeyEvent fields, CapsLock omitted)
- [ ] A1-A2: Version conflict handling (local: kill+restart; remote: negotiation failure → exit)
- [ ] Deduplicate 8 overlapping topics (preedit flush on focus, engine lifecycle,
      session persistence IME, pane close, version conflict, multi-client preedit,
      stale eviction + preedit, coalescing + preedit immediate)

### Protocol v0.11 — slim down (tracked in protocol TODO)

- [ ] Apply 23 extraction changes across docs 01-06 (see protocol v0.11 TODO)

### IME Contract v0.8 — slim down (tracked in IME TODO)

- [ ] Apply 9 extraction changes across docs 01-05 + design-resolutions (see IME v0.8 TODO)

### AGENTS.md

- [ ] Update daemon lifecycle paragraph (keep high-level summary only, reference daemon docs)

## Phase 4: Verification — Round 1

- [ ] Spawn verification team: history-guardian (**opus**), cross-reference-verifier (sonnet),
      semantic-verifier (sonnet), terminology-verifier (sonnet)
- [ ] Each verifier independently reads ALL docs (daemon v0.3, protocol v0.11, IME v0.8)
      — intra-module, cross-module, and consistency with prior versions
- [ ] Issue cross-validation among verifiers — dismiss false alarms, confirm true alarms
- [ ] If issues confirmed: record → `verification/round-1-issues.md`, loop to Phase 2b (fix)
- [ ] If clean: proceed to Phase 5

## Phase 5: Commit & Report

- [ ] Commit daemon v0.3 documents
- [ ] Commit protocol v0.11 documents
- [ ] Commit IME contract v0.8 documents
- [ ] Commit AGENTS.md update
- [ ] Report to owner
