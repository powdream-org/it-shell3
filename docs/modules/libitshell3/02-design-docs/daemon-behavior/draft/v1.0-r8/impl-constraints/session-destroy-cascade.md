# Session Destroy Cascade — Implementation Reference

> **Transient artifact**: Copied from r7 pseudocode. Deleted when implemented as
> code with debug assertions.

Source: `daemon/draft/v1.0-r7/03-lifecycle-and-connections.md` §3.4

---

Copied verbatim from r7:

### 3.4 Session Destroy Cascade

When a client sends `DestroySessionRequest`, the daemon executes an ordered
4-phase procedure within a single event loop iteration. Single-threaded
serialization guarantees no interleaving with other events.

```
handleDestroySession(requester_client_id, session_id):

    entry = sessions.get(session_id) orelse return ERR_NOT_FOUND

    // Phase 1: IME cleanup (needs focused pane PTY still open)
    result = entry.session.ime_engine.deactivate()
    if result.committed_text:
        write(focused_pane.pty_fd, result.committed_text)  // best-effort flush
    if composition was active:
        send PreeditEnd{ reason: "session_destroyed" } to all attached clients
    session.current_preedit = null
    session.preedit.owner = null
    entry.session.ime_engine.deinit()

    // Phase 2: Resource cleanup
    for each pane in session:
        cancel silence subscriptions for pane (CTR-13 cleanup trigger 6)
        kill(pane.child_pid, SIGHUP)    // explicit signal, consistent with
                                         // graceful shutdown (Section 2.1 Step 5)
                                         // and ClosePaneRequest
        remove pane.pty_fd from kqueue
        close(pane.pty_fd)
        Terminal.deinit()
        pane_slots[slot] = null
        free_mask |= (1 << slot)

    // Phase 3: Protocol notifications
    // Response to requester FIRST (response before notification rule)
    send DestroySessionResponse{ status: 0 } to requester

    // Broadcast to ALL connected clients (including requester)
    broadcast SessionListChanged{ event: "destroyed", session_id } to all clients

    // Force-detach other attached clients
    for clients_attached_to(session_id):
        if client.id == requester_client_id: continue
        send DetachSessionResponse{ reason: "session_destroyed" } to client
        client.state = READY
        client.attached_session = null
        send ClientDetached{ client_id: client.id } to requester

    // Phase 4: Free session state
    free SessionEntry
```

**Key ordering constraints**:

- IME `deactivate()` before PTY close — flush may write to PTY
- `DestroySessionResponse` before `SessionListChanged` —
  response-before-notification rule
- All messages sent in one event loop iteration — no yield to kevent between
  them (Unix socket SOCK_STREAM guarantees in-order delivery)
- Session state freed AFTER all notifications sent — notification construction
  may reference session fields (name, id)
- `engine.deactivate()` is unconditional — if the PTY is dead (last-pane SIGCHLD
  case), the write fails silently, which is acceptable (best-effort)

**Shared teardown with pane exit cascade (Section 3.2)**: The last-pane SIGCHLD
path (Section 3.2 step 12) follows a similar procedure but with different
notification ordering. The explicit `DestroySessionRequest` path (Section 3.4)
sends `DestroySessionResponse` before `SessionListChanged`
(response-before-notification rule). The SIGCHLD path has no requesting client,
so it broadcasts `SessionListChanged` first and skips `DestroySessionResponse`
and `ClientDetached` entirely.
