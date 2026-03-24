# Pane Exit Cascade — Implementation Reference

> **Transient artifact**: Copied from r7 pseudocode. Deleted when implemented as
> code with debug assertions.

Source: `daemon/draft/v1.0-r7/03-lifecycle-and-connections.md` §3.2, Phase 3

---

Copied verbatim from r7 (lines 508-607):

#### Phase 3 — `executePaneDestroyCascade(pane)`

The complete 12-step cascade, executed within a single event loop iteration:

```
executePaneDestroyCascade(pane):
    session_entry = pane's owning SessionEntry

    // Step 1: Flush pending frame data
    if pane.has_dirty_state:
        forceFrameExport(pane)  // immediate bulkExport + send to clients
        // Ensures clients see the child's final rendered output

    // Step 2: Notify clients of process exit
    send PaneMetadataChanged{ pane_id, is_running: false, exit_status }
        to all attached clients
    send ProcessExited{ pane_id, exit_status } (0x0801)
        to subscribed clients (opt-in notification)

    // Step 3: Cancel silence subscriptions (CTR-13 cleanup trigger 6)
    removePaneSubscriptions(pane.slot_index)

    // Step 4: IME cleanup (only if this was the focused pane)
    if session.focused_pane == pane.slot_index:
        if session has remaining panes:
            session.ime_engine.reset()   // discard composition (PTY is dead)
            session.current_preedit = null
            session.preedit.owner = null
            if composition was active:
                send PreeditEnd{ reason: "pane_closed" } to all attached clients
                session.preedit.session_id += 1  // after PreeditEnd (carries old id)
        else:
            // Last pane — deactivate NOW while PTY fd is still open
            result = session.ime_engine.deactivate()
            if result.committed_text:
                write(pane.pty_fd, result.committed_text)  // best-effort flush
            session.current_preedit = null
            session.preedit.owner = null
            if composition was active:
                send PreeditEnd{ reason: "session_destroyed" } to all attached clients

    // Step 5: Remove PTY fd from kqueue
    kevent(kq, EV_DELETE, pane.pty_fd)

    // Step 6: Close PTY fd
    close(pane.pty_fd)

    // Step 7: Free ghostty Terminal state
    Terminal.deinit()

    // Step 8: Invalidate pane slot
    pane_slots[pane.slot_index] = null
    free_mask |= (1 << pane.slot_index)

    // Step 9: Remove pane from split tree, compact
    remove leaf for pane.slot_index from tree_nodes
    compact tree (relocate subtrees as needed)

    // Step 10: Determine outcome
    if session has remaining panes:
        // Step 10a: Select new focused pane
        new_focus = findPaneInDirection(tree_nodes, ..., old_focus, ...)
                    or sibling heuristic
        session.focused_pane = new_focus

        // Step 10b: Reflow layout (recompute geometric positions)
        reflow(tree_nodes, total_cols, total_rows)

        // Step 11: Notify clients of layout change (includes new focus)
        send LayoutChanged{ tree, focused_pane_id: new_focus.pane_id }
            to all attached clients

    else:
        // Step 12: Last pane — session auto-destroy
        // IME already deactivated + flushed in step 4 (PTY was still open)
        engine.deinit()
        // No requester — broadcast first
        broadcast SessionListChanged{ event: "destroyed", session_id }
            to all clients
        force-detach all attached clients → READY
        free SessionEntry
        if no sessions remain: initiate graceful shutdown
```

**Non-focused pane exit**: When the exiting pane is NOT the focused pane, step 4
(IME cleanup) is skipped entirely. The IME engine only tracks state for the
focused pane. All other steps are identical.

**Ordering invariants**:

| Constraint                                        | Steps                   |
| ------------------------------------------------- | ----------------------- |
| Pending frames flushed before PaneMetadataChanged | 1 before 2              |
| PaneMetadataChanged before silence cleanup        | 2 before 3              |
| IME cleanup before resource cleanup               | 4 before 5-7            |
| PreeditEnd before LayoutChanged                   | 4b before 11            |
| Terminal.deinit() after PTY close                 | 7 after 6               |
| Terminal.deinit() before tree mutation            | 7 before 9              |
| No tombstone state                                | 8 (slot null) is atomic |
| Focus selection before LayoutChanged              | 10a before 11           |
