# 00036. Snapshot/Restore Deferred to Post-v1

- Date: 2026-03-17
- Status: Accepted
- Supersedes: ADR 00031

## Context

ADR 00031 designed a hybrid persistence model (live state in memory, periodic
JSON snapshots to disk) with client-triggered snapshot/restore wire messages
(0x0700-0x0707). During owner review of Doc 06, three fundamental problems were
identified:

1. **PTY state cannot be restored.** When the daemon restarts, all PTY file
   descriptors are gone and shell processes are dead or orphaned. There is no
   mechanism to re-attach to previous shell processes. "Restore" can only mean
   layout reconstruction + new shell spawn + scrollback replay — not actual
   session state recovery.

2. **Client trigger mechanism is undefined.** `RestoreSessionRequest` requires
   the client to detect that the daemon restarted and decide to send the
   request. No mechanism exists in the protocol for the daemon to signal "I just
   restarted" nor for the client to discover available snapshots before deciding
   to restore.

3. **Core value mismatch.** The core value of a terminal multiplexer is keeping
   sessions alive while the _client_ disconnects and reconnects — not recovering
   from _daemon_ restarts. Daemon restart recovery is an edge case whose
   semantics (what exactly gets restored?) are not yet clearly defined.

## Decision

**Remove Snapshot/Restore from v1 scope.** The wire message definitions
(0x0700-0x0707: SnapshotRequest, SnapshotResponse, RestoreSessionRequest,
RestoreSessionResponse, SnapshotListRequest, SnapshotListResponse,
SnapshotAutoSaveConfig, SnapshotAutoSaveConfigAck) are removed from Doc 06. The
message type range 0x0700-0x07FF is reserved for future use.

Post-v1 work must first answer: what does "restore" actually mean given PTY
state loss? The scope of what can and cannot be restored must be precisely
defined before designing the protocol.

## Consequences

- Doc 06 §4 (Persistence) message definitions removed.
- CTR-10 (session restore procedure) is obsolete — no implementation needed.
- Post-v1: if session restore is revisited, define restore scope (layout only?
  scrollback? new shells?) before designing wire messages.
