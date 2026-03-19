# 00022. Server-Owned Scrollback (No Client Cache)

- Date: 2026-03-18
- Status: Accepted

## Context

Terminal sessions accumulate scrollback history — lines that have scrolled above
the visible viewport. This history needs to be accessible for user scrollback
navigation and in-buffer search. The question is where this data lives: on the
server, on each client, or both.

A client-side scrollback cache would allow instant local scroll without a
round-trip, but creates synchronization problems: multiple attached clients
would each hold their own copy, requiring the server to broadcast every new line
to all clients for cache maintenance. Cache invalidation on reconnect, session
resume, and multi-client attach all add complexity. The client binary size and
memory footprint also grow with scrollback history.

## Decision

Scrollback history is owned and stored exclusively by the server. Clients hold
no local scrollback cache.

All scrollback access is request/response through the server: the client sends a
ScrollRequest (0x0301) and the server responds with a FrameUpdate I-frame
showing the scrolled viewport. Scroll-response I-frames are written to the
shared per-pane ring buffer, so when one client scrolls, all attached clients
receive the scrolled viewport — consistent with the globally singleton session
model.

The server broadcasts ScrollPosition (0x0302) to all clients after scroll
operations, carrying `viewport_top`, `total_lines`, and `viewport_rows` so
clients can render an accurate scrollbar indicator without maintaining the
history themselves.

In-buffer search (SearchRequest 0x0303 / SearchResult 0x0304 / SearchCancel
0x0305) also runs entirely server-side and follows the same request/response
pattern.

## Consequences

- Clients are thin: no scrollback buffer allocation, no cache invalidation
  logic, no reconnect sync problem.
- All attached clients always see a consistent scroll position — one client's
  scroll affects all others, which matches the singleton session model.
- Scrollback navigation requires a round-trip to the server; on a local Unix
  socket this latency is negligible, but it is a structural constraint for
  future remote (TLS) connections.
- Session resume and multi-client attach are straightforward: clients simply
  request the current viewport; no history transfer is needed.
- The server's scrollback buffer is the single source of truth, simplifying
  search, selection, and future history-export features.
