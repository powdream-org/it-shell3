# 00034. Per-Connection Handshake, No Optimization

- Date: 2026-03-16
- Status: Accepted

## Context

Each client connection (one per tab) performs a full ClientHello/ServerHello
handshake. A multi-tab client opening 10 tabs simultaneously triggers 10
independent handshakes. A lightweight "additional connection" optimization
(e.g., a session token that skips capability negotiation after the first
connection) could reduce this overhead.

## Decision

No lightweight reconnect or additional-connection optimization in v1. Every
connection performs the full ClientHello/ServerHello exchange.

The handshake is a single JSON round-trip (~200 bytes each way) over a local
Unix socket — sub-millisecond latency. Even 10 tabs opening simultaneously
produce ~10ms of total handshake overhead. Over SSH, the protocol handshake RTT
is negligible compared to SSH connection establishment (key exchange,
authentication). The optimization would add protocol complexity (token
management, expiry, invalidation) for no user-perceptible benefit.

## Consequences

- Every connection is self-contained — no shared authentication state between
  connections, no token lifecycle to manage.
- Capability negotiation happens per connection, so mixed-version clients are
  handled naturally.
- If future use cases require hundreds of simultaneous connections, the decision
  can be revisited. Current analysis shows the overhead is negligible.
