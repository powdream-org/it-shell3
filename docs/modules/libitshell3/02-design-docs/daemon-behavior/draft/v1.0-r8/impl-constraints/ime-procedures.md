# IME Procedures — Implementation Reference

> **Transient artifact**: Copied from r7 pseudocode. Deleted when implemented as
> code with debug assertions.

Sources:

- `daemon/draft/v1.0-r7/04-runtime-policies.md` §8 (Server Behavior Procedures)
- `daemon/draft/v1.0-r7/02-integration-boundaries.md` §4.3 and §4.4

---

Copied verbatim from r7:

## 8. Server Behavior Procedures

This section defines step-by-step server procedures for preedit-related events,
separating procedure (engine call sequences, buffer lifetime, message ordering)
from policy (§6 ownership rules, §7 lifecycle policies). Each procedure
specifies the exact daemon-internal operations; wire-observable behavior
(message types, field values, ordering) is defined in the protocol spec.

### 8.1 Ownership Transfer (Reference Procedure)

The flush-and-transfer sequence is the foundational procedure. Other procedures
(§8.2-§8.4) reference these steps rather than duplicating them.

> **Serialization note**: The daemon uses a single-threaded kqueue event loop
> (doc01 §2.1). All steps within a procedure execute atomically with respect to
> other event handlers — no explicit locking is needed or possible.

1. Call `engine.flush()` to commit the current composition.
2. **Extract `committed_text` from the returned `ImeResult` BEFORE making any
   further engine calls.** Engine internal buffers are invalidated on the next
   mutating call (`processKey()`, `flush()`, `reset()`) — per IME contract
   Section 6. The daemon MUST copy `committed_text` (e.g., write to PTY, copy to
   send buffer) before proceeding.
3. Write `committed_text` to PTY.
4. Clear `session.current_preedit` (set to `null`).
5. Send `PreeditEnd` with the appropriate `reason` and `preedit_session_id` to
   all attached clients via the direct message queue.
6. Increment `session.preedit.session_id`.
7. Update `session.preedit.owner` (set to new owner or `null`).
8. If transferring to a new owner: process the new client's KeyEvent through the
   IME engine, update `session.current_preedit` from the new `ImeResult`, send
   `PreeditStart` to all clients.

Steps 2-3 are the critical buffer lifetime constraint. Violating this produces
use-after-free or garbage text.

### 8.2 Client-Triggered Procedures

**Disconnect** (socket read returns 0 or error):

1. Detect disconnect on the event loop.
2. If the disconnecting client is `session.preedit.owner`: execute §8.1 steps
   1-7 with `reason: "client_disconnected"`, owner set to `null`.
3. Process connection teardown.

**Session detach** (explicit `DetachSession` request):

1. If the detaching client is `session.preedit.owner`: execute §8.1 steps 1-7
   with `reason: "client_disconnected"`, owner set to `null`.
2. Process the detach normally.

Session detach reuses `"client_disconnected"` because from remaining clients'
perspective, the effect is identical.

**Eviction** (T=300s stale timeout):

1. If the evicted client is `session.preedit.owner`: execute §8.1 steps 1-7 with
   `reason: "client_evicted"`, owner set to `null`.
2. Call `removeClientSubscriptions(client_id)` to clean up silence subscriptions
   (§11.6 cleanup trigger 5).
3. Send `Disconnect` with `reason: stale_client` to the evicted client.
4. Tear down the connection.

The preedit commit (step 1) and subscription cleanup (step 2) happen before the
connection teardown (step 4).

### 8.3 State-Triggered Procedures

**Focus change** (intra-session pane switch):

1. Execute §8.1 steps 1-7 with `reason: "focus_changed"`, owner set to `null`.
2. Update `session.focused_pane` to the new pane.
3. Send `LayoutChanged` with the new focused pane to all clients.

The daemon commits preedit to the OLD `focused_pane`'s PTY (step 1) before
updating `focused_pane` (step 2), guaranteeing the correct PTY receives the
committed text.

**Pane close** (non-last pane):

1. Call `engine.reset()` to cancel the composition — do NOT commit to PTY (the
   PTY is being closed).
2. Clear `session.current_preedit` (set to `null`).
3. Clear `session.preedit.owner` (set to `null`).
4. Send `PreeditEnd` with `reason: "pane_closed"` to all clients.
5. Increment `session.preedit.session_id += 1` (after PreeditEnd, which carries
   the old session_id).
6. Proceed with the pane close sequence.

**Alternate screen switch**:

1. Execute §8.1 steps 1-7 with `reason: "committed"`, owner set to `null`.
2. Process the screen switch through the ghostty Terminal.
3. Send FrameUpdate with `frame_type=1` (I-frame), `screen=alternate`.

**Resize during active composition**:

1. Process the resize through the ghostty Terminal (`ioctl(TIOCSWINSZ)`,
   Terminal reflow).
2. The preedit text is unchanged; only cursor position changes due to reflow.
3. Re-overlay preedit via `overlayPreedit()` at export time using the updated
   cursor position from the resized Terminal's `ExportResult`.
4. Send FrameUpdate with `frame_type=1` (I-frame) — preedit cells are included
   at the updated position.

No PreeditEnd or PreeditUpdate is sent. The composition continues uninterrupted.

### 8.4 Input-Triggered Procedures

**Rapid keystroke bursts**:

1. Process all pending KeyEvents in order through the IME engine.
2. Coalesce intermediate preedit states — do not send intermediate
   `PreeditUpdate` messages for states superseded within the same frame
   interval.
3. Inject the final preedit text into frame cell data via `overlayPreedit()`.
4. Write the resulting frame to the ring buffer as a single frame.
5. Send one `PreeditUpdate` for the burst (final state only).

**Mouse click during composition**:

1. Execute §8.1 steps 1-7 with `reason: "committed"`, owner set to `null`.
2. Forward the mouse event to the terminal via `terminal.mousePress()`.

The preedit check occurs in the server layer before `terminal.mousePress()`.
`MouseScroll` and `MouseMove` events do NOT trigger preedit commit — only
`MouseButton` events do.

**InputMethodSwitch during active preedit**:

- If `commit_current=true`:
  1. Call `setActiveInputMethod(new_method)` — the IME flushes (commits) pending
     composition and switches atomically.
  2. Extract `committed_text` from the result (buffer lifetime constraint).
  3. Write `committed_text` to PTY.
  4. Send `PreeditEnd` with `reason: "committed"` to all clients.
  5. Send `InputMethodAck` to all attached clients.

- If `commit_current=false`:
  1. Call `engine.reset()` to discard the current composition.
  2. Clear `session.current_preedit` (set to `null`).
  3. Clear `session.preedit.owner` (set to `null`).
  4. Call `setActiveInputMethod(new_method)` to switch.
  5. Send `PreeditEnd` with `reason: "cancelled"` to all clients.
  6. Increment `session.preedit.session_id += 1` (after PreeditEnd, which
     carries the old session_id).
  7. Send `InputMethodAck` to all attached clients.

### 8.5 Error Recovery

**Invalid composition state** (should not occur with correctly implemented
Korean algorithms):

1. Log the error with full state dump (session_id, preedit.owner,
   current_preedit, engine internal state).
2. Commit whatever preedit text exists to PTY (best-effort).
3. Call `engine.reset()` to force composition state to `null`.
4. Clear `session.current_preedit` (set to `null`).
5. Clear `session.preedit.owner` (set to `null`).
6. Send `PreeditEnd` with `reason: "cancelled"` to all clients.
7. Optionally send a diagnostic notification to the composing client.

The goal is to return to a known-good state without crashing.

---

## From doc02 §4.3: Eager Activate/Deactivate on Session Focus Change

`deactivate()` scope is **per-session, not per-client**. The engine is
deactivated only when the last client detaches from (or switches away from) a
session — i.e., when the session's attached-client count drops to zero. A single
client detaching while other clients remain on the same session does NOT trigger
`deactivate()` on the shared engine; only that client's preedit ownership is
resolved (per
[doc04 §6.2](04-runtime-policies.md#62-ownership-rules-last-writer-wins) — the
departing client's in-progress composition is flushed to PTY via the preedit
ownership transfer mechanism).

When the daemon detects that a client is the last one leaving session A and is
switching to session B:

1. Immediately call `entry_a.session.ime_engine.deactivate()` — flushes any
   committed text to A's focused pane PTY, clears preedit.
2. If committed text returned: write to A's focused pane PTY via
   `write(pty_fd, committed_text)`.
3. If preedit changed: set `entry_a.session.current_preedit = null` and mark
   dirty to clear the overlay.
4. Then call `entry_b.session.ime_engine.activate()` — no-op for Korean.

The trigger is the **session becoming client-free** (attached-client count
reaches zero), not the individual `AttachSessionRequest` of a single client. For
a solo client switching sessions, the two conditions coincide. For multi-client
sessions, only the last departing client triggers `deactivate()`.

**Why per-session, not per-client**: The `ImeEngine` is a shared resource owned
by the session, not by any individual client. Calling `deactivate()` on a shared
engine when one of several clients detaches would discard in-progress
composition belonging to the remaining clients — violating the last-writer-wins
preedit model
([doc04 §6.2](04-runtime-policies.md#62-ownership-rules-last-writer-wins)). The
per-session engine's `deactivate()` semantics ("end this engine's active period,
perform engine-specific cleanup") only make sense when no client remains to
interact with the session.

**Why eager, not lazy**: Lazy deactivation creates deferred routing bugs.
Concrete scenario: user composes Korean text in Session A (solo client),
switches to Session B, closes Session A's pane from B, then types in B. Lazy
deactivation would attempt to flush committed text to a pane that no longer
exists. Eager deactivation on last-client-departure flushes while the pane is
still alive.

**Zero cost when not composing**: `deactivate()` on an empty engine returns
`ImeResult{}` (all null/false fields). `activate()` is a no-op for Korean. The
path is uniform regardless of composition state.

**Language preservation**: The engine's `active_input_method` is NOT changed by
deactivate/activate. Users expect that switching between tabs and coming back
preserves their input mode (e.g., still in Korean 2-set). ghostty's Surface has
zero language state — the language indicator is derived from the engine by the
daemon.

## From doc02 §4.4: Intra-Session Pane Focus Change

When the user changes focus between panes within the same session, the daemon
flushes the engine and routes the result to the old pane before switching focus:

1. `engine.flush()` -> ImeResult with committed text (if composing) or empty (if
   not).
2. If `committed_text` present: write UTF-8 to old pane's PTY via
   `write(pty_fd, committed_text)`.
3. If `preedit_changed`: set `session.current_preedit = null` and mark dirty to
   clear the overlay.
4. Send `PreeditEnd(pane=old, reason="focus_changed")` to all clients (immediate
   delivery, bypasses coalescing — per the preedit bypass rules defined in the
   protocol CJK preedit docs).
5. Update `session.focused_pane` to new pane. Subsequent `processKey()` results
   route to the new pane.

**Edge case — engine already empty**: `flush()` returns `ImeResult{}` (all
null/false). The daemon skips ghostty calls. The code path is uniform regardless
of composition state.

**Key invariant**: The daemon MUST consume the `ImeResult` (process committed
text and update preedit) before making any subsequent call to the same engine
instance. The engine's internal buffers are overwritten by the next mutating
call (see §4.6).

**No composition restoration**: When focus returns to a previously-focused pane,
the engine starts with empty composition. libhangul has no snapshot/restore API,
and users don't expect to resume mid-syllable after switching panes. This
matches ibus-hangul and fcitx5-hangul, which both flush on focus-out with no
restoration on focus-in.

**Source**: Per-session engine architecture design resolutions in the
`libitshell3-ime` interface-contract docs (Resolution 2).
