# Daemon Design v0.1 — TODO

## Requirements

### Internal Architecture
1. Module decomposition — libitshell3 internal structure, dependency directions
2. Event loop model — kqueue single-thread vs multi-thread
3. State tree — Session:Tab 1:1 merge vs separation, Pane binary split tree
4. ghostty Terminal instance management — per-pane lifecycle, thread safety

### External Boundaries — Responsibility Separation
5. daemon ↔ libitshell3-protocol responsibility boundary — what the protocol library provides (interfaces) vs what the daemon handles (logic), across all phases: startup, handshake, frame delivery, shutdown. Results feed into cross-team request for protocol team.
6. daemon ↔ libitshell3-ime integration — per-session ImeEngine lifecycle, Phase 0→1→2 key routing, preedit injection, activate/deactivate/flush timing
7. C API surface design (itshell3.h) — public interface for Swift client

### Lifecycle
8. Daemon lifecycle — startup sequence, graceful shutdown, LaunchAgent, SSH fork+exec
9. Client connection lifecycle — accept → handshake → attach → detach → disconnect, multi-client

### Additional Constraints
- Document structure (number of docs, naming) is decided by the team during assignment negotiation
- Protocol interface requirements discovered here will be issued as cross-team requests to protocol v0.10

## Input Materials

### Design Documents
- Protocol spec v0.9: `docs/modules/libitshell3-protocol/02-design-docs/server-client-protocols/draft/v1.0-r9/`
- IME contract v0.7: `docs/modules/libitshell3-ime/02-design-docs/interface-contract/draft/v1.0-r7/`
- Protocol handover to v0.10: `draft/v1.0-r9/handover/handover-to-v0.10.md`

### Overview & Insights
- libghostty API: `docs/modules/libitshell3/01-overview/01-libghostty-api.md`
- Window/pane management: `docs/modules/libitshell3/01-overview/02-window-pane-management.md`
- Design principles: `docs/insights/design-principles.md`
- ghostty API extensions (PoC 06–08): `docs/insights/ghostty-api-extensions.md`
- Reference codebase learnings: `docs/insights/reference-codebase-learnings.md`

### PoC Results
- PoC 06: headless Terminal extraction — `Terminal.init()` works without Surface/App
- PoC 07: bulkExport() — RenderState → FlatCell[] in 22 µs (80×24)
- PoC 08: importFlatCells() — FlatCell[] → RenderState → GPU rendering validated

### Agent Definitions
- Daemon team: `.claude/agents/daemon-team/` (6 members)
- Verification team: `.claude/agents/verification/` (4 members)

## Revision Cycle Phases

- [x] **3.1 Requirements Intake** — create TODO, assemble team
- [x] **3.2 Team Discussion & Consensus** — 6 members debated all 9 requirements + 3 owner questions. R5 re-discussed per owner directive (transport layer in protocol lib).
- [x] **3.3 Resolution Document & Verification** — `design-resolutions/01-daemon-architecture.md` written and verified 6/6 PASS (twice: initial + R5 revision)
- [x] **3.4 Assignment Negotiation** — 6/6 unanimous: daemon-architect → Doc 01, protocol-architect → Doc 02, system-sw-engineer → Doc 03
- [x] **3.5 Document Writing** — 3 assigned members wrote spec docs in parallel: daemon-architect → Doc 01, protocol-architect → Doc 02, system-sw-engineer → Doc 03. Committed `cda655a`.
- [x] **3.6 Cross-Document Verification** — 4 fresh verification agents (cross-reference-verifier, terminology-verifier, semantic-verifier, history-guardian) independently verified all 4 documents.
- [x] **3.7 Issue Cross-Validation** — Verifiers debated 8 raw issues peer-to-peer. Reached 4/4 unanimous consensus: 5 true issues (4 critical, 1 minor), 3 false alarms dismissed.
- [x] **3.8 Issue Recording & Decision** — Recorded in `verification/round-1-issues.md`. Returning to 3.4 for fix cycle.

### Fix Cycle (Round 2)
- [x] **3.4** Assignment Negotiation — daemon-architect: V1-03, system-sw-engineer: V1-01/02/04/05
- [x] **3.5** Document Writing — all 5 fixes applied (dependency list, diagram names, cross-reference qualifier, DISCONNECTING note)
- [x] **3.6** Cross-Document Verification — R1 fixes confirmed by all 4 verifiers. 5 new raw issues found (4 unqualified "protocol spec" refs + 1 SIGHUP header omission).
- [x] **3.7** Issue Cross-Validation — 4/4 unanimous: 3 confirmed (V2-01, V2-02, V2-03), 2 dismissed.
- [x] **3.8** Issue Recording & Decision — Recorded in `verification/round-2-issues.md`. Returning to 3.4 for fix cycle.

### Fix Cycle (Round 3)
- [x] **3.4** Assignment Negotiation — system-sw-engineer: V2-01/V2-02 (Doc 03), daemon-architect: V2-03 (resolution doc)
- [x] **3.5** Document Writing — all 3 fixes applied (protocol doc qualifiers, SIGHUP in header)
- [x] **3.6** Cross-Document Verification — 3/4 CLEAN (cross-ref, terminology, history-guardian). Semantic verifier raised 2 issues, both re-raises of previously handled/dismissed items. Owner declared CLEAN.
- [x] **3.9** Commit & Report — all documents verified clean after 3 rounds (5 + 3 + 0 issues). Committed `53862d0`.

## Revision Cycle Complete

All steps 3.1–3.9 done. Next: **Review Cycle (Section 4)** — owner reviews committed documents.

## Review Cycle

- [ ] **4.1** Owner Review Session — pending
