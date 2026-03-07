# Extension Negotiation Timing

**Date**: 2026-03-07
**Raised by**: owner (triage of Doc 06 Open Question #3)
**Severity**: LOW
**Affected docs**: Doc 06 (Flow Control and Auxiliary)
**Status**: confirm-and-close

---

## Problem

Should extensions be negotiated before or after authentication? Before auth risks information leakage (advertising capabilities to unauthenticated clients). After auth adds latency.

## Proposed Change

- **Unix sockets**: During handshake (no auth boundary — local trust model).
- **SSH tunnel transport**: After auth. Prevents capability advertisement to unauthenticated clients.

## Owner Decision

Accepted. Transport-dependent timing.

## Resolution

{To be applied in v0.8 writing phase. Add normative statement to Doc 06, close Q3.}
