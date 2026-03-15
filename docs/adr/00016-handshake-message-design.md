# 00016. Handshake Message Design

- Date: 2026-03-16
- Status: Accepted

## Context

The handshake phase (ClientHello/ServerHello) carries capability negotiation,
session listing, and client identity. Several structural decisions shape how
runtime state updates are handled vs initial negotiation.

## Decision

Three related handshake design decisions:

1. **ClientDisplayInfo as separate message** (not part of ClientHello): Display
   and transport conditions change at runtime (monitor switch, power state,
   network change). A separate message (0x0505) allows re-sending without
   re-handshaking. ClientHello stays focused on capability negotiation.
2. **Coalescing config in ServerHello**: Informational for the client. The
   server controls actual coalescing. Exposing parameters enables client-side
   latency estimation and debugging.
3. **client_id in ServerHello**: Server-assigned monotonic u32. Required for
   preedit ownership comparison (client needs to know if it is the
   preedit_owner). Assigned per daemon lifetime, not globally unique.

## Consequences

- Runtime display changes do not require re-handshaking.
- Client can estimate latency from coalescing parameters without probing.
- Preedit ownership is unambiguous via client_id comparison.
