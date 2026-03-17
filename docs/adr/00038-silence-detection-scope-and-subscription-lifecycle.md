# 00038. Silence Detection Scope and Subscription Lifecycle

- Date: 2026-03-17
- Status: Accepted

## Context

During design of Doc 06 §5.8 (SilenceDetected) and §6 (Subscription System), two
questions were left open:

1. **Silence scope**: Should SilenceDetected fire for any pane that has been
   silent for the configured duration, or only for panes that had recent output
   (activity-then-silence pattern)?

2. **Subscription lifecycle**: The protocol defines explicit Subscribe (0x0810)
   and Unsubscribe (0x0812) messages, but does not specify what happens to
   subscriptions when a client disconnects, detaches, or is evicted without
   sending Unsubscribe.

## Decision

### 1. Silence Detection Scope: Activity-Then-Silence Only

SilenceDetected fires only after a pane has produced at least one byte of PTY
output. The timer mechanism is:

- **Arm**: on the first PTY output byte received for a pane (only if at least
  one client is subscribed to SilenceDetected for that pane).
- **Reset**: on each subsequent PTY output byte (cancel and re-arm for the full
  `silence_threshold_ms` duration).
- **Fire**: when the timer expires without being reset. Send SilenceDetected to
  all subscribed clients for that pane, then disarm the timer.
- **Re-arm**: only when the next PTY output arrives (not immediately after
  firing).

`silence_threshold_ms` is clamped to [1000, 3600000] by the server. Values
outside this range are silently adjusted; no error is returned to the client.

Panes with no SilenceDetected subscribers MUST NOT arm a timer. This matches the
tmux `monitor-silence` design (countdown timer reset on output, armed on first
output) and avoids spurious notifications for idle panes that have never
produced output.

### 2. Subscription Lifecycle: Connection-Scoped, Automatic Cleanup

Subscriptions are scoped to a connection. The daemon automatically cleans up all
subscriptions for a connection — and cancels any timers for panes that no longer
have remaining subscribers — when any of the following occurs:

- Client sends Unsubscribe (0x0812) explicitly.
- Client sends Disconnect (0x0005) (graceful disconnect).
- Connection timeout: no message received for 90 seconds.
- Session detach: client detaches from a session; pane-level subscriptions for
  that session are released.
- Client eviction: PausePane escalation reaches the eviction threshold (300s),
  triggering a forced disconnect.

**Server behavior** (normative):

- Maintain a per-pane countdown timer. Duration is `silence_threshold_ms` from
  the client's Subscribe config (default 30000 ms).
- Arm, reset, and fire the timer from the PTY read path.
- On timer expiry, deliver SilenceDetected to all subscribed clients for that
  pane, then disarm the timer until next output arrives.
- On any subscription cleanup event listed above, cancel the pane timer if no
  remaining subscribers exist.

**Client behavior** (normative):

- Clients that want SilenceDetected notifications MUST send Subscribe (0x0810)
  with SilenceDetected (bit 6) set and `silence_threshold_ms` configured.
- Clients MAY send Unsubscribe (0x0812) to stop notifications explicitly.
- Clients do NOT need to unsubscribe before disconnecting or detaching; the
  daemon performs automatic cleanup.

## Consequences

- No wire protocol change required. SilenceDetected (0x0806), Subscribe
  (0x0810), and Unsubscribe (0x0812) message definitions are unchanged.
- The daemon must implement per-pane countdown timers and subscription lifecycle
  cleanup covering all five termination cases above.
