# Move AmbiguousWidthConfig Terminal Integration from Protocol to Daemon

- **Date**: 2026-03-20
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: daemon design docs
- **Status**: open

---

## Context

During owner review of the protocol spec (v1.0-r12), Doc 05 §4.1
(AmbiguousWidthConfig) was identified as containing one sentence describing a
server-internal implementation detail: how the server passes the received
configuration to libghostty-vt's Terminal API.

The protocol spec defines the wire message format and the client-side semantics.
The server's internal action of calling into libghostty-vt's Terminal with the
received value is a daemon implementation concern, not a wire-protocol concern.

This sentence is being removed from Doc 05 §4.1 and must be defined in the
daemon design docs.

## Required Changes

1. **AmbiguousWidthConfig handling**: When the server receives an
   `AmbiguousWidthConfig` message (type `0x0406`), document that it must pass
   the `ambiguous_width` value to the libghostty-vt Terminal instance for the
   affected pane(s). The Terminal uses this setting for cursor movement and line
   wrapping calculations. The scope field (`"per_pane"`, `"per_session"`, or
   `"global"`) determines which Terminal instances are updated. The server-side
   Terminal state must match the client-side cell width computation in order for
   the rendered cell grid to be correct.

## Summary Table

| Target Doc       | Section/Message                            | Change Type | Source Resolution             |
| ---------------- | ------------------------------------------ | ----------- | ----------------------------- |
| Runtime policies | AmbiguousWidthConfig Terminal pass-through | Add         | Protocol v1.0-r12 Doc 05 §4.1 |

## Reference: Original Protocol Text (removed from Doc 05 §4.1)

The following sentence appeared in Doc 05 §4.1 immediately after the field table
for AmbiguousWidthConfig:

> The server passes this configuration to libghostty-vt's Terminal, which uses
> it for cursor movement and line wrapping calculations. The client uses it for
> cell width computation during rendering.

The second sentence ("The client uses it for cell width computation during
rendering.") is a wire-observable client requirement and remains in the protocol
spec. Only the first sentence (the server-internal libghostty-vt API call) is
moved to daemon design docs via this CTR.
