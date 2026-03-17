# 00037. Extension Negotiation Timing

- Date: 2026-03-17
- Status: Accepted

## Context

During design of Doc 06 §8 (Extension Negotiation), the timing of extension
negotiation was left as an open question. The concern was that advertising
capabilities before authentication could leak server information to
unauthenticated clients. Two options were considered:

1. **Before auth** (during handshake): simpler, but risks information leakage.
2. **After auth**: safer, but adds a round-trip and complicates the handshake
   state machine.

A transport-specific split was suggested: after auth for SSH tunnel, during
handshake for Unix socket.

## Decision

**Negotiate extensions during the handshake phase (after capability negotiation,
before session attach), regardless of transport.**

The information leakage concern does not apply to either transport in this
design:

- **Unix socket**: authentication is OS-level UID check, not a protocol-layer
  auth phase. There is no "unauthenticated client" at the protocol level.
- **SSH tunnel**: authentication is handled entirely by SSH before the
  connection reaches the daemon. The daemon only ever receives
  already-authenticated connections.

A transport-specific split adds complexity for no benefit. The existing §8.2
wording ("sent during the handshake phase") is correct as written.

## Consequences

- No protocol change required. Doc 06 §8.2 already specifies handshake-phase
  negotiation.
- No transport-specific branching in the handshake state machine.
