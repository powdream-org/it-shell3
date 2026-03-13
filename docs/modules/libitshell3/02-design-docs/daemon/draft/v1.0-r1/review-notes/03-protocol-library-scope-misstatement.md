# Protocol Library Scope Misstatement

**Date**: 2026-03-09
**Raised by**: owner
**Severity**: MEDIUM
**Affected docs**: 01-internal-architecture.md (Section 1.4)
**Status**: open

---

## Problem

Section 1.4 (Ring Buffer Placement) states:

> "The protocol library defines message formats, not delivery mechanisms."

This is incorrect. Per Resolution 5, the protocol library owns four layers:

| Layer | Scope |
|-------|-------|
| L1 Codec | Message formats (encode/decode) |
| L2 Framing | MessageReader/MessageWriter |
| L3 Connection Protocol | State machine |
| **L4 Transport** | **Socket lifecycle, Listener, Connection (recv/send/sendv/close)** |

Layer 4 is a delivery mechanism — it handles socket creation, I/O wrappers, and stale socket detection. The statement reduces the protocol library's scope to Layer 1 only, contradicting the 4-layer model established in R5 and documented in 02-integration-boundaries.md Section 1.

## Proposed Change

Replace:

> "The protocol library defines message formats, not delivery mechanisms. There is no client-side analogue."

With:

> "The ring buffer is a server-side application-level delivery optimization (multi-client cursor management, writev scheduling) with no client-side analogue. The protocol library provides transport-level I/O (Layer 4), but application-level delivery strategies are the consumer's responsibility."

## Owner Decision

Confirmed. The corrected statement should accurately reflect the protocol library's 4-layer scope.

## Resolution

(open)
