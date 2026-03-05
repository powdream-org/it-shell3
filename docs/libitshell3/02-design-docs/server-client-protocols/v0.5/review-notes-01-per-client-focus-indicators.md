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
