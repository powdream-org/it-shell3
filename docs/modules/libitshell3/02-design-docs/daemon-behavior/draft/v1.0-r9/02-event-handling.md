# Runtime Event Handling

- **Date**: 2026-03-24
- **Scope**: Cross-cutting ordering invariants, SIGCHLD two-phase model, pane
  exit cascade, session destroy cascade, client connect/disconnect, session
  rename broadcast, and IME-related event handling procedures

---

## 1. Cross-Cutting Invariants

### 1.1 Response-Before-Notification

**Invariant**: For any client request that produces both a response to the
requester and notifications to other clients, the response MUST be sent before
the notifications.

This rule is universal and applies to every current and future
request/notification pair. It guarantees that the requesting client learns the
outcome of its own action before any peer client learns about the side effects.

**Exemption — PreeditEnd**: PreeditEnd is an IME composition-resolution preamble,
not a notification under this rule's scope. When a client request requires
resolving active preedit (e.g., DestroySessionRequest, NavigatePaneRequest with
active composition), PreeditEnd precedes the response as an IME cleanup step.
This is consistent with the three-phase model: Phase 1 (IME cleanup via
PreeditEnd) → Phase 2 (response to requester) → Phase 3 (notifications to
peers).

**Known instances:**

| Request               | Response               | Notification(s)    |
| --------------------- | ---------------------- | ------------------ |
| NavigatePaneRequest   | NavigatePaneResponse   | LayoutChanged      |
| WindowResize          | WindowResizeAck        | LayoutChanged      |
| ClosePaneRequest      | ClosePaneResponse      | LayoutChanged      |
| DestroySessionRequest | DestroySessionResponse | SessionListChanged |
| RenameSessionRequest  | RenameSessionResponse  | SessionListChanged |
| SplitPaneRequest      | SplitPaneResponse      | LayoutChanged      |
| CreateSessionRequest  | CreateSessionResponse  | SessionListChanged |

**Verification**: For each request type, capture the requester's socket receive
order. The response message MUST appear before any notification triggered by the
same request.

### 1.2 Single Event-Loop-Iteration Atomicity

All steps within a single event handler execute within one iteration of the
kqueue event loop. No `kevent64()` call intervenes between steps. This is
structurally guaranteed by the single-threaded event loop — not a runtime
assertion.

**Consequence**: Unix socket `SOCK_STREAM` guarantees in-order delivery.
Messages sent within one event handler iteration arrive at each client in the
order they were enqueued.

### 1.3 EVFILT_SIGNAL Before EVFILT_READ Priority

When a single `kevent64()` call returns both `EVFILT_SIGNAL` (SIGCHLD) and
`EVFILT_READ` (PTY data) events, `EVFILT_SIGNAL` MUST be processed first. This
ensures the `PANE_EXITED` flag is set before the PTY read handler checks for it.

| # | Constraint                                            | Verification                                                                |
| - | ----------------------------------------------------- | --------------------------------------------------------------------------- |
| 1 | SIGCHLD event processed before PTY read in same batch | After SIGCHLD + PTY EOF in same kevent, pane transitions to destroyed state |

---

## 2. Child Process Exit (Two-Phase Model)

Child process exit handling uses a two-phase model: mark the pane as exited,
allow remaining PTY data to drain, then execute the destroy cascade.

### 2.1 Phase 1 — SIGCHLD (Reap and Mark)

**Trigger**: `EVFILT_SIGNAL` fires for SIGCHLD.

**Preconditions**: At least one child process has exited.

**Ordering constraints:**

| # | Constraint                                                          | Verification                                                                         |
| - | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| 1 | All exited children reaped in one pass (coalesced SIGCHLD handling) | After SIGCHLD, no zombie children remain for the reaped PIDs                         |
| 2 | `PANE_EXITED` flag set before cascade check                         | If PTY EOF already received, cascade triggers immediately within the SIGCHLD handler |

**Observable effects**: None. Phase 1 is daemon-internal — no wire messages are
sent.

**Invariants:**

- MUST reap with `waitpid(-1, WNOHANG)` in a loop (multiple SIGCHLDs coalesce)
- MUST NOT block on `waitpid`

### 2.2 Phase 2 — PTY Drain

**Trigger**: `EVFILT_READ` fires on a pane's `pty_fd`.

**Preconditions**: Pane slot is valid, PTY fd is open.

**Ordering constraints:**

| # | Constraint                                                   | Verification                                                                               |
| - | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| 1 | All remaining PTY data processed via vtStream before cascade | Final frame sent to clients contains the child's last output                               |
| 2 | `PTY_EOF` flag set only on `EV_EOF` from kqueue              | Pane does not enter cascade while PTY slave is still open and producing data               |
| 3 | Cascade triggers when both `PANE_EXITED` and `PTY_EOF` set   | Either flag can arrive first; cascade fires on the second flag regardless of arrival order |

**Observable effects**: FrameUpdate messages may be sent during the drain
(normal coalescing applies to PTY output processed during Phase 2).

**Safety timeout**: When `PANE_EXITED` is set without `PTY_EOF`, a 5-second
`EVFILT_TIMER` fallback is armed. If `EV_EOF` never arrives (e.g., a background
process inherited the PTY slave fd), the timeout fires and triggers the cascade
unconditionally.

| # | Constraint                                               | Verification                                                           |
| - | -------------------------------------------------------- | ---------------------------------------------------------------------- |
| 4 | Safety timeout triggers cascade if PTY EOF never arrives | Pane with `PANE_EXITED` is destroyed within 5 seconds even without EOF |

**Invariants:**

- The dual-flag model (`PANE_EXITED` + `PTY_EOF`) MUST handle both arrival
  orders without extra syscalls
- MUST NOT destroy the pane until both flags are set (or safety timeout fires)

---

## 3. Pane Exit Cascade

**Trigger**: Both `PANE_EXITED` and `PTY_EOF` flags are set on a pane
(order-independent), OR the 5-second safety timeout fires with `PANE_EXITED`
set.

**Preconditions**: Pane slot is valid, PTY fd is open, Terminal state exists.

### 3.1 Ordering Constraints (Wire-Observable)

| # | Constraint                                        | Verification                                                    |
| - | ------------------------------------------------- | --------------------------------------------------------------- |
| 1 | Pending frames flushed BEFORE PaneMetadataChanged | No PaneMetadataChanged in send queue while pane has dirty state |
| 2 | PreeditEnd BEFORE LayoutChanged                   | No LayoutChanged in send queue while preedit is active          |
| 3 | PaneMetadataChanged BEFORE LayoutChanged          | Exit status visible before pane disappears from layout          |
| 4 | LayoutChanged carries correct focus               | LayoutChanged.focused_pane_id != exited pane                    |
| 5 | PreeditEnd carries old preedit session_id         | PreeditEnd.preedit_session_id matches the active composition    |

Internal ordering constraints (IME cleanup before PTY close, Terminal.deinit()
ordering, slot atomicity) are implementation concerns — they will be enforced as
debug assertions in code.

### 3.2 Observable Effects

Wire messages to attached clients, in order:

**Common prefix:**

1. FrameUpdate (final frame for dying pane) [if dirty]
2. PaneMetadataChanged(is_running=false, exit_status=N)
3. ProcessExited(exit_status=N) [if subscribed]

**Conditional suffix — non-last pane:**

4a. PreeditEnd(reason="pane_closed") [if focused pane with active composition]
5a. LayoutChanged(new_focus=X, tree=updated)

**Conditional suffix — last pane (session auto-destroy):**

4b. PreeditEnd(reason="session_destroyed") [if focused pane with active
composition]
5b. SessionListChanged(event="destroyed", session_id=N) — broadcast to ALL
connected clients
6b. DetachSessionResponse(reason="session_destroyed") — to each attached client
(no requester exists in the auto-destroy path)

### 3.3 Invariants

- MUST NOT send LayoutChanged with stale focus (exited pane as focused_pane_id)
- MUST NOT leave pane slot in non-null state after cascade completes
- Preedit `session_id` MUST increment after PreeditEnd (except
  session-destruction paths where the session is freed)
- PreeditEnd reason MUST be `"pane_closed"` for non-last pane,
  `"session_destroyed"` for last pane

### 3.4 Conditional Branches

| Condition          | IME behavior                                                     | Cascade suffix              |
| ------------------ | ---------------------------------------------------------------- | --------------------------- |
| Non-focused pane   | IME cleanup skipped entirely                                     | LayoutChanged               |
| Focused, non-last  | `engine.reset()` — discard composition (PTY is dead)             | LayoutChanged               |
| Focused, last pane | `engine.deactivate()` — flush committed text to PTY before close | SessionListChanged + detach |

### 3.5 Last-Pane Session Auto-Destroy

When the last pane in a session exits, the session is auto-destroyed. There is
no requesting client in this path — the cascade is triggered by SIGCHLD, not by
a client request.

**Ordering constraints (wire-observable):**

| # | Constraint                                                 | Verification                                                  |
| - | ---------------------------------------------------------- | ------------------------------------------------------------- |
| 1 | All pane-level messages complete before SessionListChanged | PaneMetadataChanged and PreeditEnd precede SessionListChanged |
| 2 | SessionListChanged broadcast before force-detach           | Clients see the session list update before their own detach   |
| 3 | No LayoutChanged in last-pane path                         | Session is destroyed, not relaid out                          |

**Invariant**: If no sessions remain after auto-destroy, the daemon initiates
graceful shutdown (see `01-daemon-lifecycle.md`).

---

## 4. Session Destroy Cascade (Client-Requested)

**Trigger**: Client sends `DestroySessionRequest`.

**Preconditions**: Session exists, requesting client is connected.

### 4.1 Ordering Constraints (Wire-Observable)

| # | Constraint                                                       | Verification                                                         |
| - | ---------------------------------------------------------------- | -------------------------------------------------------------------- |
| 1 | PreeditEnd BEFORE DestroySessionResponse                         | Preedit resolved before requester receives success                   |
| 2 | DestroySessionResponse BEFORE SessionListChanged                 | Response-before-notification rule (Section 1.1)                      |
| 3 | SessionListChanged BEFORE DetachSessionResponse to other clients | Peers see session list update before their forced detach             |
| 4 | All messages sent within one event loop iteration                | No interleaving with other events between response and notifications |
| 5 | Session state freed AFTER all notifications sent                 | Notification construction may reference session fields (name, id)    |

Internal ordering constraints (IME deactivate before PTY close, per-pane
resource cleanup ordering) are implementation concerns — they will be enforced
as debug assertions in code.

### 4.2 Observable Effects

Wire messages in order:

1. PreeditEnd(reason="session_destroyed") — to all attached clients [if
   composition active]
2. DestroySessionResponse(status=0) — to requester
3. SessionListChanged(event="destroyed", session_id=N) — broadcast to ALL
   connected clients
4. DetachSessionResponse(reason="session_destroyed") — to each other attached
   client (not the requester)
5. ClientDetached(client_id=C) — to requester, for each detached peer client

### 4.3 Invariants

- IME `deactivate()` is unconditional — if PTY is dead, the write fails silently
  (best-effort)
- `engine.deactivate()` MUST be called before any PTY fd is closed (flush may
  write to PTY)
- The requester does NOT receive DetachSessionResponse — it already knows the
  session is destroyed from DestroySessionResponse
- `kill(child_pid, SIGHUP)` MUST be sent to each pane's child process
  (consistent with graceful shutdown and ClosePaneRequest)

### 4.4 Shared Teardown With Pane Exit Cascade

The last-pane SIGCHLD path (Section 3.5) and the explicit DestroySessionRequest
path (this section) share the same resource cleanup but differ in notification
ordering:

| Aspect                   | Pane exit (last pane, SIGCHLD)                    | DestroySessionRequest           |
| ------------------------ | ------------------------------------------------- | ------------------------------- |
| Requester                | None                                              | Client that sent the request    |
| Response message         | None                                              | DestroySessionResponse          |
| SessionListChanged order | First (no response to send before it)             | After DestroySessionResponse    |
| DetachSessionResponse    | Sent to each attached client (no requester exists) | Sent to each non-requester client |
| ClientDetached           | Not sent (no requester to notify)                 | Sent to requester for each peer |

---

## 5. New Client Connection

**Trigger**: `EVFILT_READ` fires on `listen_fd`.

**Preconditions**: Daemon is in event loop, listener is active.

### 5.1 Ordering Constraints (Wire-Observable)

| # | Constraint                                            | Verification                                                |
| - | ----------------------------------------------------- | ----------------------------------------------------------- |
| 1 | UID verification before any protocol message exchange | Connections from non-matching UIDs are rejected at accept   |
| 2 | Client fd registered with kqueue before ServerHello   | No events missed between accept and event loop registration |
| 3 | client_id is monotonically increasing, never reused   | Each new connection receives a strictly greater client_id   |

### 5.2 Observable Effects

No wire messages are sent during connection acceptance itself. The first wire
interaction is the ClientHello/ServerHello handshake, which is initiated by the
client.

### 5.3 Policy Values

| Parameter      | Value   | Description                |
| -------------- | ------- | -------------------------- |
| SO_SNDBUF      | 256 KiB | Socket send buffer size    |
| SO_RCVBUF      | 256 KiB | Socket receive buffer size |
| Socket mode    | 0600    | Owner-only access          |
| Directory mode | 0700    | Owner-only traversal       |

### 5.4 SSH Tunnel Trust Model

When a client connects through an SSH tunnel, `getpeereid()` returns sshd's UID.
The daemon accepts this because SSH has already authenticated the user at the
transport layer. No protocol-level authentication exists — the
ClientHello/ServerHello handshake is identical for local and tunneled
connections.

---

## 6. Client Disconnect (Unexpected)

**Trigger**: `conn.recv()` returns `.peer_closed` or `.err`.

**Preconditions**: Client is in any state (handshaking, ready, operating).

### 6.1 Ordering Constraints (Wire-Observable)

| # | Constraint                                            | Verification                                                                |
| - | ----------------------------------------------------- | --------------------------------------------------------------------------- |
| 1 | Preedit ownership resolved BEFORE connection teardown | If disconnecting client owned preedit, PreeditEnd sent to remaining clients |
| 2 | PreeditEnd BEFORE silence subscription cleanup        | Remaining clients see preedit end before subscription state changes         |
| 3 | Committed text written to PTY BEFORE PreeditEnd       | Preedit text is preserved (best-effort) in the terminal                     |
| 4 | preedit.session_id incremented AFTER PreeditEnd sent  | PreeditEnd carries the old session_id                                       |

### 6.2 Observable Effects

Wire messages to remaining attached clients (if disconnecting client owned
preedit):

1. PreeditEnd(reason="client_disconnected", preedit_session_id=N)

If the disconnecting client was not the preedit owner, no preedit-related
messages are sent.

### 6.3 Invariants

- Client disconnect MUST NOT affect session lifecycle — sessions persist until
  panes exit or daemon shuts down
- The DISCONNECTING state is bypassed — peer has already closed, no drain is
  possible
- Per-client resources (preedit ownership, silence subscriptions, ring cursors)
  MUST be cleaned up before ClientState deallocation

### 6.4 Session Detach (Graceful)

When a client sends `DetachSessionRequest`, preedit ownership resolution follows
the same procedure as unexpected disconnect: if the detaching client owns the
preedit, commit to PTY and send PreeditEnd with reason `"client_disconnected"`.

The reason string `"client_disconnected"` is reused because from remaining
clients' perspective, the effect is identical.

**Ordering constraints:**

| # | Constraint                                                 | Verification                                                         |
| - | ---------------------------------------------------------- | -------------------------------------------------------------------- |
| 1 | Preedit resolved BEFORE DetachSessionResponse              | PreeditEnd precedes the detach acknowledgment                        |
| 2 | Silence subscriptions cleaned for detached session's panes | No stale subscriptions remain for panes the client can no longer see |

---

## 7. Session Rename

**Trigger**: Client sends `RenameSessionRequest`.

**Preconditions**: Session exists, new name is not already in use.

### 7.1 Ordering Constraints (Wire-Observable)

| # | Constraint                                      | Verification                                     |
| - | ----------------------------------------------- | ------------------------------------------------ |
| 1 | State update BEFORE response                    | Session name is updated before response is sent  |
| 2 | RenameSessionResponse BEFORE SessionListChanged | Response-before-notification rule (Section 1.1)  |
| 3 | SessionListChanged carries the new name         | All clients see consistent name in the broadcast |

### 7.2 Observable Effects

Wire messages in order:

1. RenameSessionResponse(status=0) — to requester
2. SessionListChanged(event="renamed", session_id=N, name=new_name) — broadcast
   to ALL connected clients

### 7.3 Invariants

- No IME or ghostty implications — session name is daemon-level metadata
- Duplicate name MUST be rejected with an error response (no notification sent)

---

## 8. IME Event Handling Procedures

This section specifies wire-observable ordering for IME-related events. Internal
ordering constraints (buffer lifetime, engine call sequences) are implementation
concerns — they will be enforced as debug assertions in code.

### 8.1 Preedit Ownership Transfer

**Trigger**: Client B sends a composing KeyEvent while Client A owns the active
preedit on the same session.

**Preconditions**: Client A is `preedit.owner`, composition is active.

**Ordering constraints:**

| # | Constraint                                                          | Verification                                                              |
| - | ------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| 1 | PreeditEnd (for Client A's composition) BEFORE PreeditStart (for B) | No overlapping preedit sessions on the wire                               |
| 2 | Committed text in terminal BEFORE PreeditEnd sent                   | Terminal shows committed text when clients process PreeditEnd             |
| 3 | preedit.session_id increments between End and Start                 | PreeditStart carries a strictly greater session_id than the preceding End |

**Observable effects:**

1. PreeditEnd(reason="replaced_by_other_client", preedit_session_id=N) — to all
   attached clients
2. PreeditStart(owner=client_B, preedit_session_id=N+1) — to all attached
   clients

### 8.2 Intra-Session Focus Change

**Trigger**: Focus moves from pane A to pane B within the same session (via
NavigatePaneRequest or equivalent).

**Preconditions**: Session has active composition on pane A's focused position.

**Ordering constraints:**

| # | Constraint                                                   | Verification                                            |
| - | ------------------------------------------------------------ | ------------------------------------------------------- |
| 1 | Committed text written to old pane's PTY BEFORE focus update | Terminal on pane A shows the committed text             |
| 2 | PreeditEnd BEFORE NavigatePaneResponse                       | Preedit resolved before navigation acknowledged         |
| 3 | NavigatePaneResponse BEFORE LayoutChanged                    | Response-before-notification rule (Section 1.1)         |
| 4 | preedit.session_id incremented AFTER PreeditEnd              | PreeditEnd carries the old session_id                   |
| 5 | preedit.owner cleared AFTER PreeditEnd                       | Owner field reflects active state at time of PreeditEnd |

**Observable effects** (when composition is active):

1. PreeditEnd(reason="focus_changed", preedit_session_id=N) — to all attached
   clients
2. NavigatePaneResponse — to requester
3. LayoutChanged(focused_pane_id=pane_B) — to all attached clients

When no composition is active, only NavigatePaneResponse and LayoutChanged are
sent (preedit messages are skipped).

**Invariant**: No composition restoration — when focus returns to a previously
focused pane, the engine starts with empty composition. This matches ibus-hangul
and fcitx5-hangul behavior.

### 8.3 Inter-Session Switch (Attach to Different Session)

**Trigger**: Client sends `AttachSessionRequest` for a different session while
attached to the current session.

**Preconditions**: Client is in OPERATING state, attached to session A.

**Ordering constraints:**

| # | Constraint                                                                          | Verification                                                          |
| - | ----------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| 1 | Preedit resolved on session A BEFORE attach to session B                            | PreeditEnd for session A precedes AttachSessionResponse for session B |
| 2 | `deactivate()` called only when last client leaves session A                        | Other clients on session A do not see engine disruption               |
| 3 | `activate()` called on session B engine AFTER deactivate on A (if last client on A) | Engine lifecycle is clean                                             |

**Deactivation scope**: `deactivate()` is per-session, not per-client. It fires
only when the session's attached-client count drops to zero. A single client
detaching while others remain does NOT trigger `deactivate()` on the shared
engine — only the departing client's preedit ownership is resolved.

**Observable effects** (when departing client owns preedit on session A):

1. PreeditEnd(reason="client_disconnected") — to all clients attached to session
   A
2. AttachSessionResponse — to the switching client

### 8.4 Input Method Switch During Active Preedit

**Trigger**: Client sends `InputMethodSwitch` (0x0404) while composition is
active.

**Preconditions**: Active composition exists on the session.

#### commit_current=true Path

**Ordering constraints:**

| # | Constraint                                      | Verification                                                  |
| - | ----------------------------------------------- | ------------------------------------------------------------- |
| 1 | Committed text written to PTY BEFORE PreeditEnd | Terminal shows committed text when clients process PreeditEnd |
| 2 | PreeditEnd BEFORE InputMethodAck                | Composition resolved before method switch acknowledged        |
| 3 | preedit.owner cleared AFTER PreeditEnd          | Owner field reflects active state at time of PreeditEnd       |
| 4 | preedit.session_id incremented AFTER PreeditEnd | PreeditEnd carries the old session_id                         |

**Observable effects:**

1. PreeditEnd(reason="committed", preedit_session_id=N) — to all attached
   clients
2. InputMethodAck(active_input_method=new_method) — to all attached clients

#### commit_current=false Path

**Ordering constraints:**

| # | Constraint                                      | Verification                                            |
| - | ----------------------------------------------- | ------------------------------------------------------- |
| 1 | PreeditEnd BEFORE InputMethodAck                | Composition cancelled before method switch acknowledged |
| 2 | preedit.session_id incremented AFTER PreeditEnd | PreeditEnd carries the old session_id                   |

**Observable effects:**

1. PreeditEnd(reason="cancelled", preedit_session_id=N) — to all attached
   clients
2. InputMethodAck(active_input_method=new_method) — to all attached clients

### 8.5 Mouse Click During Composition

**Trigger**: Client sends a MouseButton event while composition is active.

**Preconditions**: Active composition exists, mouse reporting is enabled in the
terminal.

**Ordering constraints:**

| # | Constraint                                                 | Verification                                                   |
| - | ---------------------------------------------------------- | -------------------------------------------------------------- |
| 1 | Committed text written to PTY BEFORE mouse event forwarded | Terminal shows committed text before processing mouse action   |
| 2 | PreeditEnd sent to clients BEFORE mouse-triggered output   | Clients see preedit end before any mouse-induced frame changes |
| 3 | preedit.owner cleared AFTER PreeditEnd                     | Owner field reflects active state at time of PreeditEnd        |
| 4 | preedit.session_id incremented AFTER PreeditEnd            | PreeditEnd carries the old session_id                          |

**Observable effects:**

1. PreeditEnd(reason="committed") — to all attached clients
2. Subsequent FrameUpdate reflecting mouse action (normal coalescing)

**Invariant**: Only MouseButton events trigger preedit commit. MouseScroll and
MouseMove do NOT.

### 8.6 Alternate Screen Switch During Composition

**Trigger**: Application switches from primary to alternate screen (e.g., vim
launches) while composition is active.

**Ordering constraints:**

| # | Constraint                                                   | Verification                                                   |
| - | ------------------------------------------------------------ | -------------------------------------------------------------- |
| 1 | PreeditEnd BEFORE FrameUpdate with screen=alternate          | Preedit resolved before alternate screen content is delivered  |
| 2 | Committed text written to PTY BEFORE screen switch processed | Terminal has committed text before alternate screen takes over |

**Observable effects:**

1. PreeditEnd(reason="committed") — to all attached clients
2. FrameUpdate(frame_type=I-frame, screen=alternate)

### 8.7 Client Eviction During Composition

**Trigger**: Stale client eviction at T=300s while the evicted client owns
active preedit.

**Ordering constraints:**

| # | Constraint                                              | Verification                                                           |
| - | ------------------------------------------------------- | ---------------------------------------------------------------------- |
| 1 | Preedit committed to PTY BEFORE PreeditEnd              | Terminal shows committed text                                          |
| 2 | PreeditEnd BEFORE Disconnect to evicted client          | Remaining clients see preedit resolution before the eviction completes |
| 3 | Silence subscription cleanup BEFORE connection teardown | No stale subscriptions remain                                          |

**Observable effects** (to remaining attached clients):

1. PreeditEnd(reason="client_evicted", preedit_session_id=N)

**Observable effects** (to evicted client):

2. Disconnect(reason=stale_client)

### 8.8 Preedit Inactivity Timeout

**Trigger**: No input from the preedit owner for 30 seconds.

**Ordering constraints:**

| # | Constraint                                      | Verification                                            |
| - | ----------------------------------------------- | ------------------------------------------------------- |
| 1 | Committed text written to PTY BEFORE PreeditEnd | Terminal shows committed text                           |
| 2 | preedit.owner cleared AFTER PreeditEnd          | Owner field reflects active state at time of PreeditEnd |

**Observable effects:**

1. PreeditEnd(reason="timeout", preedit_session_id=N) — to all attached clients

**Policy values:**

| Parameter          | Value      |
| ------------------ | ---------- |
| Inactivity timeout | 30 seconds |

### 8.9 Rapid Keystroke Burst Coalescing

**Trigger**: Multiple KeyEvents arrive within a single coalescing interval.

**Ordering constraints:**

| # | Constraint                                                            | Verification                                                             |
| - | --------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| 1 | All KeyEvents processed in arrival order through the IME engine       | Final preedit state is deterministic regardless of batching              |
| 2 | Only final preedit state sent as PreeditUpdate (intermediate skipped) | At most one PreeditUpdate per coalescing interval per pane               |
| 3 | Committed text from each keystroke written to PTY in order            | PTY receives committed text in the same order as the original keystrokes |

**Observable effects:**

1. One PreeditUpdate per coalescing interval (final state only)
2. One FrameUpdate per coalescing interval (final overlaid preedit)

**Invariant**: Preedit frames are never delayed by batching with PTY output
("immediate first, batch rest" rule — preedit change triggers immediate frame
delivery at Tier 0).

### 8.10 Error Recovery

**Trigger**: Invalid composition state detected (should not occur with correct
Korean algorithms).

**Observable effects:**

1. PreeditEnd(reason="cancelled") — to all attached clients

**Invariant**: The daemon MUST return to a known-good state (no active
composition, no preedit owner) without crashing. Diagnostic logging is
daemon-internal.

---

## 9. Input Processing Priority

The event loop processes events from a single `kevent64()` call in a defined
priority order:

| Priority | Event source  | Rationale                                         |
| -------- | ------------- | ------------------------------------------------- |
| 1        | EVFILT_SIGNAL | SIGCHLD sets flags before PTY reads check them    |
| 2        | EVFILT_TIMER  | Coalescing timers, safety timeouts, health timers |
| 3        | EVFILT_READ   | PTY output, client messages, new connections      |
| 4        | EVFILT_WRITE  | Drain outbound data to clients                    |

The concrete 5-tier input processing priority table (within EVFILT_READ client
message handling) is defined in the daemon behavior docs
(`03-policies-and-procedures.md` Section 6).
