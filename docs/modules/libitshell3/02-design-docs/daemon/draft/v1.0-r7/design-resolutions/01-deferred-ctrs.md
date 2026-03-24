# Design Resolutions: Deferred CTRs (Daemon v1.0-r7)

**Date**: 2026-03-24 **Team**: daemon-architect, ghostty-integration-engineer,
ime-system-sw-engineer, principal-architect, protocol-architect,
system-sw-engineer (6 members) **Scope**: Integration of 4 deferred CTRs from
protocol v1.0-r12 cleanup into daemon design docs **Source**: Cross-team
requests from `draft/v1.0-r5/cross-team-requests/`: CTR-13, CTR-14, CTR-18,
CTR-19; ADRs 00038, 00039, 00043

---

## Resolution 1: Silence Detection Timer (CTR-13) (6/6 unanimous)

**Source**: CTR-13 (`13-protocol-silence-detection-timer.md`), ADR 00038
**Affected docs**: `04-runtime-policies.md` (new Section 11)

### Decision

Add a per-pane silence detection timer integrated into the PTY read path.

**Timer lifecycle** (arm / reset / fire / re-arm / disarm):

1. **Arm**: On PTY read, if the pane has at least one silence subscriber and the
   timer is not already armed, set `pane.silence_deadline = now + min_threshold`
   where `min_threshold` is the minimum `silence_threshold_ms` across all active
   subscriptions for that pane.
2. **Reset**: On each subsequent PTY read, update
   `pane.silence_deadline = now + min_threshold`. This is a single field write
   in the PTY read handler, placed next to the existing
   `dirty_mask |= (1 << pane.slot_index)` operation. No syscall.
3. **Fire**: When the timer expires (minimum threshold reached), send
   `SilenceDetected` to ALL subscribers for that pane, regardless of their
   individual thresholds (**minimum-threshold-wins** — all subscribers are
   notified at the earliest threshold). The timer then disarms (deadline set to
   null).
4. **Re-arm**: On the next PTY read after firing, the timer re-arms per step 1.
5. **Disarm**: When the last subscriber is removed (count reaches 0), set
   `silence_deadline = null`.

**Timer implementation** (implementation discretion — two viable approaches):

1. **Single periodic sweep**: One `EVFILT_TIMER` at 500ms interval checks all
   panes with active subscriptions. Pro: no per-output kqueue syscall. Con: up
   to 500ms late delivery (acceptable for a notification feature).
2. **Per-pane `EVFILT_TIMER`**: One kqueue timer per subscribable pane with
   `EV_ONESHOT`. `EV_ADD` on each PTY read resets the countdown. Pro: exact
   threshold, zero userspace bookkeeping. Con: one `kevent()` changelist
   modification per PTY read for subscribed panes.

Both produce identical observable behavior. The design docs should specify the
timer lifecycle semantics (arm/reset/fire/re-arm/disarm, cleanup triggers,
per-client thresholds) without prescribing the kqueue strategy. Either approach
is acceptable.

For either approach, a global `total_silence_subscribers` counter controls
activation: arm the mechanism on 0-to-1 transition, disarm on 1-to-0.

**Timer reset point**: PTY read handler, after `read(pty_fd)`, before
`terminal.vtStream()`. The silence timer measures PTY output activity, not
rendering activity. Control sequences that produce no visible changes still
reset the timer — the process IS producing output.

**Per-(client, pane) subscription tracking**: Each pane maintains a bounded
subscription list:

```zig
// server/pane.zig (new fields)
silence_subscriptions: BoundedArray(SilenceSubscription, MAX_SILENCE_SUBSCRIBERS),
silence_deadline: ?i64,  // now + min(thresholds), null = disarmed

const SilenceSubscription = struct {
    client_id: u32,
    threshold_ms: u32,
};
```

**Minimum-threshold-wins**: When multiple clients subscribe to the same pane
with different thresholds (e.g., 10s and 30s), the pane-level timer is set to
the minimum (10s). On fire, `SilenceDetected` is sent to ALL subscribers — no
per-client selective firing, no re-arm at a higher threshold. This is simpler
than per-client deadline tracking: the fire path iterates subscribers and sends
to all, then disarms. The next PTY output re-arms at the minimum threshold
again.

**6 cleanup triggers** (5 from ADR 00038 + pane destruction):

| # | Trigger              | Code path                                     | Action                                                 |
| - | -------------------- | --------------------------------------------- | ------------------------------------------------------ |
| 1 | Explicit Unsubscribe | Message handler                               | Remove subscription, recalculate min threshold         |
| 2 | Graceful disconnect  | Client disconnect handler (doc03 Section 3.3) | Remove all subscriptions for client                    |
| 3 | Connection timeout   | Stale client eviction (doc04 Section 3)       | Remove all subscriptions for client                    |
| 4 | Session detach       | OPERATING -> READY transition                 | Remove subscriptions for panes in the detached session |
| 5 | Client eviction      | Forced disconnect path                        | Remove all subscriptions for client                    |
| 6 | Pane destruction     | Pane exit cascade (CTR-18), ClosePaneRequest  | Cancel all subscriptions for the destroyed pane        |

All 6 triggers converge on a `removeClientSubscriptions(client_id)` or
`removePaneSubscriptions(pane_slot)` helper. When subscriber count reaches 0,
the per-pane timer auto-disarms. When the global subscriber count reaches 0, the
timer mechanism itself is disabled.

### Rationale

- ADR 00038 defines the activity-then-silence pattern and the 5 client-side
  cleanup triggers. The 6th trigger (pane destruction) is a cross-CTR concern
  identified during discussion (see Cross-CTR Concerns below).
- Timer implementation is left as implementation discretion. Both the sweep and
  per-pane `EVFILT_TIMER` approaches were discussed; both produce identical
  observable behavior. The design doc specifies the semantic lifecycle, not the
  kqueue strategy.
- Minimum-threshold-wins simplifies the fire path: send to all subscribers,
  disarm. No per-client deadline tracking, no selective firing, no re-arm at the
  next threshold. Clients requesting higher thresholds receive slightly early
  notifications — acceptable for a notification feature.
- Per-(client, pane) subscription records are still needed for cleanup (the 6
  triggers must know which subscriptions to remove).

### Prior art

tmux does not have a silence detection feature. The `monitor-silence` option in
tmux uses a window-level timer implemented via libevent timers — conceptually
similar to our per-pane approach but without per-client thresholds.

---

## Resolution 2: Session Destroy Cascade and Rename Broadcast (CTR-14) (6/6 unanimous)

**Source**: CTR-14 (`14-protocol-session-list-changed-cascade.md`), ADR 00039
**Affected docs**: `03-lifecycle-and-connections.md` (new Sections 3.4, 3.5)

### Decision

Document two server-side behavior procedures in doc03.

**Session destroy cascade** — ordered procedure when `DestroySessionRequest` is
processed:

```
handleDestroySession(requester_client_id, session_id):

    entry = sessions.get(session_id) orelse return ERR_NOT_FOUND

    // Phase 1: IME cleanup (needs focused pane PTY still open)
    result = entry.session.ime_engine.deactivate()
    if result.committed_text:
        write(focused_pane.pty_fd, result.committed_text)  // best-effort flush
    if composition was active:
        send PreeditEnd to all attached clients
    entry.session.ime_engine.deinit()

    // Phase 2: Resource cleanup
    for each pane in session:
        cancel silence subscriptions for pane (CTR-13 cleanup trigger 6)
        kill(pane.child_pid, SIGHUP)    // explicit signal, consistent with
                                         // graceful shutdown (doc03 Section 2.1 Step 5)
                                         // and ClosePaneRequest
        remove pane.pty_fd from kqueue
        close(pane.pty_fd)
        Terminal.deinit()
        pane_slots[slot] = null
        free_mask |= (1 << slot)

    // Phase 3: Protocol notifications
    // Response to requester FIRST (response-before-notification rule, per protocol docs)
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
- `DestroySessionResponse` before `SessionListChanged` — response-before-
  notification rule (per protocol docs)
- All messages sent in one event loop iteration — no yield to kevent between
  them (Unix socket SOCK_STREAM guarantees in-order delivery)
- Session state freed AFTER all notifications sent — notification construction
  may reference session fields (name, id)
- `engine.deactivate()` is unconditional — if the PTY is dead (last-pane SIGCHLD
  case), the write fails silently, which is acceptable (best-effort)

**Shared teardown with CTR-18**: The last-pane SIGCHLD path (CTR-18 step 12)
reuses the same `destroySessionEntry()` function. The difference: SIGCHLD has no
requesting client, so `DestroySessionResponse` and `ClientDetached` are skipped.
The shared function takes an optional `requester_client_id` parameter (`null`
for SIGCHLD-triggered, set for `DestroySessionRequest`-triggered).

**Rename broadcast** — ordered procedure when `RenameSessionRequest` is
processed:

```
handleRenameSession(requester_client_id, session_id, new_name):
    entry = sessions.get(session_id) orelse return ERR_NOT_FOUND
    if name_already_in_use(new_name): return ERR_DUPLICATE_NAME

    // 1. Update state
    entry.session.name = new_name

    // 2. Response to requester first
    send RenameSessionResponse{ status: 0 } to requester

    // 3. Broadcast to all connected clients
    broadcast SessionListChanged{ event: "renamed", session_id, name: new_name }
```

No IME or ghostty implications for rename — session name is daemon-level
metadata.

### Rationale

- ADR 00039 defines the three `SessionListChanged` event types (created,
  destroyed, renamed). CTR-14 specifies the daemon-side procedures.
- The destroy cascade is a linear imperative sequence (not a state machine)
  executed within one event loop iteration. Single-threaded serialization
  guarantees no interleaving with other events.
- IME cleanup before resource cleanup: `engine.deactivate()` may produce
  committed text that must be written to the focused pane's PTY. The PTY must
  still be open at this point.
- Explicit `kill(child_pid, SIGHUP)` before PTY close for consistency with the
  graceful shutdown path (doc03 Section 2.1 Step 5) and `ClosePaneRequest`. All
  three child termination paths use the same pattern.

---

## Resolution 3: Pane Exit Cascade and Sequence Diagram (CTR-18) (6/6 unanimous)

**Source**: CTR-18 (`18-pane-exit-cascade-sequence-diagram.md`) **Affected
docs**: `03-lifecycle-and-connections.md` (Section 3.2 rewrite + new sequence
diagram)

### Decision

**`[ADR-CANDIDATE]` Two-phase SIGCHLD handling**: Adopt a two-phase approach
(reap+mark, drain PTY, then destroy) instead of immediate destruction in the
SIGCHLD handler. This ensures the user sees the child process's final output
before the pane disappears.

**Event processing priority**: When a single `kevent64()` call returns both
`EVFILT_SIGNAL` (SIGCHLD) and `EVFILT_READ` (PTY data) events, `EVFILT_SIGNAL`
MUST be processed first. This ensures the `PANE_EXITED` flag is set before the
PTY read handler checks for it, which is critical for correct two-phase model
operation.

**Phase 1 — SIGCHLD handler (reap + mark)**:

```
When EVFILT_SIGNAL fires for SIGCHLD:
    loop:
        result = waitpid(-1, WNOHANG)
        if result.pid == 0: break          // no more exited children
        if result.pid == -1 and errno == ECHILD: break  // no children

        pane = lookupPaneByChildPid(result.pid)
        if pane == null: continue          // unknown child

        pane.is_running = false
        pane.exit_status = WEXITSTATUS(result.status)
        pane.flags |= PANE_EXITED

        // Check if PTY EOF was already received (rare: EOF before SIGCHLD)
        if pane.flags & PTY_EOF:
            executePaneDestroyCascade(pane)
        // else: PTY read handler will drain remaining data and trigger cascade
```

**Phase 2 — PTY read handler drains remaining data (EV_EOF model)**:

```
When EVFILT_READ fires for a pty_fd:
    n = read(pty_fd, buf)
    if n > 0:
        terminal.vtStream(buf[0..n])
        // normal processing: dirty_mask, silence timer reset, coalescing

    if event.flags & EV_EOF:
        // PTY slave closed — kqueue delivers EV_EOF even with zero remaining data
        pane.flags |= PTY_EOF
        if pane.flags & PANE_EXITED:
            executePaneDestroyCascade(pane)
```

The dual-flag model (`PANE_EXITED` + `PTY_EOF`) replaces the `ioctl(FIONREAD)`
check. Either event can arrive first: if SIGCHLD arrives first, the SIGCHLD
handler checks `PTY_EOF`; if PTY EOF arrives first, the read handler checks
`PANE_EXITED`. The cascade triggers when both flags are set, regardless of
arrival order. No extra syscall needed.

**Safety timeout**: As an implementation hint, a 5-second `EVFILT_TIMER`
fallback can be armed in Phase 1 for each `PANE_EXITED` pane. If `EV_EOF` never
arrives (pathological case — e.g., a background process inherits the PTY slave
fd), the timeout fires and triggers the destroy cascade unconditionally. This
prevents zombie panes from persisting indefinitely.

**Phase 3 — `executePaneDestroyCascade(pane)`** (complete 12-step ordering,
merging all team inputs):

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
        session.ime_engine.reset()   // discard composition (PTY is dead)
        if composition was active:
            send PreeditEnd{ reason: "pane_closed" } to all attached clients

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
        // Reuses shared destroySessionEntry() from CTR-14
        destroySessionEntry(session_entry, requester: null)
        //   -> engine.deactivate() + deinit()
        //   -> SessionListChanged(destroyed) to ALL clients
        //   -> forced DetachSessionResponse to attached clients
        //   -> if no sessions remain: graceful shutdown
```

**Ordering invariants** (satisfied by the step sequence above):

| Constraint                                        | Source                                  | Steps                   |
| ------------------------------------------------- | --------------------------------------- | ----------------------- |
| Pending frames flushed before PaneMetadataChanged | protocol-architect + system-sw-engineer | 1 before 2              |
| PaneMetadataChanged before silence cleanup        | system-sw-engineer                      | 2 before 3              |
| IME cleanup before resource cleanup               | ime-system-sw-engineer                  | 4 before 5-7            |
| PreeditEnd before LayoutChanged                   | ime-system-sw-engineer                  | 4b before 11            |
| Terminal.deinit() after PTY close                 | ghostty-integration-engineer            | 7 after 6               |
| Terminal.deinit() before tree mutation            | ghostty-integration-engineer            | 7 before 9              |
| No tombstone state                                | ghostty-integration-engineer            | 8 (slot null) is atomic |
| Focus selection before LayoutChanged              | protocol-architect                      | 10a before 11           |
| PaneMetadataChanged before LayoutChanged          | protocol-architect                      | 2 before 11             |
| LayoutChanged before SessionListChanged           | protocol-architect                      | 11 before 12            |
| EVFILT_SIGNAL before EVFILT_READ                  | system-sw-engineer                      | Phase 1 before Phase 2  |

**Non-focused pane exit**: When the exiting pane is NOT the focused pane, step 4
(IME cleanup) is skipped entirely. The IME engine only tracks state for the
focused pane. All other steps are identical.

**Sequence diagram**: Add a mermaid sequence diagram to doc03 Section 3.2 with
three participant lanes: Daemon (internal), Attached Clients (clients viewing
the session), All Clients (all connected clients). The diagram covers both the
non-last-pane and last-pane paths.

**Pseudocode gap fix**: The existing SIGCHLD pseudocode in doc03 Section 3.2
(lines 429-463) handles resource cleanup but omits all client notifications
(PaneMetadataChanged, LayoutChanged, SessionListChanged) and IME steps. The
rewrite replaces this with the complete two-phase model above. Doc01 Section 3.4
text description should reference the doc03 pseudocode as the single
authoritative reference rather than maintaining a parallel description.

### Rationale

- **Two-phase SIGCHLD**: When a child exits, it may have written final output
  (e.g., exit message, shell prompt cleanup) that sits in the PTY buffer. tmux
  uses the same two-phase strategy: set `PANE_EXITED` flag on SIGCHLD, continue
  draining PTY data via libevent bufferevent, destroy only after EOF. Immediate
  destruction would discard this output, causing visible data loss.
- **EV_EOF dual-flag model**: Replaces `ioctl(FIONREAD)` with a cleaner
  approach. kqueue delivers `EV_EOF` on the PTY master when the slave closes,
  even with zero remaining data. The dual-flag model (`PANE_EXITED` + `PTY_EOF`)
  handles both arrival orders without extra syscalls. A 5-second safety timeout
  handles the pathological case where `EV_EOF` never arrives (background process
  inheriting the PTY slave fd).
- **Signal safety**: SIGCHLD arrives via `EVFILT_SIGNAL` (blocked with
  `sigprocmask`), not a signal handler. Processing runs in normal execution
  context — no signal-safety constraints on the code in Phase 1.

### Prior art

- **tmux** (`server-client.c`, `window.c`): Two-phase child reaping.
  `waitpid(-1, WNOHANG)` loop sets `PANE_EXITED`. PTY data continues to drain
  via libevent. `window_pane_destroy_ready()` checks `ioctl(FIONREAD)` before
  final destruction.

---

## Resolution 4: Pane Navigation Algorithm (CTR-19) (6/6 unanimous)

**Source**: CTR-19 (`19-pane-navigation-algorithm.md`), ADR 00043 **Affected
docs**: `01-internal-architecture.md` (new subsection under Section 3, State
Tree)

### Decision

**Module placement**: Pure function in `core/navigation.zig`. The algorithm
depends only on `core/` types (`SplitNodeData`, `PaneSlot`, `MAX_TREE_NODES`)
and integer parameters (`total_cols`, `total_rows`). No ghostty, OS, or protocol
dependencies. Fully unit-testable in isolation.

```zig
// core/navigation.zig
pub const Direction = enum { up, down, left, right };

pub fn findPaneInDirection(
    tree_nodes: *const [MAX_TREE_NODES]?SplitNodeData,
    total_cols: u16,
    total_rows: u16,
    focused: PaneSlot,
    direction: Direction,
) ?PaneSlot
```

Return type is `?PaneSlot`: returns `null` only for single-pane sessions (no
navigation possible). In multi-pane sessions, wrap-around guarantees a non-null
result.

**`[ADR-CANDIDATE]` Algorithm — edge adjacency with overlap filtering** (not
center-point distance):

1. **Compute geometric rectangles**: Walk the `tree_nodes` array, recursively
   computing `(x, y, w, h)` for each leaf node by accumulating split ratios.
   Store results in a stack-allocated `[MAX_PANES]Rect` array. With
   MAX_PANES=16, this is 16 multiply-accumulate operations — trivially fast,
   entirely in L1 cache.

2. **Direction filter**: For direction `up`, collect all panes whose bottom edge
   is at or above the focused pane's top edge. Similarly: `down` = top edge at
   or below focused bottom edge; `left` = right edge at or left of focused left
   edge; `right` = left edge at or right of focused right edge.

3. **Overlap filter**: Among candidates, keep only those whose perpendicular
   span overlaps with the focused pane's perpendicular span. For vertical
   navigation (up/down), this means the candidate's horizontal range `[x, x+w)`
   must overlap with the focused pane's horizontal range. This eliminates panes
   that are geometrically "above" but not reachable (e.g., diagonally offset
   with no overlap).

4. **Nearest selection**: Among remaining candidates, select the one with the
   shortest edge distance (distance between the focused pane's edge and the
   candidate's adjacent edge). Tie-break: prefer the most recently focused pane
   (MRU), matching tmux's `window_pane_choose_best()` behavior.

5. **Wrap-around**: If no candidate found after direction + overlap filtering,
   search in the opposite direction for the furthest pane (wrap around). For
   example, if navigating `up` from the topmost pane, select the bottommost pane
   that has horizontal overlap.

**`[ADR-CANDIDATE]` Wrap-around is always enabled (non-configurable in v1)**.
tmux wraps, zellij wraps — no terminal multiplexer provides a "no wrap" option.
Adding configurability would introduce a settings surface (per-session? global?
client-settable?) with no known user requirement. Deferred to post-v1 if
requested.

**Documentation format**: Pseudocode + one example diagram showing a 4-pane
layout with direction arrows. A multi-step flowchart would over-formalize a
~15-line function. The example diagram provides visual intuition for the edge
adjacency + overlap concept.

**No geometry caching in v1**: Recomputing 16 rectangles per NavigatePaneRequest
is trivially fast (bounded O(n) where n <= 16, cache-hot data). Caching adds
invalidation complexity (must invalidate on split, close, resize) for no
measurable benefit.

**Integration with CTR-18**: The focus transfer after pane close (CTR-18 step
10a) reuses the same navigation infrastructure. Both explicit
`NavigatePaneRequest` and implicit "nearest neighbor after close" use the same
geometric computation.

**Caller responsibility**: The caller in `server/` must call
`handleIntraSessionFocusChange()` (defined in `input/`) before updating
`session.focused_pane`. This flushes any active IME composition to the old
pane's PTY. The navigation algorithm returns only a `PaneSlot` — all side
effects (IME flush, focus update, notifications) are the caller's
responsibility.

**Protocol ordering**: `NavigatePaneResponse` is sent before `LayoutChanged`
notification, per the standard response-before-notification rule defined in the
protocol docs.

### Rationale

- **Edge adjacency over center-point distance**: Center-point distance has a
  known failure mode with asymmetric pane sizes — a tall narrow pane next to a
  short wide pane can select a geometrically non-adjacent pane that "feels
  wrong." Edge adjacency matches user expectations from tmux and vim split
  navigation.
- **`core/` placement over `server/`**: The function is a pure geometric
  computation over `core/` types. Placing it in `server/` would force unit tests
  to depend on the full server module (ghostty, OS, protocol). `core/` placement
  enables isolated testing with synthetic tree configurations.
- **Wrap-around always on**: YAGNI. The configuration point (where stored, how
  set, per-session vs global) is unnecessary complexity for v1. If a user
  requests no-wrap, adding a `wrap: bool` parameter is a trivial one-line
  change.

### Prior art

- **tmux** (`window.c:1336-1610`): `window_pane_find_up/down/left/right` uses
  edge adjacency + overlap filtering. Each direction function computes the
  focused pane's geometric bounds, finds the edge in the target direction,
  iterates all panes filtering for adjacent edge + horizontal/vertical overlap,
  then calls `window_pane_choose_best()` for tie-breaking (most recently focused
  pane wins). tmux always wraps.
- **ghostty**: Does not implement pane navigation at the library level (handled
  by the app runtime). No applicable precedent.

---

## Cross-CTR Concerns (6/6 unanimous)

Five cross-CTR interactions were identified during discussion:

| # | Concern                                                      | CTRs           | Resolution                                                                                                                                                                                       |
| - | ------------------------------------------------------------ | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1 | Pane exit must cancel silence timers                         | CTR-18, CTR-13 | `executePaneDestroyCascade()` step 3 clears all silence subscriptions for the destroyed pane after PaneMetadataChanged but before resource cleanup.                                              |
| 2 | Session destroy must cancel all silence timers for all panes | CTR-14, CTR-13 | `destroySessionEntry()` iterates all panes and runs per-pane cleanup (which includes subscription cancellation).                                                                                 |
| 3 | SIGCHLD pseudocode needs notification sends                  | CTR-18         | The existing doc03 Section 3.2 pseudocode handles only resource cleanup. The rewrite adds PaneMetadataChanged, PreeditEnd, LayoutChanged, SessionListChanged interleaved with the cleanup steps. |
| 4 | Navigation reuse for pane-close focus transfer               | CTR-19, CTR-18 | `executePaneDestroyCascade()` step 10a uses `findPaneInDirection()` from `core/` (or a simpler sibling heuristic) to select the new focused pane after pane removal.                             |
| 5 | NavigatePaneRequest response ordering                        | CTR-19         | Standard response-before-notification rule (per protocol docs). `NavigatePaneResponse` sent before `LayoutChanged`. No special handling needed.                                                  |

---

## Wire Protocol Changes

**None.** All resolutions are daemon-internal: timer lifecycle, cascade
procedures, pseudocode, algorithm placement. The wire protocol (message types,
field definitions, encoding) is unaffected. All referenced message types
(`SilenceDetected`, `SessionListChanged`, `PaneMetadataChanged`,
`DetachSessionResponse`, `LayoutChanged`, `NavigatePaneResponse`, `PreeditEnd`)
are already defined in the protocol spec.

---

## Doc Placement Summary

| CTR    | Target Doc                    | Section                        | Change Type                                                                           |
| ------ | ----------------------------- | ------------------------------ | ------------------------------------------------------------------------------------- |
| CTR-13 | doc04 (Runtime Policies)      | New Section 11                 | Add: silence timer lifecycle, subscription tracking, cleanup triggers                 |
| CTR-14 | doc03 (Lifecycle)             | New Sections 3.4, 3.5          | Add: session destroy cascade procedure, rename broadcast procedure                    |
| CTR-18 | doc03 (Lifecycle)             | Section 3.2 rewrite            | Rewrite: two-phase SIGCHLD, complete cascade pseudocode, add mermaid sequence diagram |
| CTR-19 | doc01 (Internal Architecture) | New subsection under Section 3 | Add: navigation algorithm pseudocode, example 4-pane diagram                          |

---

## Items Deferred

| Item                                         | Deferred to         | Rationale                                                                                                                          |
| -------------------------------------------- | ------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Configurable wrap-around for pane navigation | Post-v1             | YAGNI. No known user requirement. All reference implementations (tmux, zellij) always wrap. Adding the parameter later is trivial. |
| Geometry caching for navigation              | Implementation time | With MAX_PANES=16, recomputation is trivially fast. Caching adds invalidation complexity for no measurable benefit.                |
| `remain-on-exit` (keep dead pane visible)    | Post-v1             | Protocol spec `99-post-v1-features.md` Section 2. Current design immediately destroys panes on process exit.                       |
