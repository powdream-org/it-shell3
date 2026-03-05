# Review Notes: v0.6 Cross-Document Consistency

**Date**: 2026-03-05
**Reviewers**: protocol-architect, systems-engineer, cjk-specialist
**Scope**: All 6 protocol v0.6 design docs checked against each other and against `design-resolutions-resize-health.md`
**Verdict**: 17 issues found (7 CRITICAL, 5 HIGH, 5 MEDIUM). Design resolutions not applied to specs.

> **Related review notes:**
> - `review-notes-01.md` -- Residual cosmetic issue (1 item)
> - `review-notes-owner-review.md` -- Owner architectural review (4 items: Issues 21-24)

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
| CRITICAL | 7 | Doc 01 (1), Doc 03 (2), Doc 06 (4) |
| HIGH | 5 | Doc 01 (1), Doc 03 (2), Doc 06 (2) |
| MEDIUM | 5 | Doc 02 (1), Doc 03 (1), Doc 05 (1), Doc 06 (2) |
| NONE (confirmed OK) | 2 | Doc 04, Doc 05 Sec 7.3 |
| **Total** | **19** (17 issues + 2 confirmations) | |

**By document:**

| Document | CRITICAL | HIGH | MEDIUM | Total issues |
|----------|----------|------|--------|-------------|
| Doc 01 | 1 | 1 | 0 | 2 |
| Doc 02 | 0 | 0 | 1 | 1 |
| Doc 03 | 2 | 2 | 1 | 5 |
| Doc 04 | 0 | 0 | 0 | 0 |
| Doc 05 | 0 | 0 | 1 | 1 |
| Doc 06 | 4 | 2 | 2 | 8 |

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
