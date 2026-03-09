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
- Protocol spec v0.9: `docs/modules/libitshell3-protocol/02-design-docs/server-client-protocols/v0.9/`
- IME contract v0.7: `docs/modules/libitshell3-ime/02-design-docs/interface-contract/v0.7/`
- Protocol handover to v0.10: `v0.9/handover/handover-to-v0.10.md`

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
- [ ] **3.5 Document Writing** — IN PROGRESS. 3 assigned members writing spec docs in parallel.
- [ ] **3.6 Cross-Document Verification** — fresh verification team (4 members)
- [ ] **3.7 Issue Cross-Validation** — verifiers debate and filter
- [ ] **3.8 Issue Recording & Decision** — record confirmed issues (if any)
- [ ] **3.9 Commit & Report** — commit docs, report to owner
