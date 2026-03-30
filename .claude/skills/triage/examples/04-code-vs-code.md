## Example 4: Code <-> Code Conflict

### What

The session manager's `destroySession` function frees all pane slots
synchronously during session teardown, but the frame delivery subsystem's
`deliverPendingFrames` timer callback reads those same pane slots on a 16 ms
interval without checking whether the owning session is still alive. When a
session is destroyed between timer ticks, the next tick dereferences freed
memory.

### Why

After ~50 rapid reconnections in testing, the daemon segfaults. In release
builds, it silently corrupts other sessions' pane data because the freed memory
gets reused. Debug builds catch it immediately (Zig's general-purpose allocator
panics on use-of-freed-memory), but release builds produce undefined behavior
that can affect unrelated sessions.

### Who

The session manager (`modules/libitshell3/src/session/session_manager.zig`) vs.
the frame delivery subsystem
(`modules/libitshell3/src/server/frame_delivery.zig`).

### When

Both functions were introduced during Plan 3 (session lifecycle) and Plan 4
(frame delivery pipeline) respectively. The conflict was not caught because Plan
3 tests do not exercise concurrent frame delivery, and Plan 4 tests never
destroy a session mid-delivery.

### Where

The race between session destruction and frame delivery:

```
Session destroy:     T+0 disconnect clients → T+1 FREE pane slots → T+2 remove session
Frame delivery:      T+0 get session ptr ─────────────────────────→ T+3 read pane.dirty
                                                                         ↑ USE-AFTER-FREE
                                                                    (pane freed at T+1)
```

The root cause: `destroySession` assumes no concurrent readers exist because all
clients have been disconnected. `deliverPendingFrames` assumes panes live as
long as the session and that it will be explicitly stopped before any teardown.
Neither coordinates with the other about shutdown ordering.

The frame delivery callback already holds a direct pointer to the session struct
from before destruction began. Even though the session is removed from the
registry at T+2, the callback's pointer is stale. When it calls
`pane_tree.allPanes()` and reads `pane.render_state.isDirty()`, it follows
pointers into freed pane slots.

### How

The owner needs to decide how destruction and frame delivery coordinate. Options
include but are not limited to: adding a shutdown handshake where
`destroySession` first removes the session from `active_sessions` and waits for
the current delivery tick to complete before freeing pane slots, using
generation counters on pane slots so the frame delivery callback can detect
stale references, or restructuring so that `destroySession` only marks the
session as "pending destruction" and the frame delivery loop performs the actual
cleanup after it finishes the current tick.

---
