# Implement Silence Detection Timer and Subscription Lifecycle Cleanup

- **Date**: 2026-03-17
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup), ADR 00038
- **Target docs**: daemon design docs
- **Status**: open

---

## Context

During owner review of the protocol spec (v1.0-r12), the silence detection scope
and subscription lifecycle were decided (ADR 00038). The full specification —
including timer mechanics, server behavior, client behavior, and all
subscription cleanup triggers — is in ADR 00038. This CTR summarizes the daemon
implementation work required.

## Required Changes

1. **Per-pane silence timer**: Implement a countdown timer per pane in the PTY
   read path. Arm on first output (only if subscribers exist), reset on each
   subsequent output, fire SilenceDetected on expiry, then disarm until next
   output. See ADR 00038 for the complete timer lifecycle.

2. **Subscription lifecycle cleanup**: Implement automatic subscription cleanup
   and timer cancellation for all five termination cases defined in ADR 00038:
   explicit Unsubscribe, graceful disconnect, connection timeout, session
   detach, and client eviction.

## Summary Table

| Target Doc       | Area                           | Change Type | Source Resolution |
| ---------------- | ------------------------------ | ----------- | ----------------- |
| Runtime policies | Per-pane silence timer         | Add         | ADR 00038         |
| Runtime policies | Subscription lifecycle cleanup | Add         | ADR 00038         |
