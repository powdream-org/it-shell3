# tmux Research: Multi-Client Resize and Client Health Model

**Author**: tmux-expert  
**Date**: 2025-03-05  
**Source**: `~/dev/git/references/tmux/` (tmux HEAD)

---

## Part 1: Multi-Client Window Sizing

### 1.1 The `window-size` Option

**File**: `options-table.c:1447-1456`, `tmux.h:1356-1359`

tmux provides four window sizing policies via the `window-size` per-window option:

```c
// tmux.h:1356-1359
#define WINDOW_SIZE_LARGEST  0
#define WINDOW_SIZE_SMALLEST 1
#define WINDOW_SIZE_MANUAL   2
#define WINDOW_SIZE_LATEST   3
```

```c
// options-table.c:1447-1456
{ .name = "window-size",
  .type = OPTIONS_TABLE_CHOICE,
  .scope = OPTIONS_TABLE_WINDOW,
  .choices = options_table_window_size_list,
  .default_num = WINDOW_SIZE_LATEST,
  .text = "How window size is calculated. "
          "'latest' uses the size of the most recently used client, "
          "'largest' the largest client, 'smallest' the smallest "
          "client and 'manual' a size set by the 'resize-window' "
          "command."
```

**Default is `latest`** (not `smallest`). This is a critical design insight -- tmux's default avoids the "smallest client wins" problem entirely.

Policy semantics:

| Policy | Behavior |
|--------|----------|
| `smallest` | Window sized to the smallest attached client viewing the window. Classic tmux behavior (was the pre-3.1 default). |
| `largest` | Window sized to the largest attached client viewing the window. Clients with smaller terminals see a partial view. |
| `latest` | Window sized to the most recently active client (by key/resize event). Other clients see offset view. **Default since tmux 3.1.** |
| `manual` | Window size is set explicitly via `resize-window` command. Not affected by client sizes. |

### 1.2 The `aggressive-resize` Option

**File**: `options-table.c:1057-1064`, `resize.c:337-350`

```c
// options-table.c:1057-1064
{ .name = "aggressive-resize",
  .type = OPTIONS_TABLE_FLAG,
  .scope = OPTIONS_TABLE_WINDOW,
  .default_num = 0,
  .text = "When 'window-size' is 'smallest', whether the maximum size "
          "of a window is the smallest attached session where it is "
          "the current window ('on') or the smallest session it is "
          "linked to ('off')."
},
```

The `aggressive-resize` flag only applies to `smallest` (and effectively `largest`) mode. When enabled:

```c
// resize.c:337-350
static int
recalculate_size_skip_client(struct client *loop, __unused int type,
    int current, __unused struct session *s, struct window *w)
{
    if (loop->session->curw == NULL)
        return (1);
    if (current)
        return (loop->session->curw->window != w);
    return (session_has(loop->session, w) == 0);
}
```

- `aggressive-resize off` (default): All clients attached to sessions that *contain* the window contribute to sizing.
- `aggressive-resize on`: Only clients whose *current window* is this window contribute. Clients viewing other windows in the same session are ignored.

### 1.3 Client Exclusion from Size Calculation

**File**: `resize.c:68-96`

tmux actively excludes certain clients from the sizing calculation via `ignore_client_size()`:

```c
// resize.c:68-96
static int
ignore_client_size(struct client *c)
{
    struct client *loop;

    if (c->session == NULL)
        return (1);
    if (c->flags & CLIENT_NOSIZEFLAGS)
        return (1);
    if (c->flags & CLIENT_IGNORESIZE) {
        /* Ignore flagged clients if there are any attached clients
         * that aren't flagged. */
        TAILQ_FOREACH (loop, &clients, entry) {
            if (loop->session == NULL)
                continue;
            if (loop->flags & CLIENT_NOSIZEFLAGS)
                continue;
            if (~loop->flags & CLIENT_IGNORESIZE)
                return (1);
        }
    }
    if ((c->flags & CLIENT_CONTROL) &&
        (~c->flags & CLIENT_SIZECHANGED) &&
        (~c->flags & CLIENT_WINDOWSIZECHANGED))
        return (1);
    return (0);
}
```

Clients excluded from sizing:
- **No session** (`c->session == NULL`) -- not attached
- **`CLIENT_NOSIZEFLAGS`** -- dead, suspended, or exiting clients:
  ```c
  // tmux.h:2055-2058
  #define CLIENT_NOSIZEFLAGS  \
      (CLIENT_DEAD|           \
       CLIENT_SUSPENDED|      \
       CLIENT_EXIT)
  ```
- **`CLIENT_IGNORESIZE`** -- explicitly flagged to be ignored (e.g., via `refresh-client -A`)
- **Control clients** (`CLIENT_CONTROL`) that have not yet reported their size

**Key finding for libitshell3**: tmux **does** exclude dead/suspended/exiting clients from size calculations. This directly addresses Issue 2a -- unresponsive clients' stale dimensions are excluded because dead clients get `CLIENT_DEAD` and suspended clients get `CLIENT_SUSPENDED`, both part of `CLIENT_NOSIZEFLAGS`.

### 1.4 The `latest` Client Tracking

**File**: `server-client.c:2339-2356`

The `latest` policy is implemented by tracking a `w->latest` pointer on each window:

```c
// server-client.c:2339-2356
static void
server_client_update_latest(struct client *c)
{
    struct window *w;

    if (c->session == NULL)
        return;
    w = c->session->curw->window;

    if (w->latest == c)
        return;
    w->latest = c;

    if (options_get_number(w->options, "window-size") == WINDOW_SIZE_LATEST)
        recalculate_size(w, 0);

    notify_client("client-active", c);
}
```

`server_client_update_latest()` is called on:
- Key input events (`server_client_key_callback`)
- Resize events (`MSG_RESIZE` handler)

When the latest client changes and the policy is `latest`, `recalculate_size()` is triggered immediately. If there are multiple clients, only the `latest` client's size is used (with a fallback to smallest behavior when only one client exists):

```c
// resize.c:167-170  (inside clients_calculate_size)
if (type == WINDOW_SIZE_LATEST && n > 1 && loop != w->latest) {
    log_debug("%s: %s is not latest", __func__, loop->name);
    continue;
}
```

### 1.5 Resize Event Flow

The full resize flow from client report to PTY ioctl:

1. **Client detects terminal resize** (SIGWINCH) and sends `MSG_RESIZE` to server
2. **Server receives** in `server_client_dispatch()` (`server-client.c:3417-3434`):
   - Updates `w->latest` via `server_client_update_latest(c)`
   - Calls `tty_resize(&c->tty)` which reads the client's terminal size via `ioctl(c->fd, TIOCGWINSZ)` (`tty.c:118-155`)
   - Calls `recalculate_sizes()` which iterates all windows
3. **`recalculate_size(w, 0)`** (`resize.c:352-417`):
   - Reads `window-size` type and `aggressive-resize` flag
   - Calls `clients_calculate_size()` which iterates all eligible clients
   - If size changed, sets `WINDOW_RESIZE` flag and stores `w->new_sx`, `w->new_sy`
4. **`server_client_loop()`** (`server-client.c:2713-2715`):
   - Calls `server_client_check_window_resize(w)` for each window
   - If `WINDOW_RESIZE` is set and window is current for an attached session, calls `resize_window()`
5. **`resize_window()`** (`resize.c:25-66`):
   - Calls `layout_resize()` to adjust pane layout
   - Calls `window_resize()` to update window dimensions
6. **`server_client_check_pane_resize(wp)`** (`server-client.c:2791-2861`):
   - Processes resize queue for each pane with a 250ms debounce timer
   - Calls `window_pane_send_resize()` which performs `ioctl(wp->fd, TIOCSWINSZ, &ws)` (`window.c:434-449`)

**Debouncing**: Pane resize uses a 250ms timer (`tv = { .tv_usec = 250000 }`) to coalesce rapid resize events. Multiple resizes are collapsed to avoid flooding applications with SIGWINCH:

```c
// server-client.c:2799
struct timeval tv = { .tv_usec = 250000 };
```

### 1.6 Per-Client Per-Window Size Override

**File**: `cmd-refresh-client.c:81-131`

Control mode clients can set per-window sizes using `refresh-client -C @<window>:<w>x<h>`. This is stored in a per-client `client_window` tree and participates in size calculations. This enables iTerm2 to report different sizes for different tmux windows mapped to native tabs.

---

## Part 2: Client Health Model

### 2.1 Connection Loss Detection

**File**: `proc.c:73-102`, `server-client.c:3387-3392`

tmux does **not** use application-level heartbeats. Client health is detected entirely through the Unix domain socket:

```c
// proc.c:80-84
if (!(peer->flags & PEER_BAD) && (events & EV_READ)) {
    if (imsgbuf_read(&peer->ibuf) != 1) {
        peer->dispatchcb(NULL, peer->arg);  // NULL imsg = connection lost
        return;
    }
```

When a read/write error occurs on the socket (EOF, EPIPE, etc.), `imsgbuf_read()` returns non-1, and the dispatch callback is called with `NULL`:

```c
// server-client.c:3390-3392
if (imsg == NULL) {
    server_client_lost(c);
    return;
}
```

**There is no application-level keepalive or heartbeat mechanism in tmux.** The server relies entirely on:
- OS-level socket error detection (EOF on read)
- OS TCP keepalive for network sockets (not used for local Unix sockets)
- Client explicitly sending `MSG_EXITING` during graceful disconnect

### 2.2 Client States and Transitions

tmux has a simple client state model based on flags:

```
ATTACHED ──► SUSPENDED (Ctrl-Z / lock)
    │              │
    │              ├──► WAKEUP (MSG_WAKEUP / MSG_UNLOCK) ──► ATTACHED
    │              │
    │              └──► DEAD (socket error)
    │
    ├──► CLIENT_EXIT (detach / "too far behind") ──► CLIENT_EXITED ──► DEAD
    │
    └──► DEAD (socket error / server_client_lost)
```

Key flags:
- **`CLIENT_SUSPENDED`** (`0x4000`): Client sent SIGTSTP (Ctrl-Z) or screen locked. Set in `server_client_suspend()`. Cleared on `MSG_WAKEUP`/`MSG_UNLOCK`.
- **`CLIENT_EXIT`** (`0x400`): Client is being disconnected (detach or eviction). Transitions to `CLIENT_EXITED` after all output is flushed.
- **`CLIENT_DEAD`** (`0x200`): Client connection is dead. Set in `server_client_lost()`. Client is removed from sizing calculations and scheduled for cleanup.

**There are no intermediate health states** (e.g., "slow", "degraded", "warning"). A client is either fully functional, suspended, or dead.

### 2.3 Slow Client Detection and Eviction (Control Mode)

**File**: `control.c:431-464`

tmux's most sophisticated client health handling is in control mode (used by iTerm2). The `control_check_age()` function checks how far behind a control client's output queue is:

```c
// control.c:431-464
static int
control_check_age(struct client *c, struct window_pane *wp,
    struct control_pane *cp)
{
    struct control_block *cb;
    uint64_t t, age;

    cb = TAILQ_FIRST(&cp->blocks);
    if (cb == NULL)
        return (0);
    t = get_timer();
    if (cb->t >= t)
        return (0);

    age = t - cb->t;
    log_debug("%s: %s: %%%u is %llu behind", __func__, c->name, wp->id,
        (unsigned long long)age);

    if (c->flags & CLIENT_CONTROL_PAUSEAFTER) {
        if (age < c->pause_age)
            return (0);
        cp->flags |= CONTROL_PANE_PAUSED;
        control_discard_pane(c, cp);
        control_write(c, "%%pause %%%u", wp->id);
    } else {
        if (age < CONTROL_MAXIMUM_AGE)
            return (0);
        c->exit_message = xstrdup("too far behind");
        c->flags |= CLIENT_EXIT;
        control_discard(c);
    }
    return (1);
}
```

Two escalation paths depending on client capabilities:

**Path A: No `pause-after` (legacy clients)**
- If the oldest undelivered output block is older than `CONTROL_MAXIMUM_AGE` (300,000 ms = **5 minutes**), the client is **forcibly disconnected** with "too far behind".
- All pending output is discarded.
- This is a hard eviction -- no warning, no gradual degradation.

**Path B: `pause-after` mode (modern clients like iTerm2)**
- Set via `refresh-client -f pause-after=N` where N is seconds.
- If output age exceeds `pause_age`, the **pane** (not the client) is paused: `%pause %%%u` notification sent.
- The client can later resume with `%continue`.
- The pane's output buffer is discarded and re-synced on resume.
- The client is NOT disconnected -- it can continue receiving output from other panes.
- **This is per-pane granularity**, not per-client.

```c
// server-client.c:3789-3795
if (strcmp(next, "pause-after") == 0) {
    c->pause_age = 0;
    return (CLIENT_CONTROL_PAUSEAFTER);
}
if (sscanf(next, "pause-after=%u", &c->pause_age) == 1) {
    c->pause_age *= 1000;  // seconds to milliseconds
    return (CLIENT_CONTROL_PAUSEAFTER);
}
```

### 2.4 Output Buffering and Backpressure

#### Control Mode Clients

**File**: `control.c:131-138`

```c
// control.c:131-138
#define CONTROL_BUFFER_LOW  512
#define CONTROL_BUFFER_HIGH 8192
#define CONTROL_WRITE_MINIMUM 32
#define CONTROL_MAXIMUM_AGE 300000  // 300 seconds = 5 minutes
```

Control mode uses a write-watermark system:
- When the output buffer exceeds `CONTROL_BUFFER_HIGH` (8 KiB), output is paused.
- Writing resumes when buffer drops below `CONTROL_BUFFER_LOW` (512 bytes).
- Each write callback distributes output fairly across pending panes (space / pending_count / 3, minimum 32 bytes per pane).

The `control_pane_offset` mechanism (`server-client.c:2864-2950`) tracks per-client read progress through the shared pane output buffer:

```c
// server-client.c:2876-2906
minimum = wp->offset.used;
// ...
TAILQ_FOREACH(c, &clients, entry) {
    // ...
    wpo = control_pane_offset(c, wp, &flag);
    // ...
    if (wpo->used < minimum)
        minimum = wpo->used;
}
```

The shared buffer is only drained up to the **minimum** consumed offset across all clients. This means a slow client holds the buffer for all clients.

**Critical backpressure mechanism** (`server-client.c:2939-2949`):
```c
// If all attached control clients are unable to consume data, disable reading
// from the pane's PTY entirely.
if (off)
    bufferevent_disable(wp->event, EV_READ);
else
    bufferevent_enable(wp->event, EV_READ);
```

If **all** attached clients are control clients and none can accept more data, PTY reads are disabled -- the application will block on write. This prevents unbounded buffer growth but means one slow client can cause backpressure on the application.

#### Regular (TTY) Clients

**File**: `tty.c:191-234`

Regular clients use a different mechanism -- `TTY_BLOCK`:

```c
// tty.c:80-82
#define TTY_BLOCK_INTERVAL (100000 /* 100 milliseconds */)
#define TTY_BLOCK_START(tty) (1 + ((tty)->sx * (tty)->sy) * 8)
#define TTY_BLOCK_STOP(tty)  (1 + ((tty)->sx * (tty)->sy) / 8)
```

When the output buffer exceeds `TTY_BLOCK_START` (~8 screenfuls), the TTY is blocked:
- Pending output is **discarded** (not queued).
- A 100ms timer fires to check if the client has caught up.
- If output drops below `TTY_BLOCK_STOP` (~1/8 screenful), the block is lifted.
- The entire screen is redrawn after unblocking.

This means regular clients **never cause backpressure on other clients or the application**. Instead, they simply discard frames and do a full redraw.

### 2.5 Slow Client Impact Isolation

**Summary of isolation characteristics:**

| Client Type | Backpressure on others? | Backpressure on app? | Eviction? |
|------------|------------------------|---------------------|-----------|
| **Regular TTY** | No. Output discarded and redrawn. | No. | No (unless socket dies). |
| **Control (no pause-after)** | Yes -- holds shared buffer. | Yes -- PTY read disabled if all clients stall. | Yes, after 5 minutes ("too far behind"). |
| **Control (pause-after)** | Partially -- paused panes release buffer. | Reduced -- paused panes don't hold buffer. | No forced disconnect; per-pane pause instead. |

**The key insight**: Regular TTY clients are fully isolated from each other -- tmux simply discards output and redraws. Control mode clients share a pane output buffer and can cause backpressure, but `pause-after` mode mitigates this by allowing per-pane suspension.

### 2.6 No Application-Level Keepalive

tmux has **no** heartbeat, ping/pong, or keepalive protocol. Connection health is determined solely by:

1. **Socket I/O errors**: Read EOF, write EPIPE, detected by libevent callbacks.
2. **Output age**: For control clients only, output older than 5 minutes triggers eviction.
3. **OS-level mechanisms**: TCP keepalive (for network-attached clients, not relevant for Unix sockets).

There is no "slow client" state, no health score, no gradual degradation path for regular TTY clients. A client is either operational or dead.

---

## Part 3: Relevance to libitshell3

### Issue 2a: Multi-Client Resize

**tmux's approach and what libitshell3 can learn:**

1. **Default to `latest`, not `smallest`**: tmux switched its default from `smallest` to `latest` in version 3.1. This eliminates the "stale small client shrinks everyone" problem. libitshell3 should consider `latest` as its default policy.

2. **Exclude unhealthy clients**: tmux excludes `CLIENT_DEAD | CLIENT_SUSPENDED | CLIENT_EXIT` from sizing via `CLIENT_NOSIZEFLAGS`. libitshell3 should similarly exclude paused/unresponsive clients from size calculations. This directly addresses the Issue 2a concern about "paused/unresponsive clients' stale dimensions".

3. **Per-client per-window size overrides**: tmux's `CLIENT_WINDOWSIZECHANGED` + `client_window` structure allows control clients (like iTerm2) to report different sizes per window. This is relevant for libitshell3's multi-tab scenarios where different tabs may map to different client window sizes.

4. **250ms resize debounce**: tmux debounces PTY resizes with a 250ms timer to prevent SIGWINCH storms. libitshell3 should implement similar coalescing.

### Issue 2b: Client Health Model

**What tmux does well:**
- Simple, robust model: alive or dead, detected by socket errors
- Control mode has sophisticated per-pane pause/resume for slow clients
- Regular TTY clients are fully isolated -- discard-and-redraw prevents cascading slowness
- 5-minute timeout for legacy control clients provides eventual eviction

**What tmux lacks (and libitshell3 could improve):**
- No application-level heartbeat -- relies entirely on OS socket detection
- No intermediate health states for regular clients
- No proactive health monitoring -- detection is purely reactive (output age check happens during write attempts, not on a timer)
- The shared buffer model for control clients can cause backpressure on the application when all clients are slow

**Recommended approach for libitshell3:**
- Keep application-level heartbeat (the protocol already has this at 30s interval, 90s timeout)
- Consider tmux's `pause-after` per-pane model for flow control
- Implement output discard-and-resync (like regular TTY client `TTY_BLOCK`) rather than buffering for slow clients
- Exclude unhealthy/paused clients from resize calculations (like `CLIENT_NOSIZEFLAGS`)
- Consider supporting multiple resize policies (smallest/largest/latest/manual) as tmux does, with `latest` as default

---

## Files Examined

| File | Lines/Sections | Purpose |
|------|---------------|---------|
| `resize.c` | Full file (461 lines) | Window sizing policies, client filtering |
| `server-client.c` | Lines 440-524, 2690-2760, 2760-2950, 3378-3496 | Client lifecycle, main loop, pane buffer management, message dispatch |
| `control.c` | Lines 29-96, 129-138, 265-385, 431-464, 585-800 | Control mode buffering, pause/resume, age checking |
| `tty.c` | Lines 75-82, 117-155, 191-234 | TTY resize, output blocking |
| `window.c` | Lines 414-449 | Window resize, TIOCSWINSZ ioctl |
| `options-table.c` | Lines 90-92, 1057-1064, 1447-1456 | Option definitions |
| `tmux.h` | Lines 1278-1310, 1356-1359, 1955, 2015-2058 | Structs and flag definitions |
| `proc.c` | Lines 73-102 | Socket I/O and connection loss detection |
| `cmd-refresh-client.c` | Lines 80-131 | Control client size reporting |
| `server.c` | Lines 244-290 | Main server event loop |
