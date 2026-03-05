# Handover: Protocol v0.6 to v0.7 Revision

> **Date**: 2026-03-05
> **Author**: team-lead (with owner review)
> **Scope**: All items requiring resolution in the v0.7 protocol revision
> **Prerequisite reading**: `review-notes-consistency.md`, `design-resolutions-resize-health.md`

---

## 1. What v0.6 Accomplished

v0.6 had two parallel workstreams that produced significant design artifacts but were
**not fully integrated** into the spec documents.

### 1.1 Cross-Document Consistency Fixes (from v0.5 review)

Applied 21 mechanical consistency fixes from `review-notes-01.md` (the v0.5 consistency
review). These are the only changes reflected in the v0.6 spec documents. Specific fixes
include missing registry entries, terminology standardization, direction value fixes,
`display_width` addition to FrameUpdate preedit, etc. All 6 spec docs have v0.6 changelog
entries referencing these fixes.

### 1.2 Multi-Client Resize Policy and Client Health Model Design

A major 4-round design discussion produced `design-resolutions-resize-health.md` containing
16 resolutions and 3 addenda, backed by two prior-art research reports:

- `research-tmux-resize-health.md` -- tmux multi-client resize and client health analysis
- `research-zellij-resize-health.md` -- zellij multi-client resize and health detection analysis

**Key decisions reached:**

| Resolution | Decision |
|-----------|----------|
| Resize policy | `latest` as default (tmux 3.1+ precedent). `smallest` available as opt-in. |
| `latest_client_id` tracking | Per session, updated on KeyEvent/WindowResize (not HeartbeatAck) |
| Stale client exclusion | Only `stale` health state clients excluded from resize. Transient backpressure does NOT exclude. |
| Resize policy scope | Server configuration, reported in AttachSessionResponse (not capability-negotiated) |
| Resize debounce | 250ms per pane (tmux precedent). First resize after attach fires immediately. |
| Re-inclusion hysteresis | 5 seconds of sustained healthy before re-included in resize |
| Health states | Two protocol-visible: `healthy` and `stale`. `paused` is orthogonal flow-control. Smooth degradation is server-internal. |
| PausePane escalation | T=0s pause → T=5s resize exclusion → T=60s/120s stale → T=300s eviction |
| Stale timeout reset | Application-level messages only. HeartbeatAck does NOT reset (iOS TCP keepalive concern). |
| Output queue stagnation | >90% for stale_timeout with no app-level messages → stale trigger |
| Heartbeat orthogonality | Heartbeat = connection liveness (90s). Health states = application responsiveness. Independent systems. |
| ClientHealthChanged | New notification at 0x0185 (always-sent, no subscription) |
| Buffer limit | 512KB per (client, pane), down from 1MB |
| Discard-and-resync | On buffer overflow or stale recovery: discard all buffered frames, send dirty=full snapshot |
| Stale recovery resync | LayoutChanged (if changed) → dirty=full FrameUpdate per pane → PreeditSync per pane |
| Preedit bypass | Absolute across all health states including `stale`. Only connection death stops preedit. |
| Transport-aware timeouts | Local: 60s stale. SSH: 120s stale. Configurable via FlowControlConfig. |
| Preedit commit on eviction | Active preedit committed before Disconnect at T=300s. PreeditEnd reason `"client_evicted"`. |
| Idle suppression during resize | 500ms grace after TIOCSWINSZ before allowing Idle tier transition |

### 1.3 What Was NOT Applied

**Finding 0 from `review-notes-consistency.md`**: None of the 16 resolutions + 3 addenda
were applied to the spec documents. The v0.6 docs labeled as such contain only v0.5 content
+ consistency fixes, not the v0.6 features. The design resolutions document's own "Doc changes
needed" table (lines 421-434) was never executed.

### 1.4 IME Contract Coordination (from v0.5)

Protocol doc 05 changes deferred from IME contract v0.5 were applied to v0.6:
- `"non_korean"` row removed from Section 3.1
- `"empty"` → `null` in state tables and prose
- Prefix convention cross-reference added
- `ko_vowel_only` reachability note added

**Residual**: Two prose notes at lines 349 and 381 of doc 05 still say `empty + vowel`
instead of `null + vowel` (see `review-notes-01.md`, Issue 01). Cosmetic.

---

## 2. Open Items for v0.7

### Priority 1: Apply Design Resolutions to Spec Docs (17 issues, Issues 1-20)

The design resolutions exist in `design-resolutions-resize-health.md` but are not in
the normative spec documents. The consistency review (`review-notes-consistency.md`)
catalogued exactly what's missing per document. These are pre-agreed changes that can
be applied without further debate.

**Per-document breakdown:**

#### Doc 01 -- Protocol Overview (2 issues)

| Issue | Severity | Change |
|-------|----------|--------|
| 1 | CRITICAL | Add `ClientHealthChanged` (0x0185, S→C) to message type registry. Currently jumps from 0x0184 to 0x0190. |
| 2 | HIGH | Add resize policy overview (`latest`/`smallest`) and health state model overview (`healthy`/`stale`). New section or additions to existing architecture sections. |

#### Doc 02 -- Handshake & Capability Negotiation (1 issue)

| Issue | Severity | Change |
|-------|----------|--------|
| 3 | MEDIUM | Add `"stale_client"` to Disconnect reason enum (Section 11.1). Required for T=300s eviction per Resolution 8. |

#### Doc 03 -- Session & Pane Management (6 issues)

| Issue | Severity | Change |
|-------|----------|--------|
| 4 | CRITICAL | Add `ClientHealthChanged` (0x0185) notification to Section 4 with full JSON schema, reason values, always-sent behavior. |
| 5 | CRITICAL | **Rewrite Section 5.1 resize algorithm.** Currently describes smallest-only (`min(cols) × min(rows)`). Must implement latest/smallest dual-policy with stale exclusion, 250ms debounce, 5s re-inclusion hysteresis. This is the largest single change. |
| 6 | HIGH | Add `resize_policy` field to AttachSessionResponse (Section 1.6). |
| 7 | HIGH | Update Section 8 multi-client model to reference latest/smallest dual policy instead of hardcoded smallest. |
| 8 | MEDIUM | Add 0x0185 to message type assignments table at top of doc. |
| 21 | HIGH | **Owner decision**: Under `latest` policy, clients with smaller dimensions than the effective size MUST clip to their own viewport (top-left origin), matching tmux behavior. Per-client viewports (scroll to see clipped areas) remain deferred to v2. Add normative statement to Section 5.1 or Section 8. |

#### Doc 04 -- Input & RenderState (2 issues, both from owner review)

| Issue | Severity | Change |
|-------|----------|--------|
| 23 | CRITICAL | **Open design question** (requires team discussion, not mechanical). Per-client dirty bitmap model does not scale: O(N) bitmap maintenance, O(N) frame serialization, no error recovery for client-side state drift. Proposed: adopt I-frame/P-frame model with periodic keyframes. See full analysis below in Section 3. |
| 24 | CRITICAL | **Open design question** (requires team discussion). P-frame diff base: Option A (diff from previous frame, sequential chain) vs Option B (diff from most recent I-frame, independently decodable). Architecturally fundamental — determines whether shared ring buffer eliminates per-client state tracking. See full analysis below in Section 3. |

#### Doc 05 -- CJK Preedit Protocol (1 issue + 1 cosmetic)

| Issue | Severity | Change |
|-------|----------|--------|
| 10 | MEDIUM | Add `"client_evicted"` to PreeditEnd reason values (Section 2.3). Required for Addendum B (preedit commit on eviction). |
| 01 (review-notes-01) | LOW | Lines 349 and 381: replace `empty + vowel` with `null + vowel` in prose notes. Tables/diagrams already correct. |

#### Doc 06 -- Flow Control & Auxiliary (9 issues)

| Issue | Severity | Change |
|-------|----------|--------|
| 12 | CRITICAL | Add 3 fields to FlowControlConfig (0x0502): `resize_exclusion_timeout_ms` (5000), `stale_timeout_ms` (60000/120000), `eviction_timeout_ms` (300000). |
| 13 | CRITICAL | Update buffer limit from 1MB to 512KB in Server Output Queue Management. |
| 14 | CRITICAL | Add PausePane health escalation timeline (T=0s/5s/60s/300s) as new subsection in Section 2. Include stale timeout reset rules (Resolution 9), output queue stagnation trigger (Resolution 10), transport-aware timeout selection (Addendum A). |
| 15 | CRITICAL | Add discard-and-resync pattern (Resolution 14) and stale recovery resync procedure (Resolution 15) as new subsection in Section 2. |
| 16 | HIGH | Update Section 10 timeout table: replace "PausePane: no timeout, waits indefinitely" with 5s/60s/300s escalation. |
| 17 | HIGH | Add heartbeat orthogonality note to Section 7. Reserve 0x0900 for v2 echo_nonce (HEARTBEAT_NONCE capability). |
| 18 | MEDIUM | Add Idle coalescing suppression during resize debounce (250ms window + 500ms grace after TIOCSWINSZ). |
| 19 | MEDIUM | Add preedit-commit-on-eviction to eviction subsection (Addendum B). |
| 20 | MEDIUM | Add ClientHealthChanged (0x0185) to always-sent notifications list in Section 6 default subscriptions. |

### Priority 2: Architectural Design Questions (Issues 22-24) -- REQUIRES TEAM DEBATE

These three issues, raised during owner review, are interconnected and represent a
fundamental architectural question about the output delivery model. They cannot be
resolved with mechanical fixes — they require prior-art research, team discussion,
and consensus.

#### Issue 22: Shared Ring Buffer vs Per-Client Output Buffers

**Problem**: Resolution 13 prescribes "512KB per (client, pane)" buffer allocation,
implying per-client copies of identical frame data. With N clients viewing the same
pane (all see the same terminal state under our shared-focus model), the server copies
the same serialized frame N times.

**Quantified impact** (100 clients, 120×40 CJK worst case):
- Per-frame copy cost: 100 × 116KB = 11.6MB memcpy
- At 60fps: ~696MB/s memory bandwidth for copying identical bytes
- Memory: 100 clients × 4 panes × 512KB = 200MB for buffers alone
- L2/L3 cache thrashing across 400 different buffer locations

**Proposed alternative**: Shared per-pane ring buffer with per-client read cursors.
Server serializes each frame once into the ring. Clients' socket writes read directly
from the ring at their cursor position. Memory: O(panes × ring_size) + O(clients)
for cursors. Memory bandwidth: O(1) write instead of O(N) copies.

**Protocol-visible behavior unchanged**: Same backpressure thresholds, same stale
triggers, same discard-and-resync semantics. The 512KB limit becomes a delivery lag
cap (how far behind a cursor can fall) rather than a buffer allocation.

#### Issue 23: Periodic Keyframes (I-frame/P-frame Model)

**Three interconnected problems with the current per-client dirty bitmap model:**

**(a) Diff calculation cost at scale.** Server maintains per-client dirty bitmaps per
pane. With N clients, every terminal state change requires N bitmap updates. Frame
generation requires N separate serializations because dirty sets diverge across
coalescing tiers (fast Interactive clients are caught up; slow Bulk clients have
accumulated different dirty sets). This is O(N) bitmap maintenance + O(N) frame
serialization per output event.

**(b) No error tolerance.** Protocol relies on reliable transport (TCP/Unix socket
guarantees delivery), but client-side state can silently diverge from server state
through: application bugs in delta application, race conditions, coalescing artifacts
dropping intermediate states. Current design has no detection mechanism and no
auto-recovery — corruption persists indefinitely until an explicit trigger (resize,
reattach, stale recovery). With many active clients, silent divergence is undetectable
by either side.

**(c) Catch-up complexity.** A client behind by K frames needs either: K coalesced
deltas (requires computing the union of K dirty sets — effectively a per-client
operation), or a full resync (heavyweight, requires a special codepath distinct from
normal frame delivery).

**Proposed alternative**: Adopt an I-frame/P-frame model with periodic keyframes,
analogous to MPEG video codecs.

| Concept | Video codec | Terminal protocol |
|---------|-------------|-------------------|
| Keyframe (I-frame) | Full image, self-contained | dirty=full FrameUpdate: all rows, all CellData |
| Delta (P-frame) | Diff from reference | dirty=partial FrameUpdate: only changed rows |
| Keyframe interval | e.g., every 1 second | Configurable (suggested 1-2 seconds) |
| Seek/recovery | Jump to nearest I-frame | Client skips to latest keyframe in ring |

Combined with Issue 22's shared ring buffer: server writes one frame (I or P) to the
ring. Clients read from the ring at their cursor. Clients behind by >= 1 keyframe
interval skip to the latest keyframe. Discard-and-resync becomes simply "advance cursor
to latest keyframe" — same codepath as normal delivery, no special case.

**Keyframe self-containment rule (owner decision)**: Keyframes MUST always carry full
CellData. Never a reference to a previous frame in place of data. A client that just
skipped from a distant cursor has no previous state to reference. Self-containment is
the defining property of a keyframe.

**Advisory `unchanged` hint (owner decision)**: Keyframes MAY include an advisory
`unchanged` boolean (default false). When true, it signals content is identical to
the previous keyframe. Caught-up clients can use this hint to skip re-rendering.
Clients that jumped to this keyframe ignore the hint and render from the full data.
The hint is purely a client-side render optimization — safe to ignore.

**What this eliminates:**
- Per-client dirty bitmaps → one per-pane dirty bitmap
- O(N) frame serialization → O(1) per interval
- O(N) memcpy → O(1) ring write
- Explicit discard-and-resync codepath → "skip to keyframe" (same normal codepath)
- Silent state drift → auto-heals every keyframe interval

**Cost**: ~116KB/s per pane at 1 keyframe/s. 4 panes = ~464KB/s total. Negligible on
local Unix socket. <0.5MB/s on SSH.

#### Issue 24: P-frame Diff Base (Open Design Question)

**This is the single most consequential design choice in the I/P-frame model.** The
owner explicitly chose to leave this to the design team for resolution.

**Option A: P-frame = diff from previous frame (P or I)**

```
I₀ → P₁ → P₂ → P₃ → I₁ → P₄ → ...
      ↑         ↑
      depends   depends
      on I₀     on P₂
```

- Sequential dependency chain. To decode P₃, client needs I₀ + P₁ + P₂ + P₃.
- Smallest individual P-frames (only true delta between consecutive frames).
- **Problem**: Skipping any P invalidates all subsequent P-frames until next I.
  Coalescing (clients at different tiers skip different P-frames) re-introduces
  per-client diff computation — defeating the shared ring buffer model.

**Option B: P-frame = diff from the most recent I-frame (cumulative)**

```
I₀ → P₁ → P₂ → P₃ → I₁ → P₄ → ...
 ↑    ↑    ↑    ↑
 └────┴────┴────┘  all reference I₀
```

- Every P independently decodable with just the current I-frame. No chain.
- Client needs only: latest I + latest P. Skip any number of intermediate P-frames.
- P-frames grow within a keyframe interval (cumulative dirty set). Bounded by
  terminal row count — worst case P = I size (which means all rows changed, so
  the data must be sent anyway).
- **Advantage**: No per-client state tracking at all. Coalescing is trivial — Bulk
  client skips 10 P-frames, receives P₁₁, applies to I₀, done.

**This choice determines whether Issues 22-23 truly eliminate per-client state tracking
(Option B) or merely restructure it (Option A).** The team must resolve this before
implementing the I/P-frame model.

### Priority 3: Open Questions from Protocol Docs (carried forward)

These are documented in the Open Questions sections of docs 03-06. They do not block
v0.7 but should be triaged (resolve, defer explicitly, or close with rationale).
Carried forward unchanged from the v0.5→v0.6 handover.

**Doc 03 (6 questions)**: Last-pane-close behavior, pane minimum size, session
auto-destroy, zoom+split interaction, layout tree compression, pane reuse after exit.

**Doc 04 (6 questions)**: Cell deduplication via style palette IDs, image protocol,
selection protocol, hyperlink encoding, FrameUpdate acknowledgment, notification
coalescing.

**Doc 05 (6 questions)**: Japanese/Chinese composition states, candidate window
protocol, client-side composition prediction, preedit+selection interaction, multiple
simultaneous compositions, undo during composition.

**Doc 06 (9 questions)**: Clipboard size limit, snapshot format versioning, extension
negotiation timing, multi-session snapshots, clipboard sync mode, RendererHealth
interval, extension message ordering, silence detection scope, tier transition
telemetry.

### Priority 4: Per-Client Focus Indicators (v1 nice-to-have, carried forward)

From v0.5 review. Current v0.6 has the building blocks (`client_id`, `client_name`,
`ClientAttached`/`ClientDetached`, now `ClientHealthChanged`) but no per-client focus
tracking. All clients share one `active_pane_id` per session. Natural companion to
per-client viewports (deferred to v2). Can be discussed separately or deferred.

---

## 3. Pre-Discussion Research Tasks

### 3.1 I-frame/P-frame Prior Art Research (NEW -- for Issues 22-24)

Before the team debates Issues 22-24, research how existing systems handle multi-client
frame delivery with varying consumer speeds.

**tmux-expert**:
1. How does tmux's `TTY_BLOCK` / `TTY_NOBLOCK` interact with per-client output buffering?
2. Does tmux maintain per-client dirty state, or does it redraw from authoritative state?
3. How does tmux handle the "discard and redraw" pattern for blocked clients?
4. What triggers a full redraw vs incremental update in tmux's control mode (`-CC`)?
5. Source references: `tty.c` (TTY_BLOCK handling), `screen-write.c` (dirty tracking),
   `server-client.c` (output buffering), `control.c` (control mode output)

**zellij-expert**:
1. Does zellij maintain per-client render state or share one authoritative state?
2. How does zellij's bounded channel (5000 messages) interact with render updates?
3. Does zellij ever send full screen redraws proactively (not just on resize)?
4. How does the plugin rendering pipeline differ from terminal pane rendering?
5. Source references: `server/src/panes/` (render state), `server/src/route.rs` (output
   routing), `server/src/tab/` (tab-level rendering)

**ghostty-expert** (optional but valuable):
1. How does ghostty's dirty tracking work internally (`DirtyRows`, cell invalidation)?
2. Does ghostty distinguish between full-redraw and partial-redraw at the renderer level?
3. How does ghostty coalesce VT output events into render frames?
4. Source references: `src/terminal/Screen.zig` (dirty tracking), `src/renderer/` (frame
   generation), `src/terminal/Terminal.zig` (state management)

**Video codec / streaming protocol research** (optional):
1. How do protocols like RFB (VNC), RDP, and Wayland handle multi-client frame delivery?
2. VNC's framebuffer update model: does it use keyframes? How does it handle slow clients?
3. RDP's progressive rendering: relevant patterns for terminal use case?

### 3.2 Deliverables

Each researcher produces a findings report with specific source file references. Reports
serve as evidence for the team discussion on Issues 22-24. Researchers do NOT make design
recommendations — they report how reference codebases solve the same problems.

---

## 4. Recommended v0.7 Workflow

### Phase 1: Apply Design Resolutions (mechanical, parallelizable)

Apply all 16 resolutions + 3 addenda from `design-resolutions-resize-health.md` to spec
docs. Also apply Issues 1-20 from `review-notes-consistency.md`. These are pre-agreed
changes with explicit instructions — no debate needed.

**Owner assignments:**
- **protocol-architect** (docs 01, 02): Issues 1, 2, 3
- **systems-engineer** (docs 03, 06): Issues 4, 5, 6, 7, 8, 12, 13, 14, 15, 16, 17,
  18, 19, 20, 21
- **cjk-specialist** (docs 04, 05): Issue 10, plus review-notes-01 Issue 01 (cosmetic)

Doc 04 has no mechanical changes. The cjk-specialist should review the systems-engineer's
doc 06 changes for CJK/preedit consistency (preedit bypass, PreeditSync in resync, commit
on eviction).

### Phase 2: Research (parallel with Phase 1)

Spawn research agents for I-frame/P-frame prior art (Section 3.1). Run concurrently with
Phase 1 — the research results inform Phase 3, not Phase 1.

### Phase 3: Design Discussion (Issues 22-24)

Using research findings, the team debates and resolves:

1. **Shared ring buffer vs per-client buffers** (Issue 22): Is the shared ring model
   adopted? If so, how does the 512KB delivery lag cap translate to ring sizing?

2. **Periodic keyframes** (Issue 23): Is the I-frame/P-frame model adopted? If so, what
   is the default keyframe interval? How does the `unchanged` advisory hint interact with
   the wire format (new flag byte? JSON metadata field?)?

3. **P-frame diff base** (Issue 24): Option A (previous frame) vs Option B (most recent
   I-frame). This must be resolved before Issues 22-23 can be finalized, because Option A
   potentially re-introduces per-client state tracking that Issues 22-23 aim to eliminate.

**Recommended discussion order**: Issue 24 first (foundational), then Issue 23 (keyframe
model), then Issue 22 (delivery infrastructure). Each later issue depends on the earlier
resolution.

**If Issues 22-24 are adopted**: Significant changes needed to doc 04 (FrameUpdate wire
format: keyframe flag, `unchanged` hint, dirty bitmap semantics) and doc 06 (output queue
management: ring buffer model, keyframe interval configuration, delivery lag cap
semantics). The systems-engineer and cjk-specialist must collaborate on these changes.

**If Issues 22-24 are deferred**: Document them as v2 items with explicit rationale.
Apply Phase 1 mechanical changes as-is (per-client buffers at 512KB remain normative).

### Phase 4: Verification (MANDATORY)

Cross-document consistency verification. Minimum two rounds with fresh agents per round.
Per the workflow doc: agents from the revision phase MUST NOT serve as verifiers.

### Phase 5: Triage Open Questions (Priority 3)

Review all 27 open questions from docs 03-06. For each: resolve, defer to v2, or close.

---

## 5. Key Decisions Log

Decisions made by the owner during the v0.6 review session that constrain v0.7 work:

| Decision | Context | Constraint |
|----------|---------|------------|
| `latest` as default (**strong preference**) | Owner tested zellij extensively — it behaves as `latest` despite documenting `smallest`, and the UX is excellent. `latest` is the right default. | **Owner's strong preference.** Do not reconsider `smallest` as default without compelling evidence. `smallest` remains available as opt-in server config. |
| `latest` policy clipping | Under `latest`, smaller clients clip top-left (tmux-style) | Normative in doc 03. Per-client viewports deferred to v2. |
| Keyframe self-containment | I-frames always carry full CellData, never reference previous frames | Non-negotiable. Defining property of keyframe. |
| `unchanged` advisory hint | Keyframes MAY include `unchanged` boolean for client render optimization | Advisory only. Clients that jumped from distant cursor MUST ignore and render full data. |
| P-frame diff base | Left to designers | Owner did NOT pre-decide. Both options presented with full trade-off analysis. |
| Shared ring buffer | Proposed, not mandated | Owner raised the concern and the solution but left final adoption to team. |
| Periodic keyframes | Proposed, not mandated | Same as shared ring buffer — owner raised, team decides. |

---

## 6. File Locations

### v0.6 Protocol Documents (current)

| Document | Path |
|----------|------|
| Doc 01 (Protocol Overview) | `docs/libitshell3/02-design-docs/server-client-protocols/v0.6/01-protocol-overview.md` |
| Doc 02 (Handshake) | `docs/libitshell3/02-design-docs/server-client-protocols/v0.6/02-handshake-capability-negotiation.md` |
| Doc 03 (Session/Pane Mgmt) | `docs/libitshell3/02-design-docs/server-client-protocols/v0.6/03-session-pane-management.md` |
| Doc 04 (Input/RenderState) | `docs/libitshell3/02-design-docs/server-client-protocols/v0.6/04-input-and-renderstate.md` |
| Doc 05 (CJK Preedit) | `docs/libitshell3/02-design-docs/server-client-protocols/v0.6/05-cjk-preedit-protocol.md` |
| Doc 06 (Flow Control) | `docs/libitshell3/02-design-docs/server-client-protocols/v0.6/06-flow-control-and-auxiliary.md` |

### v0.6 Design Artifacts

| Document | Path |
|----------|------|
| Design Resolutions (resize + health) | `docs/libitshell3/02-design-docs/server-client-protocols/v0.6/design-resolutions-resize-health.md` |
| Research: tmux resize/health | `docs/libitshell3/02-design-docs/server-client-protocols/v0.6/research-tmux-resize-health.md` |
| Research: zellij resize/health | `docs/libitshell3/02-design-docs/server-client-protocols/v0.6/research-zellij-resize-health.md` |

### v0.6 Review Notes

| Document | Path |
|----------|------|
| Review Notes 01 (cosmetic, 1 issue) | `docs/libitshell3/02-design-docs/server-client-protocols/v0.6/review-notes-01.md` |
| Review Notes: Consistency (17 issues) | `docs/libitshell3/02-design-docs/server-client-protocols/v0.6/review-notes-consistency.md` |
| Review Notes: Owner Review (4 issues) | `docs/libitshell3/02-design-docs/server-client-protocols/v0.6/review-notes-owner-review.md` |
| This handover | `docs/libitshell3/02-design-docs/server-client-protocols/v0.6/handover-for-v07-revision.md` |

### v0.5 Handover (predecessor)

| Document | Path |
|----------|------|
| v0.5→v0.6 handover | `docs/libitshell3/02-design-docs/server-client-protocols/v0.5/handover-for-v06-revision.md` |
| v0.5 identifier consensus | `docs/libitshell3/02-design-docs/server-client-protocols/v0.5/handover-identifier-consensus.md` |

### IME Interface Contract (cross-reference)

| Document | Path |
|----------|------|
| IME contract v0.5 (current) | `docs/libitshell3-ime/02-design-docs/interface-contract/v0.5/01-interface-contract.md` |
| IME v0.5→v0.6 handover | `docs/libitshell3-ime/02-design-docs/interface-contract/v0.5/handover-for-v06-revision.md` |

### Reference Codebases

| Reference | Path |
|-----------|------|
| tmux | `~/dev/git/references/tmux/` |
| zellij | `~/dev/git/references/zellij/` |
| ghostty | `~/dev/git/references/ghostty/` |
| iTerm2 | `~/dev/git/references/iTerm2/` |
