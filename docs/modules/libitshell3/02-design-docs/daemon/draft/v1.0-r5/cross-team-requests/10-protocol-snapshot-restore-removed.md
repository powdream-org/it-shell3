# Remove Snapshot/Restore from Daemon Design (v1 Scope Removal)

- **Date**: 2026-03-17
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: daemon design docs
- **Status**: open

---

## Context

During owner review of the protocol spec (v1.0-r12), the Snapshot/Restore
feature was removed from v1 scope (ADR 00036, supersedes ADR 00031). The removal
was based on three fundamental problems:

1. **PTY state is irrecoverable.** Daemon restart destroys all PTY file
   descriptors and orphans shell processes. "Restore" can only mean layout
   reconstruction + new shell spawn + scrollback replay, not actual session
   state recovery.
2. **Client trigger mechanism is undefined.** No protocol mechanism exists for
   the daemon to signal restart to clients, nor for clients to know when to send
   a restore request.
3. **Restore scope was never defined.** The feature was designed before
   answering what "restore" means given PTY state loss.

A prior CTR (this file, originally CTR-10) requested the daemon team to document
the session restore procedure. That request is now void.

## Required Changes

1. **Remove any Snapshot/Restore content** from daemon design docs if it was
   added based on the prior version of this CTR. Affected areas:
   - Session restore orchestration
   - IME engine re-initialization on restore
   - Scrollback restoration procedure
   - Post-restore message sequence

2. **Do not implement** Snapshot/Restore functionality in v1. The message type
   range 0x0700-0x07FF is reserved but unused in v1.

## Summary Table

| Target Doc            | Section/Message         | Change Type | Source Resolution           |
| --------------------- | ----------------------- | ----------- | --------------------------- |
| Runtime policies      | Session restore content | Remove      | Protocol v1.0-r12 ADR 00036 |
| Internal architecture | Snapshot/Restore design | Remove      | Protocol v1.0-r12 ADR 00036 |
