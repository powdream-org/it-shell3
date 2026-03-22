# Pane Process Exit Cascade — Sequence Diagram

- **Date**: 2026-03-22
- **Source team**: protocol
- **Source version**: libitshell3-protocol server-client-protocols
  draft/v1.0-r12
- **Source resolution**: owner review (v1.0-r12 cleanup)
- **Target docs**: daemon design docs
- **Status**: open

---

## Context

Protocol doc 03 (Session and Pane Management) Section 2.5 defines the
wire-observable message sequence when a pane's process exits. The daemon design
docs already have a text description of SIGCHLD handling (internal architecture
doc) and pseudocode for the handler (lifecycle doc), but two gaps exist:

1. There is no **sequence diagram** showing the full cascade from SIGCHLD to the
   final notification messages.
2. The existing SIGCHLD handler pseudocode in the lifecycle doc does not
   explicitly mention sending `SessionListChanged` when the last pane in a
   session exits and the session is auto-destroyed.

This CTR requests that both gaps be closed in the daemon design docs.

## Required Changes

1. Add a **sequence diagram** to the daemon design docs (internal architecture
   or lifecycle doc, at the daemon team's discretion) showing the full pane
   process exit cascade:
   - SIGCHLD received
   - `PaneMetadataChanged` sent to all attached clients with `is_running: false`
   - Layout reflow (same as ClosePaneRequest)
   - `LayoutChanged` sent to all attached clients
   - If the exited pane was the last pane in the session: session
     auto-destroyed, `SessionListChanged` sent with `event: "destroyed"`

2. Add an explicit `SessionListChanged` step to the existing SIGCHLD handler
   pseudocode in the lifecycle doc, covering the "last pane exits" case.

## Summary Table

| Target Doc         | Section/Area       | Change Type | Source Resolution               |
| ------------------ | ------------------ | ----------- | ------------------------------- |
| Daemon design docs | SIGCHLD handling   | Add diagram | owner review (v1.0-r12 cleanup) |
| Lifecycle doc      | SIGCHLD pseudocode | Extend      | owner review (v1.0-r12 cleanup) |

## Reference: Original Protocol Text (removed from Doc 03 §2.5)

### From Doc 03 §2.5 Auto-Close on Process Exit

**Normative**: When a pane's process exits, the server MUST automatically close
the pane. The server sends `PaneMetadataChanged` with `is_running: false`,
followed by the same sequence as ClosePaneRequest (layout reflow,
`LayoutChanged` notification). If the auto-closed pane was the last pane in the
session, the session is auto-destroyed (`side_effect=1`). Remain-on-exit is
deferred to post-v1 (see `99-post-v1-features.md` Section 2).
