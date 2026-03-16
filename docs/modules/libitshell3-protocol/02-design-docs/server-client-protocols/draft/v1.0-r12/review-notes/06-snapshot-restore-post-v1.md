# Snapshot/Restore: Remove from v1, Move to Post-v1

- **Date**: 2026-03-17
- **Raised by**: owner
- **Severity**: HIGH
- **Affected docs**: Doc 06 §4 (Persistence)
- **Status**: open

---

## Problem

The Snapshot/Restore feature (Doc 06 §4, message types 0x0700-0x0707) was
designed with unclear semantics. Three fundamental issues identified during
owner review:

1. **PTY state is irrecoverable.** Daemon restart destroys all PTY file
   descriptors and orphans shell processes. "Restore" can only reconstruct
   layout + spawn new shells + replay scrollback — not recover actual session
   state.

2. **Client trigger is undefined.** No mechanism exists for the daemon to signal
   restart to clients, nor for clients to know when and whether to send
   `RestoreSessionRequest`.

3. **Scope unclear.** What exactly gets restored was never precisely defined.
   The feature was over-designed before its semantics were established.

## Analysis

The core value of a terminal multiplexer is keeping sessions alive while the
client disconnects. Daemon restart recovery is a secondary concern with
fundamentally different constraints. Designing the wire protocol before defining
restore semantics produced a protocol that cannot be correctly implemented.

## Proposed Change

1. **Remove Doc 06 §4** (Persistence) message definitions entirely —
   SnapshotRequest (0x0700), SnapshotResponse (0x0701), RestoreSessionRequest
   (0x0702), RestoreSessionResponse (0x0703), SnapshotListRequest (0x0704),
   SnapshotListResponse (0x0705), SnapshotAutoSaveConfig (0x0706),
   SnapshotAutoSaveConfigAck (0x0707). Reserve the 0x0700-0x07FF range for
   future use.

2. **Move to `99-post-v1-features.md`** with a note that post-v1 work must first
   define restore scope precisely: what can be restored given PTY state loss
   (layout only? scrollback buffer? new shell spawn?), before any wire protocol
   is designed.

3. **See ADR 00036** for the decision rationale.

## Owner Decision

Remove from v1. Move to post-v1 with requirement to define restore scope before
designing wire messages. See ADR 00036.

## Resolution

Pending spec update (Doc 06 §4 deletion, 99-post-v1-features.md update).
