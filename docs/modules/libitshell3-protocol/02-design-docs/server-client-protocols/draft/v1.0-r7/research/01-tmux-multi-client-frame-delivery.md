# tmux Multi-Client Frame Delivery Analysis

> **Date**: 2026-03-05
> **Author**: tmux-researcher
> **Purpose**: Evidence for Issues 22-24 (I-frame/P-frame model discussion)
> **tmux source**: `~/dev/git/references/tmux/`

---

## 1. Architecture Overview: Two Separate Output Paths

tmux has **two entirely distinct output delivery systems** depending on client type:

1. **TTY clients** (normal terminal clients): Server generates VT escape sequences
   per-client and writes them to each client's `tty.out` evbuffer. Output is
   **rendered at generation time** — the server walks the authoritative screen
   state and emits terminal escape sequences directly into each client's output
   buffer.

2. **Control mode clients** (`-CC` flag, used by iTerm2): Server forwards **raw
   PTY output bytes** with per-client offset tracking. The control mode client
   (e.g., iTerm2) is responsible for parsing VT sequences and rendering
   independently.

These two paths have completely different buffering, blocking, and recovery
mechanisms.

---

## 2. TTY Client Output: Per-Client Rendering from Authoritative State

### 2.1 No Per-Client Dirty Bitmaps

tmux does **NOT** maintain per-client dirty bitmaps. Instead, it uses a two-level
system:

- **Per-pane** `PANE_REDRAW` flag (`tmux.h:1200`): A single bit on the
  `window_pane` struct. Set when any change occurs that requires redraw. This is
  a **pane-global** flag, not per-client.

- **Per-client** `CLIENT_REDRAWWINDOW` / `CLIENT_REDRAWPANES` / etc. flags
  (`tmux.h:2003-2046`): Bit flags on the client struct indicating **what scope**
  of redraw is needed. These are not dirty bitmaps — they are coarse-grained
  redraw scope selectors.

The full set of client redraw flags:

```c
// tmux.h:2003-2046
#define CLIENT_REDRAWWINDOW      0x8
#define CLIENT_REDRAWSTATUS      0x10
#define CLIENT_REDRAWSTATUSALWAYS 0x1000000
#define CLIENT_REDRAWPANES       0x20000000

#define CLIENT_ALLREDRAWFLAGS    \
    (CLIENT_REDRAWWINDOW|        \
     CLIENT_REDRAWSTATUS|        \
     CLIENT_REDRAWSTATUSALWAYS|  \
     ...                         \
     CLIENT_REDRAWPANES|         \
     ...)
```

### 2.2 Incremental Updates via `tty_write()` Dispatch

When terminal output arrives and is parsed by the VT parser (`input.c`), it
modifies the pane's screen state and then calls `screen_write_collect_flush()`
(`screen-write.c:1814`). This function iterates the collected changes and calls
`tty_write()` for each one:

```c
// screen-write.c:1877
tty_write(tty_cmd_cells, &ttyctx);
```

`tty_write()` (`tty.c:1550`) iterates **all connected clients** and dispatches
the same rendering command to each:

```c
// tty.c:1549-1568
void
tty_write(void (*cmdfn)(struct tty *, const struct tty_ctx *),
    struct tty_ctx *ctx)
{
    struct client *c;
    int state;

    if (ctx->set_client_cb == NULL)
        return;
    TAILQ_FOREACH(c, &clients, entry) {
        if (tty_client_ready(ctx, c)) {
            state = ctx->set_client_cb(ctx, c);
            if (state == -1)
                break;
            if (state == 0)
                continue;
            cmdfn(&c->tty, ctx);
        }
    }
}
```

Each `cmdfn` call generates VT escape sequences into that specific client's
`tty->out` evbuffer. The escape sequences are **different per client** because
each client may have different terminal capabilities, cursor positions, and
screen offsets. This is inherently O(N) per output event.

### 2.3 The `set_client_cb` Gating Mechanism

Before dispatching to a client, `set_client_cb` (`screen-write.c:132`) checks
whether the pane is visible for that client. If the pane already has
`PANE_REDRAW` set (meaning a full redraw is pending), it returns -1 to **skip
all remaining clients** and fall back to the full redraw path:

```c
// screen-write.c:147-157
if (wp->flags & (PANE_REDRAW|PANE_DROP))
    return (-1);
if (c->flags & CLIENT_REDRAWPANES) {
    /* Redraw is already deferred to redraw another pane -
     * redraw this one also when that happens. */
    wp->flags |= (PANE_REDRAW|PANE_REDRAWSCROLLBAR);
    return (-1);
}
```

This means: once ANY client triggers a full redraw condition, the incremental
path is abandoned for ALL clients, and the pane falls back to `PANE_REDRAW`
(full redraw from authoritative state).

---

## 3. TTY_BLOCK / TTY_NOBLOCK: Per-Client Output Blocking

### 3.1 Block Detection

Each client has a per-client `tty.out` evbuffer for outgoing data. The
`tty_block_maybe()` function (`tty.c:213`) checks the evbuffer size after
each write:

```c
// tty.c:80-82
#define TTY_BLOCK_INTERVAL (100000 /* 100 milliseconds */)
#define TTY_BLOCK_START(tty) (1 + ((tty)->sx * (tty)->sy) * 8)
#define TTY_BLOCK_STOP(tty) (1 + ((tty)->sx * (tty)->sy) / 8)
```

- `TTY_BLOCK_START`: Threshold to enter blocked state. For a 120x40 terminal:
  `1 + 4800 * 8 = 38,401 bytes`.
- `TTY_BLOCK_STOP`: Threshold to exit blocked state. For 120x40:
  `1 + 4800 / 8 = 601 bytes`.

When the output buffer exceeds `TTY_BLOCK_START`:

```c
// tty.c:212-238
static int
tty_block_maybe(struct tty *tty)
{
    struct client *c = tty->client;
    size_t size = EVBUFFER_LENGTH(tty->out);
    struct timeval tv = { .tv_usec = TTY_BLOCK_INTERVAL };

    if (size < TTY_BLOCK_START(tty))
        return (0);

    if (tty->flags & TTY_BLOCK)
        return (1);
    tty->flags |= TTY_BLOCK;

    log_debug("%s: can't keep up, %zu discarded", c->name, size);

    evbuffer_drain(tty->out, size);   // DISCARD all buffered output
    c->discarded += size;

    tty->discarded = 0;
    evtimer_add(&tty->timer, &tv);    // Start 100ms timer
    return (1);
}
```

### 3.2 Discard Behavior While Blocked

Once `TTY_BLOCK` is set, **all subsequent output is silently discarded** at the
lowest level — `tty_add()` (`tty.c:620`):

```c
// tty.c:620-628
static void
tty_add(struct tty *tty, const char *buf, size_t len)
{
    struct client *c = tty->client;

    if (tty->flags & TTY_BLOCK) {
        tty->discarded += len;
        return;
    }
    // ... normal output path ...
}
```

The discarded byte count is accumulated in `tty->discarded`.

### 3.3 Recovery: Discard-and-Redraw via Timer

The 100ms timer fires `tty_timer_callback()` (`tty.c:191`):

```c
// tty.c:191-210
static void
tty_timer_callback(...)
{
    struct tty *tty = data;
    struct client *c = tty->client;
    struct timeval tv = { .tv_usec = TTY_BLOCK_INTERVAL };

    c->flags |= CLIENT_ALLREDRAWFLAGS;  // Request FULL redraw
    c->discarded += tty->discarded;

    if (tty->discarded < TTY_BLOCK_STOP(tty)) {
        tty->flags &= ~TTY_BLOCK;       // Unblock
        tty_invalidate(tty);             // Reset all tty state
        return;
    }
    tty->discarded = 0;
    evtimer_add(&tty->timer, &tv);       // Still too much - retry
}
```

The recovery cycle:
1. `TTY_BLOCK` set, all output discarded
2. 100ms timer fires
3. If discard rate dropped below `TTY_BLOCK_STOP`: unblock, set
   `CLIENT_ALLREDRAWFLAGS`, call `tty_invalidate()`
4. If still discarding too fast: reschedule timer for another 100ms
5. On next `server_client_loop()` iteration, `server_client_check_redraw()`
   sees `CLIENT_ALLREDRAWFLAGS` and performs a **full screen redraw from
   authoritative state**

### 3.4 `tty_invalidate()`: Resetting Per-Client Rendering State

When unblocking, `tty_invalidate()` (`tty.c:2216`) resets all cached rendering
state for that client:

```c
// tty.c:2215-2238
void
tty_invalidate(struct tty *tty)
{
    memcpy(&tty->cell, &grid_default_cell, sizeof tty->cell);
    memcpy(&tty->last_cell, &grid_default_cell, sizeof tty->last_cell);

    tty->cx = tty->cy = UINT_MAX;
    tty->rupper = tty->rleft = UINT_MAX;
    tty->rlower = tty->rright = UINT_MAX;

    if (tty->flags & TTY_STARTED) {
        tty_putcode(tty, TTYC_SGR0);  // Reset attributes
        tty->mode = ALL_MODES;
        tty_update_mode(tty, MODE_CURSOR, NULL);
        tty_cursor(tty, 0, 0);        // Home cursor
        tty_region_off(tty);           // Reset scroll region
        tty_margin_off(tty);
    }
}
```

This ensures the full redraw starts from a clean slate, as all incremental
state (cursor position, current attributes, scroll region) was invalidated
when output was discarded.

---

## 4. Full Redraw: `server_client_check_redraw()`

This function (`server-client.c:3182`) is called for every client on every
event loop iteration. It is the central redraw dispatch:

### 4.1 Deferred Redraw When Output Buffer Non-Empty

```c
// server-client.c:3230-3237
if (needed && (left = EVBUFFER_LENGTH(tty->out)) != 0) {
    log_debug("%s: redraw deferred (%zu left)", c->name, left);
    // ... set 1ms timer to re-enter event loop ...
    // ... save per-pane redraw flags into c->redraw_panes bitmask ...
    return;
}
```

If there is still pending output in the client's buffer, the redraw is
**deferred** until the buffer drains. A 1ms timer (`server_client_redraw_timer`)
kicks the event loop to retry.

The `c->redraw_panes` field is a **64-bit bitmask** tracking which panes need
redraw for this specific client. If more than 64 panes exist, tmux falls back
to `CLIENT_REDRAWWINDOW` (full window redraw):

```c
// server-client.c:3250-3258
if (++bit == 64) {
    /* If more that 64 panes, give up and
     * just redraw the window. */
    client_flags &= ~(CLIENT_REDRAWPANES|...);
    client_flags |= CLIENT_REDRAWWINDOW;
    break;
}
```

### 4.2 Per-Pane Redraw from Authoritative State

When the buffer is empty and redraw proceeds, panes are redrawn by calling
`screen_redraw_pane()` (`screen-redraw.c:688`), which calls
`screen_redraw_draw_pane()` (`screen-redraw.c:939`).

This function reads **directly from the pane's grid** (the authoritative
terminal state) using `tty_draw_line()` (`tty-draw.c:111`):

```c
// screen-redraw.c:962-1003
for (j = 0; j < wp->sy; j++) {
    // ... compute visible range, handle offsets ...
    tty_draw_line(tty, s, rr->px - wp->xoff, j,
        rr->nx, rr->px, y, &defaults, palette);
}
```

`tty_draw_line()` reads cells from the grid via `grid_view_get_cell()` and
generates VT escape sequences to render them. It reads the **current
authoritative state** — there is no delta, no diff, no reference to any
previous frame. Every full redraw is a complete re-rendering from the
ground-truth screen state.

### 4.3 Redraw Tracking: `c->redraw` Byte Counter

After a redraw, tmux records how many bytes were generated:

```c
// server-client.c:3323-3330
if (needed) {
    c->redraw = EVBUFFER_LENGTH(tty->out);
    log_debug("%s: redraw added %zu bytes", c->name, c->redraw);
}
```

This value is used in `tty_write_callback()` (`tty.c:254-262`) to prevent
`tty_block_maybe()` from triggering during the initial flush of a redraw:

```c
// tty.c:254-262
if (c->redraw > 0) {
    if ((size_t)nwrite >= c->redraw)
        c->redraw = 0;
    else
        c->redraw -= nwrite;
} else if (tty_block_maybe(tty))
    return;
```

This prevents the block mechanism from immediately discarding a redraw that
was triggered by a previous block recovery.

---

## 5. Control Mode (`-CC`): Per-Client Offset-Based Raw Output

### 5.1 Architecture: Shared Pane Buffer with Per-Client Read Cursors

Control mode uses a fundamentally different model from TTY clients. It is
the closest analogue to our proposed shared ring buffer design.

The pane's raw PTY output accumulates in `wp->event->input` (a shared
evbuffer). Each control mode client maintains a per-pane offset
(`control_pane.offset` / `control_pane.queued`) that tracks how far into
this shared buffer it has read:

```c
// control.c:54-75
struct control_pane {
    u_int                    pane;
    struct window_pane_offset offset;   // data written to client
    struct window_pane_offset queued;   // data queued for writing
    int                      flags;
#define CONTROL_PANE_OFF 0x1
#define CONTROL_PANE_PAUSED 0x2
    int                      pending_flag;
    TAILQ_HEAD(, control_block) blocks;
    RB_ENTRY(control_pane)   entry;
};
```

```c
// tmux.h:1156-1158
struct window_pane_offset {
    size_t used;
};
```

The shared buffer is drained only when ALL clients have consumed data past
a point. `server_client_check_pane_buffer()` (`server-client.c:2865`)
calculates the minimum offset across all control clients and drains the
shared buffer up to that point:

```c
// server-client.c:2879-2906
minimum = wp->offset.used;
// ... check pipe offset ...
TAILQ_FOREACH(c, &clients, entry) {
    // ... for each control client ...
    wpo = control_pane_offset(c, wp, &flag);
    // ...
    if (wpo->used < minimum)
        minimum = wpo->used;
}
// ...
evbuffer_drain(evb, minimum);
```

### 5.2 Per-Client Output Blocks and Ordering

When new data arrives on a pane's PTY, `control_write_output()`
(`control.c:468`) is called for each control client. It creates a
`control_block` recording the new data size and adds it to both:

- The pane's block queue (`cp->blocks`) — per-client, per-pane
- The client's global block queue (`cs->all_blocks`) — ensures ordering between
  `%output` blocks and notification lines

The dual-queue design ensures that notification lines (like `%layout-change`)
are never reordered past pending `%output` blocks.

### 5.3 Flow Control: Watermarks and Pause Mode

Control mode uses buffer watermarks, not TTY_BLOCK:

```c
// control.c:130-138
#define CONTROL_BUFFER_LOW 512
#define CONTROL_BUFFER_HIGH 8192
#define CONTROL_WRITE_MINIMUM 32
#define CONTROL_MAXIMUM_AGE 300000  // 300 seconds
```

The `control_write_callback()` (`control.c:728`) is triggered when the
client's output buffer drains below `CONTROL_BUFFER_LOW`. It writes pending
blocks up to `CONTROL_BUFFER_HIGH`, distributing bandwidth across panes:

```c
// control.c:738-758
while (EVBUFFER_LENGTH(evb) < CONTROL_BUFFER_HIGH) {
    if (cs->pending_count == 0)
        break;
    space = CONTROL_BUFFER_HIGH - EVBUFFER_LENGTH(evb);
    limit = (space / cs->pending_count / 3);
    if (limit < CONTROL_WRITE_MINIMUM)
        limit = CONTROL_WRITE_MINIMUM;

    TAILQ_FOREACH_SAFE(cp, &cs->pending_list, pending_entry, cp1) {
        if (EVBUFFER_LENGTH(evb) >= CONTROL_BUFFER_HIGH)
            break;
        if (control_write_pending(c, cp, limit))
            continue;
        TAILQ_REMOVE(&cs->pending_list, cp, pending_entry);
        // ...
    }
}
```

### 5.4 Age-Based Slow Client Handling

`control_check_age()` (`control.c:432`) monitors how old the oldest
undelivered block is. Two modes:

**Pause mode** (`CLIENT_CONTROL_PAUSEAFTER`): If the oldest block exceeds
`c->pause_age`, the pane is paused. All pending blocks are discarded. A
`%pause %%N` notification is sent. The client (e.g., iTerm2) can later
request `%continue` to resume, at which point offsets are reset to current:

```c
// control.c:450-455
if (c->flags & CLIENT_CONTROL_PAUSEAFTER) {
    if (age < c->pause_age)
        return (0);
    cp->flags |= CONTROL_PANE_PAUSED;
    control_discard_pane(c, cp);
    control_write(c, "%%pause %%%u", wp->id);
```

**Non-pause mode**: If the oldest block exceeds `CONTROL_MAXIMUM_AGE` (300s),
the client is disconnected:

```c
// control.c:456-461
} else {
    if (age < CONTROL_MAXIMUM_AGE)
        return (0);
    c->exit_message = xstrdup("too far behind");
    c->flags |= CLIENT_EXIT;
    control_discard(c);
}
```

### 5.5 Recovery After Pause: Offset Reset

When a paused pane is continued via `control_continue_pane()`
(`control.c:360`), the client's offsets are reset to the pane's current
position:

```c
// control.c:360-370
void
control_continue_pane(struct client *c, struct window_pane *wp)
{
    cp = control_get_pane(c, wp);
    if (cp != NULL && (cp->flags & CONTROL_PANE_PAUSED)) {
        cp->flags &= ~CONTROL_PANE_PAUSED;
        memcpy(&cp->offset, &wp->offset, sizeof cp->offset);
        memcpy(&cp->queued, &wp->offset, sizeof cp->queued);
        control_write(c, "%%continue %%%u", wp->id);
    }
}
```

This is equivalent to "skip to latest keyframe" in our I-frame model. The
client must parse subsequent raw output from the current point — it has no
screen state reference. iTerm2 handles this by requesting a full capture of
the current pane content via `capture-pane -p`.

### 5.6 Backpressure: Disabling PTY Reads

If ALL control clients are unable to consume data (all paused or off), the
PTY read is disabled entirely to apply backpressure to the child process:

```c
// server-client.c:2938-2949
/* If there is data remaining, and there are no clients able to
 * consume it, do not read any more. */
if (off)
    bufferevent_disable(wp->event, EV_READ);
else
    bufferevent_enable(wp->event, EV_READ);
```

---

## 6. Incremental vs Full Redraw Triggers

### 6.1 Incremental Updates (TTY clients only)

Incremental updates flow through `screen_write_collect_flush()` ->
`tty_write()` -> `cmdfn()` for each client. These happen inline as VT
sequences are parsed. The "increment" is the VT command itself (e.g.,
insert character, clear line, write cells).

Incremental updates are abandoned when:
- The pane has `PANE_REDRAW` set (deferred to full redraw)
- Any client has `CLIENT_REDRAWPANES` set (pane added to deferred list)
- The client is blocked (`TTY_BLOCK`)

### 6.2 Full Redraw Triggers

Full redraw (`CLIENT_ALLREDRAWFLAGS` or `PANE_REDRAW`) is triggered by:

1. **TTY_BLOCK recovery** — `tty_timer_callback()` sets
   `CLIENT_ALLREDRAWFLAGS` (`tty.c:200`)
2. **Terminal resize** — `tty_update_window_offset()` sets
   `CLIENT_REDRAWWINDOW|CLIENT_REDRAWSTATUS` (`tty.c:1052`)
3. **Attach/reattach** — `server_redraw_client()` sets
   `CLIENT_ALLREDRAWFLAGS` (`server-fn.c:36`)
4. **Scroll region operations** — Various `screen_write_*` functions set
   `PANE_REDRAW` when operations cannot be translated to incremental
   terminal commands (`screen-write.c` throughout)
5. **Pane resize** — `window_pane_resize()` triggers `PANE_REDRAW`
6. **Mode changes** — Copy mode enter/exit, command mode, etc.
7. **Fallback from incremental path** — When `set_client_cb` returns -1

### 6.3 Control Mode Notifications (triggers client-side redraw)

Control mode does not send screen state — it sends raw PTY bytes and
notifications. The client (iTerm2) does its own VT parsing and rendering.
When structural changes occur, notifications trigger client-side redraws:

- `%layout-change @N LAYOUT` — Window layout changed (resize, split, close)
- `%window-pane-changed @N %%M` — Active pane changed
- `%session-changed $N NAME` — Client attached to different session
- `%pause %%N` / `%continue %%N` — Pane output flow control

---

## 7. Summary of Key Findings

### 7.1 Per-Client State in tmux

| Aspect | TTY Clients | Control Mode Clients |
|--------|-------------|---------------------|
| Output format | VT escape sequences (rendered by server) | Raw PTY bytes + notifications |
| Per-client state | `tty` struct (cursor, attrs, scroll region, mode) | `control_pane.offset` (read cursor into shared buffer) |
| Dirty tracking | Per-pane `PANE_REDRAW` flag (boolean, not bitmap) | None (offset-based) |
| Blocking | `TTY_BLOCK` flag + 100ms timer | Age-based pause/disconnect |
| Recovery | Discard all output, full redraw from authoritative grid | Discard pending blocks, reset offset to current position |
| Full redraw source | Server reads pane grid, generates VT sequences | Client requests `capture-pane` or re-parses from reset point |

### 7.2 Observations Relevant to Issues 22-24

1. **tmux's TTY path is inherently O(N)**: Each client gets individually
   rendered VT escape sequences. There is no shared output — the rendering
   is per-client because terminal capabilities and state differ.

2. **tmux's control mode path IS a shared buffer with per-client cursors**:
   The `wp->event->input` evbuffer is the shared buffer. Each control client
   has an offset (`control_pane.offset`). The buffer is drained only when all
   clients have consumed past a point. This is architecturally identical to
   the proposed shared ring buffer in Issue 22.

3. **tmux has NO concept of keyframes**: In TTY mode, recovery always means
   a full redraw from authoritative state (the pane's grid). In control mode,
   recovery means resetting the offset and having the client re-derive state
   (iTerm2 uses `capture-pane`). Neither is analogous to periodic keyframes —
   both are triggered only on error/overload, not proactively.

4. **tmux's PANE_REDRAW is a boolean, not a bitmap**: A pane is either
   "needs full redraw" or "doesn't". There is no row-level dirty tracking
   at the server level. The per-client "what to redraw" is the coarse
   bitmask of `CLIENT_REDRAW*` flags and the 64-bit `c->redraw_panes`.

5. **Incremental updates fail closed to full redraw**: When any client is
   blocked or behind, the incremental path (`tty_write` dispatch) falls
   back to `PANE_REDRAW`, which triggers a full redraw from authoritative
   state on the next loop iteration. There is no attempt to compute a
   per-client delta — it's all-or-nothing.

6. **The discard-and-redraw pattern is tmux's only recovery mechanism**:
   There is no gradual catch-up, no delta accumulation, no skip-ahead.
   When a client falls behind: discard everything, wait for drain, redraw
   everything from scratch.

---

## 8. Source File Reference

| File | Key Functions | Role |
|------|--------------|------|
| `tty.c:80-82` | `TTY_BLOCK_START`, `TTY_BLOCK_STOP`, `TTY_BLOCK_INTERVAL` | Block threshold constants |
| `tty.c:191-210` | `tty_timer_callback()` | Block recovery: schedule full redraw |
| `tty.c:212-238` | `tty_block_maybe()` | Detect output buffer overflow, enter blocked state |
| `tty.c:242-266` | `tty_write_callback()` | Output drain callback, redraw-aware block check |
| `tty.c:620-638` | `tty_add()` | Lowest-level output: discard if blocked |
| `tty.c:1527-1547` | `tty_client_ready()` | Check if client can receive incremental updates |
| `tty.c:1549-1568` | `tty_write()` | Dispatch rendering command to all ready clients |
| `tty.c:2215-2238` | `tty_invalidate()` | Reset all per-client rendering state |
| `tty-draw.c:111-190` | `tty_draw_line()` | Render one line from authoritative grid state |
| `screen-write.c:132-157` | `screen_write_set_client_cb()` | Gate incremental updates, fall back to PANE_REDRAW |
| `screen-write.c:1814-1889` | `screen_write_collect_flush()` | Flush collected cell changes to all clients |
| `screen-redraw.c:644-684` | `screen_redraw_screen()` | Full screen redraw for one client |
| `screen-redraw.c:688-707` | `screen_redraw_pane()` | Full pane redraw for one client |
| `screen-redraw.c:939-1008` | `screen_redraw_draw_pane()` | Walk grid rows, call `tty_draw_line()` |
| `server-client.c:2706-2752` | `server_client_loop()` | Main loop: check all windows, then all clients |
| `server-client.c:3182-3332` | `server_client_check_redraw()` | Per-client redraw dispatch with deferred handling |
| `server-client.c:2865-2950` | `server_client_check_pane_buffer()` | Shared buffer drain for control mode clients |
| `control.c:44-75` | `struct control_block`, `struct control_pane` | Per-client output block and offset structures |
| `control.c:130-138` | `CONTROL_BUFFER_*` | Control mode buffer watermarks |
| `control.c:267-276` | `control_discard_pane()` | Discard all pending output for one pane |
| `control.c:360-370` | `control_continue_pane()` | Resume after pause: reset offsets to current |
| `control.c:432-464` | `control_check_age()` | Age-based slow client detection |
| `control.c:468-518` | `control_write_output()` | Queue raw PTY output per control client per pane |
| `control.c:728-761` | `control_write_callback()` | Drain pending blocks to client with fair scheduling |
| `server-fn.c:34-37` | `server_redraw_client()` | Mark client for full redraw |
| `tmux.h:1200-1201` | `PANE_REDRAW`, `PANE_DROP` | Per-pane redraw flags |
| `tmux.h:1575-1658` | `struct tty` | Per-client terminal state (cursor, attrs, out buffer) |
| `tmux.h:2003-2046` | `CLIENT_REDRAW*` flags | Per-client redraw scope selectors |
| `window.c:1024-1050` | `window_pane_read_callback()` | PTY read: dispatch to control clients, parse VT |
| `window.c:1729-1747` | `window_pane_get_new_data()` | Get unread data from shared pane buffer |
