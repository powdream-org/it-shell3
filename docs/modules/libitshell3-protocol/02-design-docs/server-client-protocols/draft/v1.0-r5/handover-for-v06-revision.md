# Handover: Protocol v0.5 to v0.6 Revision

> **Date**: 2026-03-05
> **Author**: protocol-architect
> **Scope**: All items requiring resolution in the v0.6 protocol revision

---

## 1. What v0.5 Accomplished

v0.5 was a consolidation release with two main workstreams:

1. **Input method identifier unification** (handover-identifier-consensus.md): Replaced the
   split `LanguageId` enum + `layout_id` pair with a single canonical `input_method` string
   flowing unchanged from client to server to IME engine. 10-point consensus applied across
   all 6 protocol docs and IME contract v0.4. The `"korean_3set_390" -> "3f"` mapping bug
   was fixed (correct: `"39"`). Cross-component mapping tables removed; canonical registry
   now lives solely in IME Interface Contract, Section 3.7.

2. **Cross-review with IME contract v0.3**: 11 cross-component issues resolved. 8 mechanical
   (Source B) + 6 consensus (Source A) changes applied to protocol docs. composition_state
   `ko_` prefix and stale reference cleanup verified in two rounds.

Additional v0.5 changes: multi-session client model (Section 5.5 of doc 01), version byte
semantics clarified (wire format only), ERR_DECOMPRESSION_FAILED removed, `active_` prefix
convention documented, compression pseudocode updated.

---

## 2. Open Items for v0.6

### Priority 1: Cross-Document Consistency Fixes (20 issues)

**Source**: `review-notes-consistency.md`

All 20 issues are documentation inconsistencies -- no structural protocol design flaws.
These are mechanical fixes that can be applied without team debate.

**HIGH severity (6 issues -- apply first)**:

| ID | Summary | Affected Docs | Fix |
|----|---------|---------------|-----|
| 1 | Doc 01 registry missing message types from docs 03/06 | 01 | Add all pane response types, WindowResizeAck, and per-message rows for 0x0500-0x0AFF ranges |
| 2 | ERR_PROTOCOL_ERROR referenced but undefined | 01 | Add to error code table (Section 6.3) with numeric code |
| 3 | Doc 04 references removed ERR_DECOMPRESSION_FAILED | 04 | Replace with ERR_PROTOCOL_ERROR (line 929) |
| 4 | DetachSession field drift between docs 02/03 | 02 | Remove `reason` from request; adopt doc 03's response schema; fix reason string values |
| 18 | ko_vowel_only missing from state transitions | 05 | Add transitions to state diagram (Section 3.2) and table (Section 3.3) |
| 19 | display_width missing from FrameUpdate preedit section | 04, 05 | Add `display_width` (u8) to doc 04 FrameUpdate preedit; update doc 05 Section 10.1 |

**MEDIUM severity (6 issues)**:

| ID | Summary | Affected Docs | Fix |
|----|---------|---------------|-----|
| 5 | pixel_width/pixel_height in doc 02 but not doc 03 | 02 | Remove from CreateSessionRequest/AttachSessionRequest |
| 6 | Dual ClientDisplayInfo definition | 02, 06 | Doc 06 authoritative; doc 02 cross-references |
| 7 | ConnectionClosing should be Disconnect in doc 06 | 06 | Replace at lines 984, 991 |
| 8 | num_dirty_rows vs dirty_row_count terminology | 04, 05, 06 | Standardize on `num_dirty_rows` (doc 04 authoritative) |
| 9 | Dangling FrameAck reference | 02 | Remove or replace |
| 10 | KeyInput vs KeyEvent naming | 02 | Replace with KeyEvent |

**LOW severity (8 issues)**:

| ID | Summary | Affected Docs | Fix |
|----|---------|---------------|-----|
| 11 | PreeditEnd reason CANCELLED vs doc 05 values | 02 | Align with doc 05's defined reasons |
| 12 | Readonly cross-refs point to doc 02 not doc 03 | 04, 05 | Point to doc 03 Section 9 |
| 13 | Redundant readonly/heartbeat definitions | 03-06 | Replace with cross-references |
| 14 | Heartbeat direction inconsistency | 01 | Clarify server-initiated-only vs bidirectional |
| 15 | Non-canonical identifiers in state diagram | 05 | Use canonical `input_method` strings; remove hex codes |
| 16 | PaneMetadataChanged vs opt-in notification distinction undocumented | 03, 06 | Add clarifying note |
| 17 | preedit_sync description ambiguous | 02 | Tighten to PreeditSync-only semantics |
| 20 | "4-tier" vs "5-state" coalescing terminology | 01, 04, 05, 06 | Choose one; document Idle exception if keeping "4-tier" |

Full details with line numbers and fix instructions: `review-notes-consistency.md`.

**Owner assignments** (from the consistency review):
- **protocol-architect** (docs 01, 02): Issues 1, 2, 4, 5, 6, 9, 10, 11, 14, 17
- **systems-engineer** (docs 03, 06): Issues 7, 8 (doc 06), 16, 20 (doc 06)
- **cjk-specialist** (docs 04, 05): Issues 3, 8 (docs 04/05), 12, 13, 15, 18, 19, 20 (docs 04/05)

### Priority 2: Design Issues Requiring Team Discussion

These are substantive design gaps that need research, team debate, and consensus before
changes can be applied to the protocol docs.

#### 2a. Multi-Client Window Resize Policy (potential DoS)

**Source**: `review-notes-01-per-client-focus-indicators.md`, Issue 2 (lines 189-318)
**Severity**: Design gap -- paused/unresponsive client can shrink PTY for all healthy clients
**Related docs**: doc 03 Section 5.1, doc 06 Section 2

**Problem**: The "smallest client wins" resize algorithm (`min(cols) x min(rows)`) counts
paused or unresponsive clients' stale dimensions. A hung client with a small window
permanently constrains all healthy clients.

**Questions to resolve**:
1. Exclude paused clients' dimensions from `min()` after a grace period?
2. Resize cascade on resume -- how to avoid flicker?
3. Configurable "stale client resize timeout" (e.g., 30s)?
4. Server policy vs capability-negotiated behavior?

**Pre-requisite**: Research tasks in Section 3 below.

#### 2b. Client Health Model (no intermediate states)

**Source**: `review-notes-01-per-client-focus-indicators.md`, Issue 3 (lines 322-506)
**Severity**: Design gap -- protocol robustness
**Related docs**: doc 01 Section 5.4, doc 02 Section 11.2, doc 06 Sections 2 and 7

**Gaps identified**:
1. PausePane has no timeout -- client never calls ContinuePane, buffers grow indefinitely
2. No intermediate health states (only alive or dead after 90s heartbeat timeout)
3. No stale client eviction beyond heartbeat timeout
4. No health reporting to other clients (only join/leave notifications exist)
5. No application-level health check (heartbeat only proves TCP is alive)

**Possible approaches** (starting points, not recommendations):
- PausePane timeout (simplest -- addresses resource leak)
- Client health states: healthy -> degraded -> paused -> stale -> evicted
- ClientHealthChanged notification (0x0185+ range)
- Application-level heartbeat with nonce

**Interaction**: Issue 2b directly feeds into Issue 2a. If the protocol gains health states,
the resize algorithm can use health state as exclusion criteria rather than inventing
separate staleness tracking.

**Pre-requisite**: Research tasks in Section 3 below.

#### 2c. Per-Client Focus Indicators (v1 nice-to-have)

**Source**: `review-notes-01-per-client-focus-indicators.md`, Issue 1 (lines 1-186)
**Severity**: Enhancement -- v1 nice-to-have, not blocker

**Current state**: v0.5 has the building blocks (`client_id`, `client_name`,
`ClientAttached`/`ClientDetached`) but no per-client focus tracking. All clients share one
`active_pane_id` per session.

**What would be needed** (non-normative sketch):
- Per-client `focused_pane_id` tracking on server
- Decision: display-only focus vs independent input routing (zellij independent mode)
- New messages: `ClientFocusChanged`, `ListAttachedClients` (0x0185+ range)
- Client-side rendering of focus indicators (tab bar, pane frames)

**Zellij reference**: Detailed analysis of zellij's mirrored vs independent modes,
color assignment, server-side computation, and rendering approach is captured in the
review notes (Section 3).

**Interaction**: Natural companion to per-client viewports (deferred to v2 per doc 02
line 922). Design together if pursuing as v1 nice-to-have.

### Priority 3: Open Questions from Protocol Docs

These are questions documented in the Open Questions sections of docs 03-06. They do not
block v0.6 but should be triaged (resolve, defer explicitly, or close with rationale).

**Doc 03 (Session/Pane Management) -- 6 questions**:
1. Last-pane-close auto-destroys session? (Current: yes)
2. Pane minimum size? (Suggestion: 2 cols x 1 row, matching tmux)
3. Session auto-destroy on no attached clients? (Current: never)
4. Zoom + split interaction? (tmux unzooms first)
5. Layout tree compression for large trees? (Deferrable -- ~50 panes = few KB JSON)
6. Pane reuse after exit? (tmux `remain-on-exit` pattern)

**Doc 04 (Input/RenderState) -- 6 questions**:
1. Cell deduplication via style palette IDs? (Reduces 20B -> ~10B per cell)
2. Image protocol (Sixel/Kitty)? (Deferred to future spec)
3. Selection protocol for multi-client sync?
4. Hyperlink data (OSC 8) encoding?
5. FrameUpdate acknowledgment for flow control?
6. Notification coalescing (batch vs separate)?

**Doc 05 (CJK Preedit) -- 6 questions**:
1. Japanese/Chinese composition states?
2. Candidate window protocol?
3. Client-side composition prediction for high-latency SSH?
4. Preedit and selection interaction? (Current: commit preedit first)
5. Multiple simultaneous compositions (per-pane)?
6. Undo (Cmd+Z) during composition?

**Doc 06 (Flow Control/Auxiliary) -- 9 questions**:
1. Clipboard size limit? (Suggestion: 10 MB)
2. Snapshot format versioning?
3. Extension negotiation timing (before/after auth)?
4. Multi-session vs per-session snapshots?
5. Clipboard sync mode (auto/manual/configurable)?
6. RendererHealth interval minimum? (Suggestion: 1000 ms)
7. Extension message ordering?
8. Silence detection scope (activity-then-silence pattern)?
9. Tier transition telemetry? (Defer -- RendererHealth sufficient for v1)

### Priority 4: Previously Carried-Forward Items (Now Resolved or Low Priority)

**SSH vs TLS transport**: Resolved in v0.5. Doc 01 Section 2.2 documents the decision
("SSH tunneling, not custom TCP+TLS") with full rationale. Decision rationale table
(Section 11) marks it as **Decided**. The previous handover's note that "rationale section
could be made more explicit" has been addressed. No further action needed.

---

## 3. Pre-Discussion Research Tasks

The following research MUST be completed before the team discusses Issues 2a and 2b.
Assign to tmux-expert and zellij-expert agents respectively.

### 3.1 tmux Research (tmux-expert)

**For Issue 2a (multi-client resize)**:
1. Document `window-size` option policies: `smallest`, `largest`, `latest`, `manual`
2. Document `aggressive-resize` per-window option and its interaction with `window-size`
3. Investigate unresponsive client exclusion from size calculation
4. Trace resize event flow from client report to PTY `TIOCSWINSZ` ioctl

**For Issue 2b (client health model)**:
1. How tmux detects unresponsive/slow clients (look for `server_client_check`)
2. Backoff and eviction escalation path
3. Per-client output buffering limits
4. Application-level vs OS-level keepalive
5. Slow client impact isolation (does one slow client cause backpressure on others?)

**Source**: `~/dev/git/references/tmux/`

### 3.2 zellij Research (zellij-expert)

**For Issue 2a (multi-client resize)**:
1. Multi-client sizing strategy (mirrored vs independent mode)
2. Unresponsive client handling in resize
3. Resize propagation path with debounce/coalescing
4. Per-client viewport sizing (if independent focus supported)

**For Issue 2b (client health model)**:
1. Client health detection mechanisms
2. Unresponsive client actions (disconnect/pause/degrade)
3. Per-client output flow control and backpressure
4. Thread architecture and per-client isolation
5. Plugin client vs terminal client policies

**Source**: `~/dev/git/references/zellij/`

### 3.3 Deliverables

Each researcher produces a findings report with specific source file references (file paths,
function/struct names). Reports are input to team discussion on Issues 2a and 2b.

---

## 4. Recommended v0.6 Workflow

1. **Phase 1 (mechanical)**: Apply all 20 consistency fixes (Priority 1). These are
   pre-agreed fixes with explicit instructions -- no debate needed. Can be parallelized
   across three owners (protocol-architect, systems-engineer, cjk-specialist).

2. **Phase 2 (research)**: Spawn tmux-expert and zellij-expert for research tasks
   (Section 3). Run in parallel with Phase 1.

3. **Phase 3 (design)**: Team discussion on Issues 2a (resize) and 2b (health model)
   using research findings. These two issues are tightly coupled -- discuss together.
   Issue 2c (focus indicators) can be discussed separately or deferred.

4. **Phase 4 (triage)**: Review Priority 3 open questions. For each: resolve with a
   decision, defer explicitly to v2 with rationale, or close as not-applicable.

5. **Phase 5 (verification)**: Cross-document consistency check on the revised v0.6 docs.
   Minimum two verification rounds (lesson from v0.4/v0.5 cross-verification).

---

## 5. File Locations

### v0.5 Protocol Documents

| Document | Path |
|----------|------|
| Doc 01 (Protocol Overview) | `docs/modules/libitshell3/02-design-docs/server-client-protocols/draft/v1.0-r5/01-protocol-overview.md` |
| Doc 02 (Handshake) | `docs/modules/libitshell3/02-design-docs/server-client-protocols/draft/v1.0-r5/02-handshake-capability-negotiation.md` |
| Doc 03 (Session/Pane Mgmt) | `docs/modules/libitshell3/02-design-docs/server-client-protocols/draft/v1.0-r5/03-session-pane-management.md` |
| Doc 04 (Input/RenderState) | `docs/modules/libitshell3/02-design-docs/server-client-protocols/draft/v1.0-r5/04-input-and-renderstate.md` |
| Doc 05 (CJK Preedit) | `docs/modules/libitshell3/02-design-docs/server-client-protocols/draft/v1.0-r5/05-cjk-preedit-protocol.md` |
| Doc 06 (Flow Control) | `docs/modules/libitshell3/02-design-docs/server-client-protocols/draft/v1.0-r5/06-flow-control-and-auxiliary.md` |

### v0.5 Review Notes and Handovers

| Document | Path |
|----------|------|
| Review Notes: Focus, Resize, Health | `docs/modules/libitshell3/02-design-docs/server-client-protocols/draft/v1.0-r5/review-notes-01-per-client-focus-indicators.md` |
| Review Notes: Consistency (20 issues) | `docs/modules/libitshell3/02-design-docs/server-client-protocols/draft/v1.0-r5/review-notes-consistency.md` |
| Handover: Identifier Consensus | `docs/modules/libitshell3/02-design-docs/server-client-protocols/draft/v1.0-r5/handover-identifier-consensus.md` |

### IME Interface Contract

| Document | Path |
|----------|------|
| IME Contract v0.4 | `docs/modules/libitshell3-ime/02-design-docs/interface-contract/draft/v1.0-r4/01-interface-contract.md` |

### Reference Codebases

| Reference | Path |
|-----------|------|
| tmux | `~/dev/git/references/tmux/` |
| zellij | `~/dev/git/references/zellij/` |
| ghostty | `vendors/ghostty/` |
