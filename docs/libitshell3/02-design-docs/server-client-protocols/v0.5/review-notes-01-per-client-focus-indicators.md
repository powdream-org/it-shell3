# Review Notes: Per-Client Focus Indicators (v0.5)

**Author**: heejoon.kang
**Date**: 2026-03-05
**Status**: Open idea (v1 nice-to-have). No action needed for v1 core.
**Severity**: Enhancement (nice-to-have)
**Inspiration**: zellij independent focus mode

---

## Summary

When multiple clients are attached to the same session, it would be valuable to
show which clients are focused on which tabs and panes. This provides spatial
awareness in collaborative or multi-device usage scenarios (e.g., macOS + iPad
viewing the same session).

This document captures the idea and reference material for future design work.
Nothing here is normative for v1.

---

## 1. Current Protocol Foundation (v0.5)

The v0.5 protocol already has the building blocks for multi-client awareness:

| Existing element | Location | What it provides |
|---|---|---|
| `client_id` (u32) | ServerHello response (doc 02, line 213) | Unique per-connection identifier |
| `client_name` (string) | ClientHello request (doc 02, line 96) | Human-readable name (e.g., "it-shell3-macos") |
| `ClientAttached` (0x0183) | doc 03, Section 4.4 | Notification when a client joins a session |
| `ClientDetached` (0x0184) | doc 03, Section 4.5 | Notification when a client leaves a session |
| `attached_clients` count | In ClientAttached/ClientDetached payloads | Total attached client count |
| Preedit ownership via `client_id` | doc 05, PreeditSync payload | Identifies which client owns active composition |

### What is missing

- **Per-client focus tracking**: The server does not track which pane each client
  is currently viewing. v0.5 uses a shared focus model -- all clients share one
  `active_pane_id` per session (doc 02, line 748), matching tmux behavior.

- **`ClientFocusChanged` notification**: No message exists to broadcast when a
  client changes their focused pane.

- **`ListAttachedClients` query**: No way to query the current set of attached
  clients and their focus state on demand (e.g., on reconnect).

- **Per-client cursor position broadcasting**: No mechanism for showing other
  clients' cursor positions within shared panes ("fake cursors").

### v0.5 design decision

Per-client viewports are currently scoped as a v1 nice-to-have (doc 02, line 922):

> Per-client virtual viewports (where each client sees a viewport into a larger
> terminal) are deferred to v2.

Per-client focus indicators are a natural companion to per-client viewports and
should be designed together as a v1 nice-to-have.

---

## 2. What Would Be Needed (Sketch)

This is a non-normative sketch for future design work.

### 2.1 Per-client focus model

Each client independently tracks which pane they are viewing. The server
maintains a `focused_pane_id` per `client_id`. This is distinct from the
session-level `active_pane_id` which determines where keyboard input is routed.

**Decision needed**: Does per-client focus affect input routing? Two options:

- **Display-only focus**: Each client tracks what they are *looking at*, but
  input always goes to the session's `active_pane_id`. Simpler, but a client
  might be viewing pane B while typing into pane A.
- **Independent input routing**: Each client's input goes to their own focused
  pane. This is zellij's "independent" mode. More complex -- requires per-client
  PTY size negotiation (minimum sizing or per-client viewport).

### 2.2 New protocol messages

| Message | Direction | Payload (sketch) |
|---|---|---|
| `ClientFocusChanged` | S -> C | `{ "client_id": u32, "client_name": string, "pane_id": u32 }` |
| `ListAttachedClients` request | C -> S | `{ "session_id": u32 }` |
| `ListAttachedClients` response | S -> C | `{ "clients": [{ "client_id": u32, "client_name": string, "focused_pane_id": u32 }] }` |

These would fit in the 0x0185+ range (extending the existing 0x0183/0x0184
notification block).

### 2.3 Client-side rendering

Since our architecture uses RenderState (structured cell data) rather than
server-side VT rendering, the client is responsible for computing and rendering
focus indicators from protocol messages. This means:

- Tab bar indicators (colored blocks next to tab names)
- Pane frame indicators (colored user markers on borders)
- Optional: fake cursors within shared panes

The client maintains a local map of `client_id -> color` using a fixed palette.

---

## 3. Zellij Reference (for Future Design Work)

Zellij's implementation provides the most relevant reference for this feature.
Key details captured here for the team to use when designing this v1 nice-to-have.

### 3.1 Two modes

Zellij supports two multi-client modes:

- **Mirrored** (default): All clients see the same view. No focus indicators
  needed -- everyone is looking at the same thing.
- **Independent**: Each client has their own focused tab and pane. Focus
  indicators are shown to convey other clients' positions.

Our session-per-connection architecture (doc 01, Section 5.2) naturally maps to
independent mode, since each client connection is attached to one session and
can independently navigate tabs/panes within it.

### 3.2 Color assignment

Zellij uses a fixed palette of 10 colors mapped to client IDs by index modulo:

```
client_id % 10 -> color_index
```

### 3.3 Server-side computation

The zellij server computes per-client `other_focused_clients` lists and pushes
tailored state to each client. Each client receives only the information about
*other* clients' positions, not their own.

### 3.4 Tab bar rendering

Zellij's tab bar and compact bar are WASM plugins that subscribe to `TabUpdate`
events. Tab entries include a list of `other_focused_clients` with their color
indices. The tab bar renders colored block indicators (e.g., `[block block]`)
next to tab names where other clients are focused.

### 3.5 Pane frame rendering

Pane frame indicators are rendered server-side with graceful text degradation
based on available space:

- Full width: `"MY FOCUS AND: [block] [block]"`
- Medium: `"U: [block]"`
- Narrow: just colored blocks

### 3.6 Key difference from our architecture

Zellij renders everything server-side as VT sequences. Our RenderState model
means the server sends structured data and the client computes the visual
representation. This is actually *simpler* for focus indicators -- the client
receives `ClientFocusChanged` messages and locally decides how to render them,
without the server needing to know about tab bar layout or pane frame geometry.

---

## 4. Relationship to Other v1 Nice-to-Have Features

Per-client focus indicators interact with several other features scoped as v1 nice-to-have:

| v1 Nice-to-Have Feature | Interaction |
|---|---|
| Per-client viewports (doc 02, line 922) | Independent focus requires independent viewport sizing |
| `CELLDATA_ENCODING` capability flag | Binary CellData encoding might need to carry per-client cursor overlay data |
| Selection protocol (doc 04, line 974) | Multi-client selection sync is a related multi-client awareness problem |
| Network transport (SSH tunneling) | Multi-client over network makes focus indicators more valuable |

---

## 5. Owner's Note

This is a nice-to-have feature idea, not a v1 blocker. The ability to indicate
which users (including myself) are focused on which tabs and panes would be a
great UX enhancement. Since our design is already separate-tab (session) based,
independent focus mode is a natural fit. The existing `client_id` / `client_name`
/ `ClientAttached` / `ClientDetached` infrastructure provides a solid foundation
to build on as a v1 nice-to-have.

---
---

# Review Notes: Multi-Client Window Size Negotiation (v0.5)

**Author**: heejoon.kang
**Date**: 2026-03-05
**Status**: Open -- needs team discussion
**Severity**: Design gap (potential denial-of-service vector)
**Related docs**: doc 03 Section 5.1, doc 06 Section 2

---

## Summary

Current protocol (doc 03, Section 5.1) uses "smallest client wins"
(`min(cols) x min(rows)`) for effective session size. This has a critical gap:
paused or unresponsive clients' dimensions still count toward the calculation.

This document captures the gap and questions for team discussion.

---

## 1. Problem Statement

Scenario:

- Client A (healthy): 100x30
- Client B (frozen/paused): 50x20 -- stale dimensions
- Effective size: 50x20 -- all healthy clients suffer

This is a potential denial-of-service vector: a single hung client with a small
window permanently shrinks the PTY for all healthy clients. The problem is
compounded in network-attached sessions where a remote client may become
unresponsive due to network conditions while its last-reported dimensions remain
in the server's resize calculation.

---

## 2. Questions to Resolve

1. **Should paused clients' dimensions be excluded from the `min()` calculation
   after a grace period?** Currently, PausePane (doc 06, Section 2) suspends
   rendering output but does not affect the resize algorithm. A paused client's
   stale dimensions continue to constrain all healthy clients.

2. **If excluded, what happens when the paused client resumes?** Does another
   resize cascade occur? This could cause visible flickering for healthy clients
   if a paused client with different dimensions repeatedly pauses and resumes.

3. **Should there be a configurable "stale client resize timeout"?** For
   example: 30s paused with no resize update -> exclude from resize calculation.
   This creates a two-tier system where "recently paused" clients still
   participate in sizing but "long-paused" clients do not.

4. **Should this be an explicit server policy or a capability-negotiated
   behavior?** Server-side policy is simpler (all clients get the same behavior).
   Capability negotiation adds flexibility but increases protocol complexity for
   a niche scenario.

---

## 3. Pre-Discussion Research Required

Before the team discusses solutions for multi-client window size negotiation,
the following reference codebase research MUST be completed. Assign these tasks
to **tmux-expert** and **zellij-expert** agents respectively.

### 3.1 tmux research (tmux-expert)

Research how tmux computes session/window size when multiple clients are
attached. Specifically:

1. **`window-size` option**: tmux supports multiple size policies via the
   `window-size` server option (e.g., `smallest`, `largest`, `latest`,
   `manual`). Document each policy's semantics and which is the default.
   Look for `size_latest`, `size_smallest`, and related logic in the source.

2. **`aggressive-resize` option**: Document what this per-window option does,
   how it interacts with `window-size`, and whether it changes the
   per-session vs per-window sizing granularity.

3. **Unresponsive client exclusion**: Investigate whether tmux excludes
   unresponsive or slow clients' dimensions from the size calculation. Look
   for any staleness or timeout logic in the resize path. Does a hung client
   permanently constrain the window size for healthy clients?

4. **Resize event flow**: Trace the path from a client reporting a new
   terminal size to the PTY `TIOCSWINSZ` ioctl. How does the server
   aggregate multiple clients' sizes and decide the effective dimensions?

Source location: `~/dev/git/references/tmux/`

### 3.2 zellij research (zellij-expert)

Research how zellij computes pane/tab dimensions when multiple clients are
attached. Specifically:

1. **Multi-client sizing strategy**: Does zellij use "smallest wins"
   (`min(cols) x min(rows)`), per-client viewports, or something else?
   Document the algorithm used in both mirrored and independent modes.

2. **Unresponsive client handling in resize**: Investigate whether zellij
   excludes unresponsive clients' window sizes from the dimension
   calculation. Does a frozen client shrink the terminal for all other
   clients?

3. **Resize propagation path**: Trace how a client's terminal size change
   propagates through the server to affect pane layout and PTY size. Are
   there any debounce or coalescing mechanisms?

4. **Per-client viewport sizing**: If zellij supports independent pane focus
   per client, does each client get its own viewport dimensions, or does the
   PTY still use a single shared size?

Source location: `~/dev/git/references/zellij/`

### 3.3 Deliverables

Each researcher should produce a short findings report (plain text or
markdown) covering the above points with specific source file references
(file paths and function/struct names). These findings will be used as input
to the team discussion on Questions 1-4 in Section 2.

---

## 4. Interaction with Other Issues

This issue directly interacts with Issue 3 (Client Health Model) below. If the
protocol gains intermediate health states (e.g., `degraded`, `stale`), the
resize algorithm can use health state as input rather than inventing its own
staleness tracking.

---
---

# Review Notes: Client Health Model (v0.5)

**Author**: heejoon.kang
**Date**: 2026-03-05
**Status**: Open -- needs team discussion. Interacts with Issue 2 (resize policy for unhealthy clients).
**Severity**: Design gap (protocol robustness)
**Related docs**: doc 01 Section 5.4, doc 02 Section 11.2, doc 06 Sections 2 and 7

---

## Summary

The protocol currently has a binary model: clients are either alive (connected,
heartbeat passing) or dead (heartbeat timeout at 90s -> Disconnect). There are
no intermediate health states. This document captures the identified gaps and
possible approaches for team discussion.

---

## 1. Gaps Identified

### 1.1 PausePane has no timeout

A client that never calls `ContinuePane` remains paused indefinitely. Server
buffers up to 1 MB per pane (doc 06, Section 2). No automatic eviction or
timeout mechanism exists.

### 1.2 No health states

Connection lifecycle states (`HANDSHAKING`, `READY`, `OPERATING`,
`DISCONNECTING`) are connection states, not health states. There is no concept
of "degraded" or "unresponsive-but-connected."

### 1.3 No stale client eviction

Beyond the 90s heartbeat timeout (doc 02, Section 11.2), there is no mechanism
to evict a chronically paused client. A client whose TCP stack ACKs packets (so
heartbeat passes) but whose application is frozen is invisible to the protocol.

### 1.4 No health reporting to other clients

Other attached clients have no way to know that a peer client is
unhealthy/paused. `ClientAttached` (0x0183) / `ClientDetached` (0x0184) only
cover join/leave, not health transitions.

### 1.5 No application-level health check

Heartbeat only proves the TCP connection is alive. It does not prove the client
application is actually processing messages. Consider whether HeartbeatAck
should require application-level processing (not just TCP-level ACK).

---

## 2. Possible Approaches (Non-Normative)

These are starting points for team discussion, not recommendations.

### 2.1 PausePane timeout

Add a configurable timeout for PausePane (e.g., 30s paused -> auto-continue or
disconnect). This is the simplest fix and addresses the most immediate resource
leak.

### 2.2 Client health states

Add intermediate health states to the client model:

```
healthy -> degraded (high queue, tier downgraded)
        -> paused (explicit PausePane)
        -> stale (paused too long)
        -> evicted (server-initiated disconnect)
```

Health states would be orthogonal to connection lifecycle states. A client can
be in `OPERATING` connection state but `degraded` health state.

### 2.3 ClientHealthChanged notification

Add a new notification message so other clients can observe peer health
transitions:

```
ClientHealthChanged (S -> C):
  { "client_id": u32, "client_name": string, "health": string, "reason": string }
```

This would fit in the 0x0185+ notification range alongside `ClientAttached`
and `ClientDetached`.

### 2.4 Application-level heartbeat

Require the client to echo a nonce after processing its message queue, proving
the application layer is alive (not just the TCP stack). This is more invasive
than the other approaches and may add latency to the heartbeat path.

---

## 3. Pre-Discussion Research Required

Before the team discusses solutions for the client health model, the following
reference codebase research MUST be completed. Assign these tasks to
**tmux-expert** and **zellij-expert** agents respectively.

### 3.1 tmux research (tmux-expert)

Research how tmux detects and handles unresponsive or slow clients. Specifically:

1. **Client health detection**: Investigate how tmux determines that a client
   is unresponsive or slow. Look for `server_client_check` or similar
   periodic check functions. What metrics does the server track per client
   (e.g., output buffer size, last activity timestamp)?

2. **Backoff and eviction**: When tmux identifies a slow client, what actions
   does it take? Document the escalation path -- does it backoff output,
   pause updates, or forcibly disconnect the client? Look for `MSG_EXITING`
   and related disconnect logic.

3. **Flow control for slow clients**: Investigate tmux's output buffering
   strategy per client. How large can the output buffer grow before tmux
   takes action? Is there a configurable timeout or buffer limit that
   triggers disconnect?

4. **Heartbeat / keepalive mechanism**: Does tmux use application-level
   heartbeats or rely solely on OS-level TCP keepalive? If application-level,
   what is the check interval and timeout? How does it distinguish between
   "TCP alive but application frozen" vs "connection dead"?

5. **Impact on other clients**: When one client is slow or unresponsive, does
   tmux isolate the impact or do all clients suffer? Specifically, does a
   slow client cause backpressure that blocks PTY reads or other clients'
   output?

Source location: `~/dev/git/references/tmux/`

### 3.2 zellij research (zellij-expert)

Research how zellij detects and handles unresponsive clients and manages output
flow control. Specifically:

1. **Client health detection**: Does zellij have any mechanism to detect that
   a client is unresponsive or processing output too slowly? Look for
   per-client health checks, timeout logic, or output queue monitoring.

2. **Unresponsive client actions**: What actions does zellij take when a
   client is identified as unresponsive? Does it disconnect, pause output,
   or degrade service? Is there an escalation path (warn -> pause -> evict)?

3. **Output flow control / backpressure**: Investigate zellij's per-client
   output buffering strategy. How does the server handle the case where one
   client consumes output slowly while others are fast? Is there per-client
   buffering with independent backpressure, or does a slow client cause
   global slowdown?

4. **Thread architecture and isolation**: Since zellij uses a multi-threaded
   architecture, does its threading model naturally isolate slow clients from
   affecting other clients or PTY reads? Document how per-client output is
   dispatched (dedicated thread per client, shared thread pool, async I/O,
   etc.).

5. **Plugin client vs terminal client**: If zellij distinguishes between
   different client types (WASM plugins vs terminal clients), does it apply
   different health/flow-control policies to each?

Source location: `~/dev/git/references/zellij/`

### 3.3 Deliverables

Each researcher should produce a short findings report (plain text or
markdown) covering the above points with specific source file references
(file paths and function/struct names). These findings will be used as input
to the team discussion on the approaches outlined in Section 2 and to inform
the interaction with Issue 2 (resize policy for unhealthy clients).

---

## 4. Interaction with Other Issues

- **Issue 2 (Multi-Client Window Size Negotiation)**: If client health states
  are adopted, the resize algorithm (doc 03, Section 5.1) can exclude clients
  in `stale` or `paused` health states from the `min()` calculation, rather
  than inventing separate staleness tracking.

- **Issue 1 (Per-Client Focus Indicators)**: Health state information could be
  surfaced alongside focus indicators in the client UI, giving users visibility
  into peer client status.
