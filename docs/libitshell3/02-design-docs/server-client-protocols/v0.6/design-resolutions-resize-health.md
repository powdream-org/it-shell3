# Design Resolutions: Multi-Client Resize Policy and Client Health Model

**Version**: v0.6
**Date**: 2026-03-05
**Status**: Resolved (full consensus)
**Participants**: protocol-architect, systems-engineer, cjk-specialist
**Discussion rounds**: 4 (initial proposals, counterpoints, convergence, final confirmation)
**Source issues**: Review Notes v0.5 -- Issue 2 (Multi-Client Window Size Negotiation), Issue 3 (Client Health Model)

---

## Table of Contents

1. [Issue 2a: Multi-Client Resize Policy](#issue-2a-multi-client-resize-policy)
   - [Resolution 1: Default resize policy is `latest`](#resolution-1-default-resize-policy-is-latest)
   - [Resolution 2: `latest_client_id` tracking per session](#resolution-2-latest_client_id-tracking-per-session)
   - [Resolution 3: Only `stale` clients excluded from resize](#resolution-3-only-stale-clients-excluded-from-resize)
   - [Resolution 4: Resize policy is server configuration](#resolution-4-resize-policy-is-server-configuration)
   - [Resolution 5: 250ms resize debounce per pane](#resolution-5-250ms-resize-debounce-per-pane)
   - [Resolution 6: 5-second re-inclusion hysteresis](#resolution-6-5-second-re-inclusion-hysteresis)
2. [Issue 2b: Client Health Model](#issue-2b-client-health-model)
   - [Resolution 7: Two protocol-visible health states](#resolution-7-two-protocol-visible-health-states)
   - [Resolution 8: 5s / 60s / 300s PausePane timeline](#resolution-8-5s--60s--300s-pausepane-timeline)
   - [Resolution 9: Stale timeout resets on application-level messages only](#resolution-9-stale-timeout-resets-on-application-level-messages-only)
   - [Resolution 10: Output queue stagnation as stale trigger](#resolution-10-output-queue-stagnation-as-stale-trigger)
   - [Resolution 11: Heartbeat remains orthogonal to health states](#resolution-11-heartbeat-remains-orthogonal-to-health-states)
   - [Resolution 12: ClientHealthChanged notification at 0x0185](#resolution-12-clienthealthchanged-notification-at-0x0185)
   - [Resolution 13: Buffer limit 512KB per (client, pane)](#resolution-13-buffer-limit-512kb-per-client-pane)
   - [Resolution 14: Discard-and-resync pattern](#resolution-14-discard-and-resync-pattern)
   - [Resolution 15: Resync procedure on stale recovery](#resolution-15-resync-procedure-on-stale-recovery)
   - [Resolution 16: Preedit bypass absolute across all health states](#resolution-16-preedit-bypass-absolute-across-all-health-states)
3. [Addenda](#addenda)
   - [Addendum A: Transport-aware stale timeout](#addendum-a-transport-aware-stale-timeout)
   - [Addendum B: Commit active preedit on client eviction](#addendum-b-commit-active-preedit-on-client-eviction)
   - [Addendum C: Suppress Idle coalescing during resize debounce](#addendum-c-suppress-idle-coalescing-during-resize-debounce)
4. [CJK-Specific Validations](#cjk-specific-validations)
5. [Wire Protocol Changes Summary](#wire-protocol-changes-summary)
6. [Prior Art References](#prior-art-references)
7. [Research Inputs](#research-inputs)

---

## Issue 2a: Multi-Client Resize Policy

### Resolution 1: Default resize policy is `latest`

**Consensus (3/3).** The server defaults to `latest` policy: PTY dimensions are set to the most recently active client's reported size. `smallest` (min(cols) x min(rows) across all eligible clients) is available as an opt-in server configuration.

**Rationale**: tmux switched from `smallest` to `latest` as default in version 3.1. For libitshell3's primary use case (single user, multiple devices -- macOS desktop + iPad), `latest` prevents an idle device's dimensions from constraining the active device. zellij still uses `smallest` and suffers from the exact stale-dimensions vulnerability identified in the review notes.

**v1 scope**: Two policies only (`latest` and `smallest`). `largest` and `manual` are deferred to v2 -- `largest` is niche (deliberately shows clipped content on smaller clients), `manual` requires an admin resize command that does not exist in our protocol.

### Resolution 2: `latest_client_id` tracking per session

**Consensus (3/3).** The server tracks `latest_client_id` per session, updated on:

- KeyEvent received from a client
- WindowResize received from a client
- NOT on HeartbeatAck (passive liveness does not indicate active use)

When the latest client detaches or becomes stale, the server falls back to the next most-recently-active healthy client. If no client has any recorded activity, fall back to the client with the largest terminal dimensions.

**Implementation sketch** (non-normative):

```
struct Session {
    latest_client_id: u32,
    latest_activity_time: u64,  // monotonic timestamp
}

on KeyEvent or WindowResize from client C:
    if session.latest_client_id != C.id:
        session.latest_client_id = C.id
        session.latest_activity_time = now()
        if resize_policy == .latest:
            recompute_effective_size(session)

on detach of latest client:
    session.latest_client_id = session.attached_clients
        .filter(c => c.health == .healthy)
        .max_by(c => c.last_activity_time)
        .unwrap_or(client_with_largest_dimensions)
```

### Resolution 3: Only `stale` clients excluded from resize

**Consensus (3/3).** Clients in the `stale` health state (see Resolution 7) are excluded from the resize calculation under both `latest` and `smallest` policies. All other clients participate, including those experiencing transient backpressure (server-internal smooth degradation).

**Rationale**: Excluding transiently slow clients (e.g., output queue at 51%) would cause resize flapping that is more disruptive than the backpressure itself. A brief burst of output triggers exclusion, PTY grows, burst ends, client recovers, PTY shrinks -- two unnecessary resize cascades from a transient condition.

Policy-specific behavior when stale clients are excluded:

| Policy | Behavior |
|--------|----------|
| `latest` | If the latest client becomes stale, use the next most-recently-active healthy client's dimensions |
| `smallest` | Remove stale clients from the min() calculation. If no healthy clients remain, retain last known dimensions |

### Resolution 4: Resize policy is server configuration

**Consensus (3/3).** Resize policy is a session-level server concern. It affects all clients viewing a session and requires global visibility of all clients' health and dimensions. The server reports the active policy in `AttachSessionResponse` (informational, not negotiated).

New field in AttachSessionResponse payload:

```json
{
  "resize_policy": "latest"
}
```

**Rationale for not capability-negotiating**: Capability negotiation would create inconsistent expectations (Client A thinks `latest`, Client B thinks `smallest`). The server is the only entity with the global view needed to make this decision.

### Resolution 5: 250ms resize debounce per pane

**Consensus (3/3).** `ioctl(fd, TIOCSWINSZ)` is debounced at 250ms per pane, matching tmux's battle-tested approach. Prevents SIGWINCH storms during rapid resize drags.

Behavior:

1. When a resize is computed for a pane, arm a 250ms timer.
2. If another resize arrives within 250ms, reset the timer and update target dimensions.
3. Only fire `ioctl(TIOCSWINSZ)` when the timer expires.
4. **Exception**: The FIRST resize after session creation or client attach fires immediately (no debounce).
5. During the debounce window, suppress FrameUpdate generation for old dimensions (only preedit bypass frames are sent).
6. During the debounce window and for 500ms after, suppress Idle coalescing tier transition (see Addendum C).

### Resolution 6: 5-second re-inclusion hysteresis

**Consensus (3/3).** When a stale client recovers to healthy, it must remain healthy for 5 seconds before being re-included in the resize calculation. This prevents resize churn from rapid stale/healthy oscillations.

During the 5-second window, the client receives frames normally but does not affect PTY dimensions. After 5 seconds of sustained healthy state, the server re-includes the client in the resize calculation and triggers a resize cascade if the effective size changes.

**Rationale for 5s (not 2s)**: A client recovering from stale experiences a burst of resync traffic (LayoutChanged + dirty=full FrameUpdate per pane + PreeditSync). 5 seconds ensures the resync settles before the client's dimensions affect the PTY.

---

## Issue 2b: Client Health Model

### Resolution 7: Two protocol-visible health states

**Consensus (3/3).** The protocol defines two health states orthogonal to connection lifecycle:

| State | Definition | Resize participation | Frame delivery |
|-------|-----------|---------------------|----------------|
| `healthy` | Normal operation | Yes | Full (per coalescing tier) |
| `stale` | Paused too long or output queue stagnant | No (excluded after 5s grace) | None (except preedit bypass) |

**`paused`** (PausePane active) is an orthogonal flow-control state, not a health state. A paused client remains `healthy` until the stale timeout fires.

**Smooth degradation** (auto-tier-downgrade at 50% queue, force Bulk at 75%, queue compaction) is **server-internal** implementation behavior, NOT a protocol-visible state. It is documented as implementation guidance in doc 06 Section 2 and reported via RendererHealth (0x0803) for debugging. It does not trigger ClientHealthChanged and does not affect resize.

**Rationale for not formalizing `degraded` as a protocol state**:

- No protocol message is associated with it (ClientHealthChanged for every tier downgrade would be noisy and not actionable).
- No resize-exclusion behavior (degraded clients are still receiving frames, their dimensions are still valid).
- No client recovery action (the server handles it automatically).
- The smooth degradation thresholds (50%? 60%? 75%?) would become normative, reducing implementation flexibility.

### Resolution 8: 5s / 60s / 300s PausePane timeline

**Consensus (3/3).** When a client enters PausePane and does not send ContinuePane:

```
T=0s:    PausePane. Client is still `healthy`. Still participates in resize.

T=5s:    Resize exclusion. Server recalculates effective size without this client.
         No protocol message. Server-internal decision.
         Handles the common case of brief iOS backgrounding without waiting
         for the full stale timeout.

T=60s:   `stale` health state transition (local transport).
(local)  Server sends ClientHealthChanged (0x0185) to all peer clients.

T=120s:  `stale` health state transition (SSH tunnel transport).
(SSH)    Same behavior as T=60s. Longer timeout accounts for higher latency
         and more variable behavior over SSH tunnels.

T=300s:  Eviction. Server sends Disconnect(STALE_CLIENT) and tears down
         the connection. Transport-independent.
```

All timeouts are configurable via FlowControlConfig (doc 06 Section 2.3). Default values:

| Parameter | Default (local) | Default (SSH) | Description |
|-----------|-----------------|---------------|-------------|
| `resize_exclusion_timeout_ms` | 5000 | 5000 | Grace period before resize exclusion |
| `stale_timeout_ms` | 60000 | 120000 | PausePane duration before `stale` transition |
| `eviction_timeout_ms` | 300000 | 300000 | Total duration before forced disconnect |

The server selects transport-aware defaults based on `ClientDisplayInfo.transport_type`. The client can override via FlowControlConfig.

The 300s eviction matches tmux's `CONTROL_MAXIMUM_AGE` (5 minutes).

**The 5s grace period and the stale timeout serve different purposes:**

- 5s grace: "Should this client affect PTY dimensions right now?" (resize concern)
- 60s/120s stale: "Is this client meaningfully participating in the session?" (health concern, triggers peer notification)

### Resolution 9: Stale timeout resets on application-level messages only

**Consensus (3/3).** The stale timeout clock resets ONLY when the client sends a message that proves application-level processing:

- ContinuePane
- KeyEvent
- WindowResize
- ClientDisplayInfo
- Any request message (CreateSession, SplitPane, etc.)

**HeartbeatAck does NOT reset the stale timeout.**

**Rationale**: On iOS, the OS can suspend the application while keeping TCP sockets alive. The TCP stack continues to respond to heartbeats (ACKs) even though the application event loop is frozen. If HeartbeatAck reset the stale timeout, a backgrounded iPad client would never be marked stale, and its stale dimensions would permanently constrain healthy clients -- exactly the DoS vector Issue 2a describes.

The eviction timeout (300s) MAY reset on HeartbeatAck as a safety net against false disconnects (the connection is alive, just slow).

### Resolution 10: Output queue stagnation as stale trigger

**Consensus (3/3).** In addition to PausePane duration, the server uses output queue stagnation as a stale trigger:

```
If client's output queue utilization > 90% for stale_timeout_ms (60s/120s)
   AND client has not sent any application-level message during that period:
   -> transition to `stale`
```

This catches the "TCP alive but app frozen" scenario without wire format changes. The server already tracks per-client output queue metrics (OutputQueueStatus, doc 06 Section 2.5).

### Resolution 11: Heartbeat remains orthogonal to health states

**Consensus (3/3).** Heartbeat (0x0003-0x0005) is a connection liveness mechanism. 90s timeout -> Disconnect. This is unchanged.

Health states are an application responsiveness mechanism, triggered by output queue metrics and PausePane duration. These are independent systems:

| Combination | Meaning |
|-------------|---------|
| Heartbeat-healthy + output-stale | `stale` (app frozen, TCP alive) |
| Heartbeat-missed + output-healthy | Connection problem (will resolve or disconnect at 90s) |

**`echo_nonce`** (application-level heartbeat verification) is deferred to v2 in the `0x0900` reserved range. For v1, the combination of `latest` default policy + output queue stagnation detection + PausePane escalation covers practical scenarios.

The idle-PTY blind spot (no output = no queue growth = no detection of frozen client) is mitigated by `latest` policy: an idle client's dimensions are irrelevant when another client is active. For `smallest` policy edge cases, `echo_nonce` can be added in v2 as a `HEARTBEAT_NONCE` capability.

**Server-side heartbeat RTT** measurement (time between sending Heartbeat and receiving HeartbeatAck) MAY be used as an implementation-level heuristic (e.g., RTT >60s for 2 consecutive heartbeats suggests event loop stall). This is non-normative implementation guidance, not a protocol state trigger.

### Resolution 12: ClientHealthChanged notification at 0x0185

**Consensus (3/3).** New notification message:

**Message type**: `0x0185` ClientHealthChanged (S -> C)

**Payload** (JSON):

```json
{
  "session_id": 1,
  "client_id": 5,
  "client_name": "iPad-Pro",
  "health": "stale",
  "previous_health": "healthy",
  "reason": "pause_timeout",
  "excluded_from_resize": true
}
```

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | number (u32) | Session the affected client is attached to |
| `client_id` | number (u32) | The affected client |
| `client_name` | string | Human-readable client name (from ClientHello) |
| `health` | string | New health state: `"healthy"` or `"stale"` |
| `previous_health` | string | Previous health state |
| `reason` | string | Reason for transition (see below) |
| `excluded_from_resize` | boolean | Whether the client is now excluded from resize calculation |

**`reason` values:**

| Value | Description |
|-------|-------------|
| `"pause_timeout"` | PausePane duration exceeded stale timeout |
| `"queue_stagnation"` | Output queue >90% for stale timeout with no app-level messages |
| `"recovered"` | Client sent ContinuePane or resumed processing |

**Direction**: S -> C, sent to all peer clients attached to the same session. NOT sent to the affected client itself (it already knows -- it received PausePane or is processing its recovery).

This extends the existing notification block: `ClientAttached` (0x0183), `ClientDetached` (0x0184), `ClientHealthChanged` (0x0185). Always-sent (no subscription required), matching the convention for 0x0180-0x018x notifications.

### Resolution 13: Buffer limit 512KB per (client, pane)

**Consensus (3/3).** The per-(client, pane) output buffer limit is reduced from 1MB to 512KB.

**Rationale**:

- A worst-case full CJK FrameUpdate (120x40 pane, all wide characters): ~116KB
  - 4800 cells at ~24 bytes/cell (CellData with wide char, fg/bg colors, attributes)
  - Plus ~1KB JSON metadata, ~5 bytes DirtyRows bitmap
- 512KB buffers ~4 full CJK frames or ~12 partial-dirty frames
- With discard-and-resync (Resolution 14), the server only needs enough buffer for 1 full frame plus headroom for in-flight frames during resync
- Total memory: 5 clients x 10 panes x 512KB = 25MB (reasonable)
- Configurable via FlowControlConfig for low-memory clients

Doc 06 Section 2 "Server Output Queue Management" should be updated from 1MB to 512KB.

### Resolution 14: Discard-and-resync pattern

**Consensus (3/3).** When a client's buffer is exceeded or the client recovers from stale:

1. Discard all buffered frames for that client.
2. Send a single dirty=full FrameUpdate reflecting current terminal state.
3. Resume incremental updates.

**Rationale**: Inspired by tmux's regular TTY client model (discard-and-redraw, via `TTY_BLOCK`). Our structured frame model makes this strictly better -- the server always has authoritative terminal state, and a full FrameUpdate is bounded at `cols * rows * sizeof(CellData)`. zellij's maintainers explicitly acknowledge "redraw-on-backpressure" as the ideal approach but have not implemented it.

### Resolution 15: Resync procedure on stale recovery

**Consensus (3/3).** When a stale client recovers (sends ContinuePane), the server sends the following sequence:

```
1. LayoutChanged (if layout changed while client was stale)
   Server tracks a `layout_changed_while_stale` flag per client.

2. dirty=full FrameUpdate per pane, including ALL JSON metadata:
   - Grid CellData (all rows)
   - Current dimensions (cols, rows, pixel_width, pixel_height)
   - Cursor position and style
   - Terminal modes (mouse, focus, bracketed paste)
   - Preedit state (if active composition exists)
   - Color palette (if changed)

3. PreeditSync per pane (for CJK_CAP_PREEDIT clients with active composition)
   Provides full composition metadata snapshot.
```

The client replaces its entire state from this resync sequence. PreeditSync is NOT requested by the client -- the server proactively sends it as part of the resync.

### Resolution 16: Preedit bypass absolute across all health states

**Consensus (3/3, reaffirming settled decision).** Preedit-only FrameUpdates (`num_dirty_rows=0` + preedit JSON metadata, ~100 bytes) MUST be delivered to clients in ANY health state, including `stale`. The only exception is connection death.

A user composing Korean (e.g., "한") MUST see each composition step (ㅎ -> 하 -> 한) even if the terminal grid is frozen due to backpressure. The ~100 bytes per preedit frame is negligible overhead.

During stale recovery, the client already has current preedit state (from bypass frames received while stale). The resync FrameUpdate's preedit coordinates reflect post-resize grid geometry, correcting any positional staleness from the stale period.

---

## Addenda

### Addendum A: Transport-aware stale timeout

**Refines Resolution 8.**

The stale timeout is transport-aware, using `ClientDisplayInfo.transport_type` (already in the protocol):

| Transport | Stale timeout | Rationale |
|-----------|--------------|-----------|
| `local` (Unix socket) | 60s | OS detects dead sockets fast; 60s is sufficient |
| `ssh_tunnel` | 120s | Higher latency, more variable behavior; longer patience needed |
| `unknown` | 60s | Conservative default |

The 5s resize-exclusion grace period and 300s eviction timeout remain transport-independent.

The server selects transport-aware defaults. The client can override via FlowControlConfig.

### Addendum B: Commit active preedit on client eviction

**Refines Resolution 15.** Adds a normative requirement for client eviction.

When the server evicts a stale client (Disconnect at T=300s), any active preedit composition owned by that client MUST be committed (flushed to the terminal grid) before the client connection is torn down. This prevents orphaned composition state -- if the user was mid-composition when the client became stale, the partial composition is committed to the terminal so it is not lost.

The server sends PreeditEnd with `reason: "client_evicted"` to remaining peer clients before the Disconnect.

### Addendum C: Suppress Idle coalescing during resize debounce

**Refines Resolution 5.** Adds a coalescing tier interaction.

During the 250ms resize debounce window and for 500ms after the debounce fires (`ioctl(TIOCSWINSZ)`), the server MUST NOT transition the pane's coalescing tier to Idle, even if no new PTY output arrives.

**Rationale**: The PTY application is processing SIGWINCH and may briefly pause output; this is not true idleness. Transitioning to Idle would suppress frame delivery, causing the client to miss the post-resize FrameUpdate.

After the 500ms grace expires, normal coalescing tier transitions resume.

---

## CJK-Specific Validations

The following CJK concerns were raised and resolved during discussion:

### 1. Preedit during `latest` policy resize

**No race condition.** Doc 05 Section 7.3 already specifies that FrameUpdate is sent before PreeditUpdate when both are triggered by the same resize event. The FrameUpdate carries both new grid dimensions and new preedit coordinates atomically. The `latest` policy does not change this -- it just makes resize events triggered by client switching (not just window resize). The same Section 7.3 behavior applies regardless of why the resize happened.

### 2. CellData at column boundaries during resize

**Handled by the terminal emulator (libghostty-vt), not the protocol.** Double-width CJK characters at the right edge produce a padding cell (display_width=0) and wrap to the next line. Standard terminal behavior, correctly encoded in CellData. More frequent resizes with `latest` policy means more frequent reflows at CJK boundaries -- a UX consideration, not a protocol correctness issue. The 250ms resize debounce mitigates excessive reflows.

### 3. IME state preservation across resize

**Confirmed transparent.** The IME engine operates on a per-pane jamo buffer independent of terminal dimensions. Composition continues uninterrupted across resize; only the preedit display position changes. Explicitly stated in doc 05 Section 7.3: "The preedit text itself is not affected by resize -- only its display position changes."

### 4. Resize triggers dirty=full

Every resize invalidates all per-client dirty bitmaps for the affected pane (O(clients * rows)). This is expensive and is a key reason `latest` policy (fewer resize events) is superior to `smallest` for multi-client scenarios.

### 5. Preedit state after resize exclusion recovery

PreeditSync is NOT needed for recovery. The stale client has been receiving preedit-only FrameUpdates (preedit bypass) throughout its stale period. On ContinuePane resync, the dirty=full FrameUpdate includes post-resize preedit coordinates, correcting any positional staleness atomically.

---

## Wire Protocol Changes Summary

### New message type

| Code | Name | Direction | Doc |
|------|------|-----------|-----|
| `0x0185` | ClientHealthChanged | S -> C | Doc 03 |

### Modified messages

| Message | Change | Doc |
|---------|--------|-----|
| AttachSessionResponse | Add `resize_policy` field | Doc 03 |
| FlowControlConfig | Add `resize_exclusion_timeout_ms`, `stale_timeout_ms`, `eviction_timeout_ms` fields | Doc 06 |

### Doc changes needed

| Doc | Section | Change |
|-----|---------|--------|
| Doc 01 | Protocol overview | Add resize policy description, health state model overview |
| Doc 02 | Handshake | No changes (echo_nonce deferred to v2) |
| Doc 03 | Section 4 | Add ClientHealthChanged (0x0185) notification |
| Doc 03 | Section 5.1 | Rewrite resize algorithm for `latest`/`smallest` policies with stale exclusion, 5s grace period, 5s re-inclusion hysteresis |
| Doc 03 | AttachSessionResponse | Add `resize_policy` field |
| Doc 04 | -- | No changes |
| Doc 05 | -- | No changes (Section 7.3 already handles resize+preedit) |
| Doc 06 | Section 2 | Add PausePane timeout (5s/60s/300s timeline), update buffer limit to 512KB, add stale trigger from queue stagnation, add resync procedure, add preedit flush on eviction |
| Doc 06 | Section 5 | Note Idle suppression during resize debounce + 500ms grace |
| Doc 06 | Section 7 | Add note about heartbeat orthogonality with health states; reserve 0x0900 for v2 echo_nonce |

### Deferred to v2

| Item | Reserved range | Rationale |
|------|---------------|-----------|
| `echo_nonce` (HEARTBEAT_NONCE capability) | 0x0900-0x09FF | Idle-PTY blind spot mitigated by `latest` policy for v1 |
| `largest` resize policy | N/A (server config) | Niche use case |
| `manual` resize policy | N/A (server config) | Requires admin command not in protocol |

---

## Prior Art References

| Decision | tmux precedent | zellij precedent |
|----------|---------------|------------------|
| `latest` as default | `WINDOW_SIZE_LATEST` (default since 3.1) | N/A (uses `smallest` only) |
| Stale client exclusion | `CLIENT_NOSIZEFLAGS` (dead, suspended, exiting) | Not implemented (acknowledged gap) |
| Per-pane pause/resume | `pause-after` mode (control clients) | N/A |
| Discard-and-resync | `TTY_BLOCK` (regular clients) | FIXME comment acknowledges need |
| 250ms resize debounce | `tv = { .tv_usec = 250000 }` | `ResizeCache` (batch per event loop) |
| 300s eviction timeout | `CONTROL_MAXIMUM_AGE` (300000ms) | 5000-msg bounded channel (different mechanism, similar intent) |
| Watcher/observer pattern | N/A | Watcher clients excluded from sizing (inspired health-based exclusion) |

---

## Research Inputs

The following research reports were produced by tmux-expert and zellij-expert agents and served as evidence for the discussion:

- `research-tmux-resize-health.md` -- tmux multi-client resize and client health model analysis
- `research-zellij-resize-health.md` -- zellij multi-client resize and client health detection analysis
- Review Notes v0.5 (`review-notes-01-per-client-focus-indicators.md`, Issues 2 and 3) -- original problem statements
