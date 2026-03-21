# 00042. Per-Client Viewports Declined — Breaks Shared Ring Buffer Optimization

- Date: 2026-03-21
- Status: Accepted

## Context

When multiple clients are attached to a session and the effective pane size is
larger than a client's own window (e.g., under `latest` resize policy where the
largest client drives dimensions), the client cannot display all terminal rows.
Section 8.9 (server-client-protocols Doc 02, v1.0-r12) of the handshake spec
notes that such clients MUST clip to their own viewport using a top-left origin,
and mentions that per-client viewports — the ability to scroll or pan within the
clipped area to access off-screen rows — were considered and deferred.

The practical question was: could a client independently scroll its view of a
pane that is physically larger than its window, receiving rows outside its
clipped origin? This would require the server to track each client's viewport
position and deliver frame data scoped to that position.

The architecture, however, is built on a shared per-pane ring buffer (ADR
00009). The server serializes each frame exactly once into a per-pane ring. All
connected clients share that single encoded stream; per-client state is limited
to a 12-byte read cursor. This model provides the core efficiency guarantees of
the frame delivery system: O(panes × ring_size) memory instead of O(clients ×
buffer_size), one encode pass per frame regardless of client count, and no
per-client dirty tracking.

Per-client viewports are architecturally incompatible with this model. If each
client can have a different viewport offset, the server must either (a) encode a
separate frame per client scoped to that client's viewport, negating the
single-encode optimization entirely, or (b) send the full frame to every client
and require clients to handle offset-based clipping — which defeats the purpose
of viewport-aware delivery. Neither approach is compatible with the shared ring
buffer design without re-introducing per-client buffers and per-client encode
passes.

## Decision

Per-client viewports are declined, not merely deferred. The phrase "deferred to
v2" in §8.9 (server-client-protocols Doc 02, v1.0-r12) is superseded by this
record: the feature is incompatible with the shared ring buffer architecture and
will not be added in v1 or in any future version that retains the shared ring
buffer model.

Under `latest` resize policy, clients with smaller windows than the effective
pane size clip to their own viewport at the top-left origin. This is the
permanent behavior. Clients that need to see the full pane must resize their
window to match or exceed the effective pane dimensions.

If per-client viewports are ever needed in the future, the ring buffer
architecture would need to be reconsidered from scratch. That is a separate
architectural decision requiring evidence of need and a replacement model for
efficient multi-client frame delivery.

## Consequences

- The resize behavior for smaller clients is finalized: top-left clipping, no
  scrolling or panning within the clipped area. This is documented as permanent
  behavior, not a temporary limitation.
- The shared ring buffer model remains intact: one encode pass per frame,
  O(panes × ring_size) + O(clients) memory, no per-client frame filtering.
- Any future request for per-client viewports requires a full architectural
  review of the frame delivery model, not an incremental protocol extension.
