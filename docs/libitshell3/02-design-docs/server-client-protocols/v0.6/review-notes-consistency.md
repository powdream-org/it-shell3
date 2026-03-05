# Review Notes: v0.6 Cross-Document Consistency

**Date**: 2026-03-05
**Reviewers**: protocol-architect, systems-engineer, cjk-specialist
**Scope**: All 6 protocol v0.6 design docs checked against each other and against `design-resolutions-resize-health.md`
**Verdict**: 21 issues found (9 CRITICAL, 7 HIGH, 5 MEDIUM). Design resolutions not applied to specs.

---

## Finding 0: Systematic Gap -- Design Resolutions Not Applied

The `design-resolutions-resize-health.md` file defines 16 resolutions and 3 addenda covering multi-client resize policy, client health model, buffer limits, timeouts, preedit bypass, and more. Its own "Doc changes needed" table (lines 421-434) explicitly lists required changes to docs 01, 03, 06, and notes "No changes" for docs 02, 04, 05. **None of these changes have been made.** The v0.6 changelogs in all 6 docs reference only the consistency-review fixes (Issues 1-21 from `review-notes-01.md`), not the design-resolution changes.

This means the protocol docs labeled "v0.6" do not actually contain the v0.6 features. They contain only mechanical consistency fixes from the earlier review.

---

## Issue List

### Doc 01 -- Protocol Overview

| # | Severity | Location | Description | Resolution ref |
|---|----------|----------|-------------|----------------|
| 1 | **CRITICAL** | Sec 4.2, Session & Pane Mgmt table | `ClientHealthChanged` (0x0185, S->C) missing from message type registry. Registry goes 0x0183 (ClientDetached) -> 0x0190 (WindowResize). Must add 0x0185 entry. | Resolution 12 |
| 2 | **HIGH** | General | No overview of resize policy (`latest`/`smallest`) or health state model (`healthy`/`stale`). The resolutions document says "Doc 01: Add resize policy description, health state model overview." Not present anywhere in doc 01. | Resolutions 1, 7 |

### Doc 02 -- Handshake & Capability Negotiation

| # | Severity | Location | Description | Resolution ref |
|---|----------|----------|-------------|----------------|
| 3 | **MEDIUM** | Sec 11.1, Disconnect reason enum | Disconnect reason values are: `"normal"`, `"error"`, `"timeout"`, `"version_mismatch"`, `"auth_failed"`, `"server_shutdown"`, `"replaced"`. Missing `"stale_client"`. Resolution 8 specifies `Disconnect(STALE_CLIENT)` at T=300s eviction. | Resolution 8 |

### Doc 03 -- Session & Pane Management

| # | Severity | Location | Description | Resolution ref |
|---|----------|----------|-------------|----------------|
| 4 | **CRITICAL** | Sec 4 (Notifications) | `ClientHealthChanged` (0x0185) notification entirely missing. Should be added after ClientDetached (0x0184) with JSON payload schema (`session_id`, `client_id`, `client_name`, `health`, `previous_health`, `reason`, `excluded_from_resize`), reason values (`"pause_timeout"`, `"queue_stagnation"`, `"recovered"`), and always-sent behavior (no subscription required). | Resolution 12 |
| 5 | **CRITICAL** | Sec 5.1, resize algorithm | Still describes smallest-only: "effective terminal size is `min(cols)` x `min(rows)` across all attached clients (like tmux)." Must be rewritten for latest/smallest dual-policy model with stale client exclusion, 250ms resize debounce per pane, and 5-second re-inclusion hysteresis after stale recovery. | Resolutions 1, 3, 5, 6 |
| 6 | **HIGH** | Sec 1.6, AttachSessionResponse | Missing `resize_policy` field. Response should include `"resize_policy": "latest"` (or `"smallest"`) as an informational field reporting the server's active policy. | Resolution 4 |
| 7 | **HIGH** | Sec 8, Multi-Client Window Size | Still says "The effective terminal size for a session is `min(cols)` x `min(rows)` across all attached clients." Must reference the latest/smallest dual-policy model from Section 5.1. | Resolutions 1, 3 |
| 8 | **MEDIUM** | Message type assignments table (top of doc) | 0x0185 (`ClientHealthChanged`) missing from the table. Currently the Notifications block lists 0x0180-0x0184 only. | Resolution 12 |

### Doc 04 -- Input & RenderState

| # | Severity | Location | Description | Resolution ref |
|---|----------|----------|-------------|----------------|
| 9 | NONE | -- | No v0.6 resolution changes required. Design resolutions confirm "Doc 04 -- No changes." Verified consistent. | -- |

### Doc 05 -- CJK Preedit Protocol

| # | Severity | Location | Description | Resolution ref |
|---|----------|----------|-------------|----------------|
| 10 | **MEDIUM** | Sec 2.3, PreeditEnd reason values | Missing `"client_evicted"` reason. Addendum B specifies that when the server evicts a stale client at T=300s, any active preedit must be committed and `PreeditEnd` with `reason: "client_evicted"` sent to remaining peer clients before the Disconnect. This reason value does not exist in doc 05's PreeditEnd reason enum. | Addendum B |
| 11 | NONE | Sec 7.3 | Resize+preedit ordering confirmed correct. Already specifies FrameUpdate before PreeditUpdate when both triggered by same resize event. Preedit text unaffected by resize (only display position changes). No changes needed. | CJK Validation #1 |

### Doc 06 -- Flow Control & Auxiliary

| # | Severity | Location | Description | Resolution ref |
|---|----------|----------|-------------|----------------|
| 12 | **CRITICAL** | Sec 2.3, FlowControlConfig (0x0502) payload | Missing 3 new fields from Resolution 8: `resize_exclusion_timeout_ms` (default 5000), `stale_timeout_ms` (default 60000 local / 120000 SSH), `eviction_timeout_ms` (default 300000). These must be added to the FlowControlConfig JSON schema and the FlowControlConfigAck effective values. | Resolution 8, Addendum A |
| 13 | **CRITICAL** | Sec 2, Server Output Queue Management table | Buffer limit still says "Max size per pane per client: 1 MB." Resolution 13 explicitly states "Doc 06 Section 2 should be updated from 1MB to 512KB." Must change to 512 KB. | Resolution 13 |
| 14 | **CRITICAL** | Sec 2 (new subsection needed) | Missing PausePane health escalation timeline. Resolution 8 defines: T=0s PausePane (client still healthy) -> T=5s resize exclusion (server-internal, no protocol message) -> T=60s local / T=120s SSH stale transition (ClientHealthChanged 0x0185 to peers) -> T=300s eviction (Disconnect with reason "stale_client"). Also missing: stale timeout resets on application-level messages only (Resolution 9), output queue stagnation as stale trigger (Resolution 10), and transport-aware timeout selection via ClientDisplayInfo.transport_type (Addendum A). | Resolutions 7, 8, 9, 10, Addendum A |
| 15 | **CRITICAL** | Sec 2 (new subsection needed) | Missing discard-and-resync pattern (Resolution 14) and resync procedure on stale recovery (Resolution 15). When buffer is exceeded or client recovers from stale: discard all buffered frames, send dirty=full FrameUpdate, resume incremental. On stale recovery (ContinuePane): send LayoutChanged if layout changed while stale, dirty=full FrameUpdate per pane with all metadata, PreeditSync per pane for CJK clients with active composition. | Resolutions 14, 15 |
| 16 | **HIGH** | Sec 10, Timeout Handling table | Row "PausePane without ContinuePane: No timeout, Server compacts queue, waits indefinitely" directly contradicts Resolution 8. Must be updated to reflect the 5s/60s/300s escalation timeline with 300s eviction. | Resolution 8 |
| 17 | **HIGH** | Sec 7, Heartbeat and Connection Health | Missing heartbeat orthogonality note. Resolution 11 states heartbeat is connection liveness (90s timeout -> Disconnect), while health states are application responsiveness (output queue + PausePane duration). These are independent systems. Also missing: echo_nonce reservation in 0x0900 range for v2 HEARTBEAT_NONCE capability, and server-side heartbeat RTT as non-normative implementation heuristic. | Resolution 11 |
| 18 | **MEDIUM** | Sec 1 (coalescing) or new subsection | Missing Idle coalescing suppression during resize debounce. Addendum C specifies: during the 250ms resize debounce window and for 500ms after ioctl(TIOCSWINSZ), the server MUST NOT transition the pane's coalescing tier to Idle. The resolutions document says "Doc 06 Section 5: Note Idle suppression during resize debounce + 500ms grace." | Addendum C |
| 19 | **MEDIUM** | Sec 2 (eviction subsection) | Missing commit-active-preedit-on-eviction behavior. Addendum B: when server evicts a stale client at T=300s, any active preedit composition owned by that client MUST be committed (flushed to terminal grid). Server sends PreeditEnd with `reason: "client_evicted"` to remaining peer clients before the Disconnect. | Addendum B |
| 20 | **MEDIUM** | Sec 6, Default Subscriptions list | Once ClientHealthChanged (0x0185) is added to doc 03, it must also be added to the default subscriptions list in doc 06 Section 6 as an always-sent notification (no subscription required), matching the 0x0180-0x018x convention per Resolution 12. Currently the list covers: LayoutChanged, SessionListChanged, PaneMetadataChanged, ClientAttached, ClientDetached. | Resolution 12 |

---

## Summary Statistics

| Severity | Count | Affected docs |
|----------|-------|---------------|
| CRITICAL | 9 | Doc 01 (1), Doc 03 (2), Doc 04 (2), Doc 06 (4) |
| HIGH | 7 | Doc 01 (1), Doc 03 (3), Doc 06 (3) |
| MEDIUM | 5 | Doc 02 (1), Doc 03 (1), Doc 05 (1), Doc 06 (2) |
| NONE (confirmed OK) | 2 | Doc 04, Doc 05 Sec 7.3 |
| **Total** | **23** (21 issues + 2 confirmations) | |

**By document:**

| Document | CRITICAL | HIGH | MEDIUM | Total issues |
|----------|----------|------|--------|-------------|
| Doc 01 | 1 | 1 | 0 | 2 |
| Doc 02 | 0 | 0 | 1 | 1 |
| Doc 03 | 2 | 3 | 1 | 6 |
| Doc 04 | 2 | 0 | 0 | 2 |
| Doc 05 | 0 | 0 | 1 | 1 |
| Doc 06 | 4 | 3 | 2 | 9 |

### Doc 03 (continued)

| # | Severity | Location | Description | Resolution ref |
|---|----------|----------|-------------|----------------|
| 21 | **HIGH** | Sec 5.1 or Sec 8 | Under `latest` policy, clients with smaller dimensions than the effective size receive FrameUpdates for a larger grid than they can display. The spec does not define what the smaller client should do. **Required addition**: Normative statement that clients MUST clip to their own viewport dimensions (top-left origin), matching tmux `latest` policy behavior. Per-client viewports (scroll to see clipped areas) remain deferred to v2. | Resolution 1 |

### Doc 06 (continued)

| # | Severity | Location | Description | Resolution ref |
|---|----------|----------|-------------|----------------|
| 22 | **HIGH** | Sec 2, Server Output Queue Management | Resolution 13 prescribes "512KB per (client, pane)" buffer allocation. This implies per-client copies of identical frame data. With N clients viewing the same pane, the server copies the same serialized frame N times — O(N) memory bandwidth for identical content. At 100 clients, a single 120×40 CJK scroll frame (~116KB) becomes 11.6MB of memcpy per frame, ~696MB/s at 60fps. **Required change**: Reframe Resolution 13 as a **delivery lag cap** ("a client may fall at most 512KB behind the current frame sequence") rather than a per-client buffer allocation. Document shared ring buffer with per-client read cursors as the recommended implementation pattern: server serializes each frame once into a shared per-pane ring; each client's socket write reads from the ring at its cursor position; when a cursor falls behind the ring tail, discard-and-resync. This preserves all protocol-visible behavior (same backpressure thresholds, same stale triggers, same discard-and-resync semantics) while reducing memory from O(clients × panes × buffer) to O(panes × ring) + O(clients) cursors, and memory bandwidth from O(clients) copies to O(1) write. | Resolution 13, Resolution 14 |

| # | Severity | Location | Description | Resolution ref |
|---|----------|----------|-------------|----------------|
| 23 | **CRITICAL** | Sec 2 (output queue), Doc 04 Sec 4 (FrameUpdate dirty tracking) | **Per-client dirty bitmap model does not scale and lacks error recovery.** Three interconnected problems: **(a) Diff calculation cost**: Server maintains per-client dirty bitmaps per pane. With N clients, every terminal state change requires N bitmap updates, and frame generation requires N separate serializations (dirty sets diverge across coalescing tiers). At 100 clients this is O(N) bitmap maintenance + O(N) frame serialization per output event. **(b) No error tolerance**: Protocol relies on reliable transport (no frame loss), but client-side state can silently diverge from server state (application bugs, race conditions in delta application, coalescing artifacts). Current design has no detection or auto-recovery — corruption persists until an explicit trigger (resize, reattach, stale recovery). With many active clients, silent divergence is undetectable. **(c) Catch-up complexity**: A client behind by K frames needs either K coalesced deltas (complex union of dirty sets) or a full resync (heavyweight, requires special codepath). **Proposed change**: Adopt an I-frame/P-frame model with periodic keyframes, analogous to MPEG. The server emits dirty=full "keyframe" FrameUpdates at a configurable interval (e.g., every 1-2 seconds) alongside incremental "delta" FrameUpdates. Combined with Issue 22's shared ring buffer: server writes one frame (I or P) to a shared per-pane ring; clients read from the ring at their cursor position; clients behind by >= 1 keyframe interval skip to the latest keyframe instead of replaying deltas. This eliminates per-client dirty bitmaps (server tracks one bitmap per pane, cleared on each frame write), provides automatic self-healing of client state corruption within the keyframe interval, and reduces frame serialization from O(clients) to O(1) per interval. Cost: ~116KB/s per pane at 1 keyframe/s (negligible on local socket, <0.5MB/s total on SSH for 4 panes). Keyframes MUST always carry full CellData — never a reference to a previous frame in place of data. Self-containment is the defining property of a keyframe; a client that just skipped from a distant cursor has no previous state to reference. However, the keyframe MAY include an advisory `unchanged` boolean hint (default false). When true, it signals that the content is identical to the previous keyframe. Caught-up clients can use this hint to skip re-rendering; clients that jumped to this keyframe ignore the hint and render from the full data as normal. Discard-and-resync (Resolution 14) becomes simply "advance cursor to latest keyframe" — no special codepath needed. | Resolution 13, Resolution 14 |

| # | Severity | Location | Description | Resolution ref |
|---|----------|----------|-------------|----------------|
| 24 | **CRITICAL** | Doc 04 (FrameUpdate), Doc 06 (flow control) | **Open design question: P-frame diff base.** If Issues 22-23 adopt an I-frame/P-frame model, the team must decide the P-frame's reference point. **Option A**: P-frame = diff from previous frame (P or I). Smallest individual P-frames, but creates sequential dependency chain — skipping any P invalidates all subsequent P-frames until the next I. Coalescing (clients at different tiers skip different P-frames) re-introduces per-client diff computation, defeating the shared ring buffer model. **Option B**: P-frame = diff from the most recent I-frame (cumulative). Every P is independently decodable given only the current I-frame. Clients can skip any number of intermediate P-frames and apply the latest P directly. No sequential dependency, no per-client dirty tracking. Trade-off: P-frames grow within a keyframe interval as the cumulative dirty set expands; bounded by terminal row count. This choice is architecturally fundamental — it determines whether the shared ring buffer (Issue 22) can truly eliminate per-client state tracking or merely defer it. **Leave to designers for resolution.** | Issues 22, 23 |

---

## Root Cause

The v0.6 tag was applied after a consistency review pass that fixed mechanical issues (Issues 1-21 from `review-notes-01.md`: missing registry entries, terminology standardization, direction fixes, etc.). The design resolutions document (`design-resolutions-resize-health.md`) was produced from a separate 4-round discussion about multi-client resize policy and client health model, but those resolutions were never applied to the protocol specs. The v0.6 docs essentially contain v0.5 content + consistency fixes, not the actual v0.6 features.

The v0.6 changelogs in all 6 docs reference only the consistency-review fixes. None reference the design-resolution changes.

---

## Recommendation

1. **Apply all 16 resolutions + 3 addenda** from `design-resolutions-resize-health.md` to docs 01, 02, 03, 05, and 06. The resolutions document's "Doc changes needed" table provides a precise checklist.

2. **Per-document breakdown of required changes:**
   - **Doc 01**: Add 0x0185 to message type registry. Add resize policy and health model overview (new section or additions to existing sections).
   - **Doc 02**: Add `"stale_client"` to Disconnect reason enum.
   - **Doc 03**: Add ClientHealthChanged (0x0185) notification to Section 4 and message type table. Add `resize_policy` to AttachSessionResponse. Rewrite Section 5.1 resize algorithm for latest/smallest dual policy with stale exclusion, 250ms debounce, 5s hysteresis. Update Section 8 multi-client model.
   - **Doc 04**: No changes needed.
   - **Doc 05**: Add `"client_evicted"` to PreeditEnd reason values.
   - **Doc 06**: Add health timeout fields to FlowControlConfig. Update buffer limit to 512KB. Add PausePane health escalation timeline (5s/60s/300s). Add discard-and-resync and stale recovery resync procedure. Update PausePane timeout row. Add heartbeat orthogonality note and echo_nonce v2 reservation. Add Idle suppression during resize debounce. Add preedit-commit-on-eviction. Add ClientHealthChanged to default subscriptions.

3. **After applying, run a second consistency verification round** to confirm the changes are correct, complete, and did not introduce new inconsistencies. Both spec areas (protocol team + any affected cross-team) should participate.
