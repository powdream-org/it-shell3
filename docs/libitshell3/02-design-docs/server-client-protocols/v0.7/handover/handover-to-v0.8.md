# Handover: Protocol v0.7 to v0.8 Revision

> **Date**: 2026-03-07
> **Author**: team-lead (with owner review)
> **Scope**: Review notes, open questions triage, and design insights from the v0.7 revision and verification cycle
> **Prerequisite reading**: All files in `v0.7/review-notes/`, `v0.7/verification/round-3-issues.md`

---

## 1. What v0.7 Accomplished

### 1.1 I/P-Frame Ring Buffer Model

Major architectural change: replaced per-client output buffers with a shared per-pane ring buffer. Produced `design-resolutions/01-i-p-frame-ring-buffer.md` (21 resolutions, 5/5 consensus). All 6 spec docs updated.

### 1.2 Per-Session IME Architecture

Applied cross-team request from IME contract v0.6: one `ImeEngine` per session (not per-pane). Updated session management, attach responses, layout tree, persistence, and preedit ownership model.

### 1.3 Verification (3 rounds)

- **Round 1**: 2 critical fixes applied (frame_sequence scope, preedit frame size)
- **Round 2**: 9 minor fixes applied (terminology, wire traces, naming conventions)
- **Round 3**: 4 issues confirmed but **not fixed** — design-level feedback requiring architectural decisions. Verification terminated by owner. Issues transferred to review notes.

### 1.4 Owner Design Review

Owner review session produced review notes beyond the 3 verification-derived notes:
- `04-preedit-protocol-overhaul` (CRITICAL): Preedit is cell data, not metadata. Removes `composition_state`, FrameUpdate preedit JSON, dual-channel design, ring buffer bypass, cursor/width fields, Section 3, Section 10.1. Consolidated from earlier separate notes after visual PoC confirmed ghostty's preedit rendering model.
- `06-zoom-split-interaction` (MEDIUM): Open discussion, no pre-selected direction.
- `07-pane-auto-close-on-exit` (MEDIUM): Auto-close on process exit, cascade to session destroy.
See `v0.7/review-notes/` for the full list.

---

## 2. Insights and New Perspectives

### 2.1 Preedit is cell data, not metadata

The most significant insight from v0.7: the visual PoC (`poc/preedit-visual/`) proved that ghostty renders preedit as cell data (2-cell block cursor overlay), not as a separate metadata layer. In the daemon-client architecture, the server calls `ghostty_surface_preedit()` and injects preedit cells into FrameUpdate. The client never calls preedit APIs — it just renders cells. This eliminates the dual-channel design (ring buffer + preedit bypass), `composition_state`, and the FrameUpdate preedit JSON section.

### 2.2 Globally singleton session model

v0.7 verification exposed confusion about per-client vs shared state. The scroll delivery issue (review note `01`) crystallized the principle: all clients share the same viewport, the same selection, the same scroll position. Per-client independent state (viewports, scroll positions) is a post-v1 concern. When in doubt, ask: "does tmux do this per-client?" If no, neither do we.

### 2.3 Ring buffer simplifies everything

The I/P-frame ring buffer model (v0.7's major contribution) turned out to resolve multiple open questions beyond its original scope: flow control (cursor stagnation replaces explicit ack), notification coalescing (per-pane ring makes batching unnecessary), recovery unification (skip to latest I-frame), and selection sync (shared state in RowData). Future design decisions should consider the ring buffer as the default delivery path before inventing alternatives.

## 3. Design Philosophy

- **Shared state by default.** All clients see the same thing. Per-client divergence (viewports, focus, scroll) is complexity that must be explicitly justified.
- **One delivery path.** The ring buffer is the canonical data path. Bypass paths (direct queue, priority buffer) are exceptions that require strong justification. The preedit bypass removal validates this — Coalescing Tier 0 already ensures immediate delivery without a separate path.
- **Close early, design later.** Open questions that have no concrete use case should be closed, not carried forward indefinitely. They can be reopened when a real scenario demands it.
- **Implementation details are not protocol concerns.** Clipboard policy, cursor blink timing, focus indicator rendering — these belong to the client app, not the wire protocol.

## 4. Owner Priorities

v0.8 review notes should be processed in the following order:

### Priority 1: CRITICAL
1. **`04-preedit-protocol-overhaul`** — Largest structural change. Removes composition_state, FrameUpdate preedit JSON, ring buffer bypass, Section 3, Section 10.1. Affects docs 04, 05, 06. Must be done first as it changes the foundation other notes build on.
2. **`01-scroll-delivery-design`** — Revert incorrect V2-04 text. Scroll I-frames go through ring buffer. Affects doc 04.

### Priority 2: HIGH
3. **`02-preeditend-reason-cleanup`** — PreeditEnd reason values cleanup. Depends on `04` being resolved first.

### Priority 3: MEDIUM
4. **`05-mouse-preedit-interaction`** — Direction already decided, needs spec text.
5. **`07-pane-auto-close-on-exit`** — Direction already decided, needs spec text.
6. **`06-zoom-split-interaction`** — Open discussion, no pre-selected direction.
7. **`17-hyperlink-celldata-encoding`** — Open discussion, no pre-selected direction.

### Priority 4: LOW (confirm-and-close, apply mechanically)
8. **`03-resolution-doc-text-fixes`** — Text corrections in resolution doc.
9. **`09`–`16`** — 8 confirm-and-close items. Direction decided, just apply to spec docs.

## 5. Open Questions Triage

### 5.1 Closed in v0.7

| Question | Status | Rationale |
|----------|--------|-----------|
| Doc 05 Q5 (Multiple simultaneous compositions) | **Resolved** | Per-session engine makes simultaneous compositions within a session physically impossible. Preedit exclusivity invariant is the normative statement. |
| Doc 05 Q1 (Japanese/Chinese composition states) | **Moot** | Review note `04-preedit-protocol-overhaul` removes the `composition_state` field entirely. Q1 was predicated on this field existing. CJK language extension will be addressed as a v0.8 design decision without the `composition_state` mechanism. |
| Doc 03 Q1 (Last-pane-close behavior) | **Closed** | Already reflected in the design (`ClosePaneResponse` `side_effect = 1`). Owner confirmed: yes, auto-destroy. |
| Doc 03 Q3 (Session auto-destroy) | **Closed** | Core design principle: daemon keeps sessions alive indefinitely with no attached clients. This is fundamental to the daemon's purpose (reconnect later). Owner confirmed: never. |
| Doc 06 Q9 (Tier transition telemetry) | **Closed** | RendererHealth's `coalescing_tier` field is sufficient. No dedicated notification needed. Owner confirmed. |
| Doc 05 Q6 (Undo during composition) | **Closed** | Not a protocol concern. IME contract governs modifier key handling — Cmd+key flushes preedit and forwards. See IME Interface Contract v0.6 Section 3.3. Owner decision. |
| Doc 05 Q3 (Client-side prediction) | **Closed — will not discuss** | Preedit rendering requires server-side libghostty-vt for width/wrapping. Client-side IME does not eliminate server roundtrip. Owner decision. |
| Doc 06 Q5 (Clipboard sync mode) | **Closed — not a protocol concern** | Clipboard access policy is implementation-defined by the client app. Normative note added to Doc 06 §3.1. Owner decision. |
| Doc 03 Q5 (Layout tree compression) | **Closed** | Unnecessary. ~50 panes = few KB JSON. Owner decision. |
| Doc 04 Q1 (Cell deduplication) | **Closed** | Unnecessary. I/P-frame model already reduces bandwidth. 20B/cell acceptable. Owner decision. |
| Doc 04 Q5 (FrameUpdate acknowledgment) | **Closed** | Unnecessary. Ring cursor stagnation + PausePane escalation + SSH TCP flow control covers all scenarios. Owner decision. |
| Doc 04 Q3 (Selection protocol) | **Closed** | Unnecessary. Per-pane shared selection delivered via RowData in FrameUpdate. No dedicated messages needed. Owner decision. |
| Doc 04 Q6 (Notification coalescing) | **Closed** | Unnecessary. Per-pane individual FrameUpdate aligns with per-pane ring buffer model. Owner decision. |

**Instruction to v0.8 writers**: These questions are fully closed. Do NOT carry them into v0.8 open questions. Specifically:
- Remove Q5, Q1, Q3, Q6 from Doc 05 Section 15.
- Remove Q1, Q3, Q5 from Doc 03 Section 10.
- Remove Q9 and Q5 from Doc 06 Section 11.
- Remove Q1, Q3, Q5, and Q6 from Doc 04 Section 11.

### 5.1b Transferred to Review Notes

| Question | Review Note | Note |
|----------|-------------|------|
| Doc 03 Q4 (Zoom + split interaction) | `06-zoom-split-interaction` | Owner requests open discussion with no pre-selected direction. Do NOT bias toward any option. |
| Doc 05 Q4 (Preedit and mouse interaction) | `05-mouse-preedit-interaction` | MouseButton commits preedit; MouseScroll does not. Viewport restoration is libghostty auto-behavior (`scroll-to-bottom` default). |
| Doc 04 Q4 (Hyperlink data) | `17-hyperlink-celldata-encoding` | OSC 8 hyperlink encoding in CellData. Open discussion, no pre-selected direction. |

### 5.2 Resolve in v0.8

These require design discussion or open exploration before spec changes can be written.

| Review Note | Severity | Type |
|-------------|----------|------|
| `04-preedit-protocol-overhaul` | CRITICAL | Architectural overhaul — removes composition_state, preedit JSON, ring buffer bypass |
| `01-scroll-delivery-design` | CRITICAL | Revert V2-04 text, route scroll I-frames through ring |
| `02-preeditend-reason-cleanup` | HIGH | Cleanup after `04` is applied |
| `06-zoom-split-interaction` | MEDIUM | Open discussion |
| `17-hyperlink-celldata-encoding` | MEDIUM | Open discussion |

### 5.3 Confirm-and-Close (direction decided, apply to spec)

These have owner-approved direction. v0.8 writers apply mechanically — no discussion needed.

| Review Note | Change |
|-------------|--------|
| `05-mouse-preedit-interaction` | MouseButton commits preedit; MouseScroll does not. Add normative text. |
| `07-pane-auto-close-on-exit` | Auto-close on process exit, cascade to session destroy. Add normative text. |
| `03-resolution-doc-text-fixes` | Text corrections in resolution doc. |
| `09-pane-minimum-size` | 2col x 1row minimum. Add normative statement to Doc 03. |
| `10-extension-message-ordering` | Strict ordering. Add normative statement to Doc 06. |
| `11-silence-detection-scope` | Activity-then-silence. Add normative statement to Doc 06. |
| `12-renderer-health-interval` | 1000ms minimum. Add normative minimum to Doc 06. |
| `13-snapshot-format-versioning` | Format version in JSON snapshot. Add to Doc 06. |
| `14-clipboard-size-limit` | 10MB + chunked. Add normative limit to Doc 06. |
| `15-multi-session-snapshots` | Per-session files + manifest. Define in Doc 06. |
| `16-extension-negotiation-timing` | Unix socket: handshake, SSH: after auth. Add to Doc 06. |

### 5.4 Defer Beyond v1

All items below are moved to `99-post-v1-features.md`. Do NOT discuss or design these during v0.x through v1.

| Question | Post-v1 Section | Rationale |
|----------|-----------------|-----------|
| Doc 04 Q2 (Image protocol) | Section 1 | Sixel/Kitty requires dedicated message type and out-of-band transfer. Entirely different problem domain. Owner decision. |
| Doc 03 Q6 (Pane reuse after exit) | Section 2 | v1 uses auto-close. Remain-on-exit requires ghostty `wait-after-command` integration. Owner decision. |
| Doc 05 Q2 (Candidate window protocol) | Section 3 | Japanese/Chinese candidate list. v2 schema sketch in review note `04-preedit-protocol-overhaul` Section 8. Owner decision. |
| Application-level heartbeat (echo_nonce) | Section 4 | v1 covers practical scenarios via ring cursor stagnation + PausePane escalation + `latest` policy. Idle-PTY blind spot under `smallest` policy is the only gap — mitigated by `echo_nonce` (`HEARTBEAT_NONCE` capability, 0x0900 range) in v2. Origin: v0.5 Issue 3 gap 1.5, v0.6 Resolution 11. Owner decision. |
| Per-client focus indicators | Section 5 | v1 scope에서 우선순위 밀림. v0.5부터 carry forward된 enhancement. Zellij independent focus mode 참조. Owner decision. |

**Instruction to v0.8 writers**: Do NOT carry these into v0.8 open questions. Remove from their respective sections:
- Remove Q2 from Doc 04 Section 11.
- Remove Q6 from Doc 03 Section 10.
- Remove Q2 from Doc 05 Section 15.

## 6. Pre-Discussion Research Tasks

### 6.1 For `04-preedit-protocol-overhaul`

Research `07-ghostty-preedit-cell-serialization.md` is already complete. No additional research needed — the visual PoC and ghostty source analysis provide sufficient basis.

### 6.2 For `17-hyperlink-celldata-encoding`

Research needed: how does ghostty internally represent OSC 8 hyperlinks in its cell/page structure? Specifically:
- What is the hyperlink ID type and lifecycle?
- How are URIs stored and deduplicated?
- What data is available through the public API for serialization?

Source: `~/dev/git/references/ghostty/`, look for `hyperlink` in the terminal page/cell structures.
