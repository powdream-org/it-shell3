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

{TODO}

## 3. Design Philosophy

{TODO}

## 4. Owner Priorities

{TODO}

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

**Instruction to v0.8 writers**: These questions are fully closed. Do NOT carry them into v0.8 open questions. Specifically:
- Remove Q5, Q1, Q3, Q6 from Doc 05 Section 15.
- Remove Q1, Q3, Q5 from Doc 03 Section 10.
- Remove Q9 and Q5 from Doc 06 Section 11.
- Remove Q1 and Q5 from Doc 04 Section 11.

### 5.1b Transferred to Review Notes

| Question | Review Note | Note |
|----------|-------------|------|
| Doc 03 Q4 (Zoom + split interaction) | `06-zoom-split-interaction` | Owner requests open discussion with no pre-selected direction. Do NOT bias toward any option. |
| Doc 05 Q4 (Preedit and mouse interaction) | `05-mouse-preedit-interaction` | MouseButton commits preedit; MouseScroll does not. Viewport restoration is libghostty auto-behavior (`scroll-to-bottom` default). |

### 5.2 Resolve in v0.8

{TODO}

### 5.3 Confirm-and-Close (direction already decided, owner approval needed)

{TODO}

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

{TODO}
