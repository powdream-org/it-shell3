# Research: tmux Multi-Client Frame Delivery

**Date**: 2026-03-05
**Researcher**: tmux-expert
**Purpose**: Prior-art evidence for I-frame/P-frame design discussion (Issues 22-24)

## 1. Per-Client Output Buffering

### Terminal Clients (Normal Mode)

Each terminal client has a **per-client `struct tty`** containing its own output buffer (`tty->out`, an `evbuffer`). Output is **not shared** between clients.

**Source**: `tmux.h:1613`, `tty.c:289-292`

The `struct tty` (embedded in each `struct client` at `tmux.h:1981`) contains:

```c
struct evbuffer	*out;       // tmux.h:1613 — per-client output buffer
size_t		 discarded; // tmux.h:1615 — bytes discarded while blocked
```

When the server processes pane output through VT parsing (`input.c`), it calls `screen_write_*` functions which invoke `tty_write()`. This function iterates over **all clients** and writes terminal escape sequences independently to each client's `tty->out` buffer:

```c
void
tty_write(void (*cmdfn)(struct tty *, const struct tty_ctx *),
    struct tty_ctx *ctx)
{
    struct client	*c;
    TAILQ_FOREACH(c, &clients, entry) {
        if (tty_client_ready(ctx, c)) {
            state = ctx->set_client_cb(ctx, c);
            if (state == 1)
                cmdfn(&c->tty, ctx);    // writes to THIS client's tty->out
        }
    }
}
```

**Source**: `tty.c:1549-1568`

This is a **fan-out model**: the authoritative screen state is updated once, then each client's tty output is generated independently. There is no shared ring buffer.

### TTY_BLOCK and TTY_NOBLOCK

`TTY_BLOCK` and `TTY_NOBLOCK` are per-client flags on `tty->flags` that control output throttling.

- **`TTY_BLOCK` (`0x80`)** -- Set when the client's output buffer exceeds a threshold. While set, all subsequent output for that client is **discarded** (counted but not buffered). Defined at `tmux.h:1630`.
- **`TTY_NOBLOCK` (`0x8`)** -- Set for operations that must not be blocked (clipboard writes via OSC 52, raw passthrough strings, sixel images). While set, `tty_block_maybe()` returns immediately without entering block mode. Defined at `tmux.h:1626`.

The block threshold is proportional to terminal size:

```c
#define TTY_BLOCK_START(tty) (1 + ((tty)->sx * (tty)->sy) * 8)
#define TTY_BLOCK_STOP(tty)  (1 + ((tty)->sx * (tty)->sy) / 8)
```

**Source**: `tty.c:80-82`

For a typical 80x24 terminal, `TTY_BLOCK_START` = 15,361 bytes, `TTY_BLOCK_STOP` = 241 bytes. The start threshold is approximately 8 screenfuls of raw characters.

### Control Clients (-CC Mode)

Control clients use a completely different buffering model defined in `control.c`. Each control client has:

- A `struct control_state` with a per-pane red-black tree (`control_panes`) -- `control.c:115-116`
- Each `struct control_pane` has its own queue of `control_block` entries -- `control.c:54-75`
- A global `all_blocks` queue that interleaves `%output` blocks with notification lines -- `control.c:121`
- Per-pane read offsets (`offset` and `queued`) tracking consumption position into the pane's shared input `evbuffer` -- `control.c:62-63`
- Watermark-based flow control: `CONTROL_BUFFER_LOW` (512 bytes) and `CONTROL_BUFFER_HIGH` (8192 bytes) -- `control.c:131-132`

**Source**: `control.c:29-51` (architecture comment), `control.c:54-128` (data structures)

## 2. Dirty State Tracking

### Pane-Level Dirty Flag (Global, Not Per-Client)

tmux uses a **single global** `PANE_REDRAW` flag on `window_pane->flags` (`tmux.h:1200`). This flag is **not per-client** -- it is set on the pane itself and signals that all clients viewing this pane need a redraw.

The flag is set in several circumstances:
- VT input parsing triggers it for certain sequences (e.g., `DA` response) -- `input.c:1915`
- Pane resize -- `window.c:1137`
- Theme/style changes -- `window.c:576-586`
- Pane respawn -- `cmd-respawn-pane.c:90`

### Per-Client Deferred Redraw Bitmask

While `PANE_REDRAW` is global, there is a per-client deferred mechanism. When a client has outstanding output in its `tty->out` buffer, the redraw is deferred, and the needed panes are recorded in per-client bitmasks:

```c
uint64_t  redraw_panes;      // tmux.h:2073 — bitmask of panes needing redraw
uint64_t  redraw_scrollbars;  // tmux.h:2074 — bitmask for scrollbar redraws
```

This limits tracking to 64 panes per window; if a window has more than 64 panes, tmux falls back to `CLIENT_REDRAWWINDOW` (full window redraw).

**Source**: `server-client.c:3239-3267`

### Redraw Is Always From Authoritative State

tmux does **not** compute diffs between old and new screen state. When a pane needs redrawing, `screen_redraw_draw_pane()` walks every row of the pane's `screen` and calls `tty_draw_line()` to emit the terminal escape sequences for each cell.

**Source**: `screen-redraw.c:939-1008`

The authoritative state is `wp->screen` (points to either `wp->base` for normal mode or a mode-specific screen). There is no concept of "previous frame" or delta encoding -- every redraw re-reads the full screen grid.

### No Per-Client Screen Shadow

tmux does not maintain a per-client copy of what was last sent. The `tty` struct tracks cursor position (`tty->cx`, `tty->cy`), current cell attributes (`tty->cell`), and scroll region state, but not a full screen image. The `tty_invalidate()` function resets these cached values, forcing the next redraw to re-emit all positioning and attribute commands.

**Source**: `tty.c:2216-2231`

## 3. Discard and Redraw Pattern

### Terminal Clients: Discard-Then-Full-Redraw

When a terminal client cannot keep up, tmux implements a **discard-and-full-redraw** cycle:

**Step 1 -- Detect overload**: `tty_block_maybe()` checks if `tty->out` exceeds `TTY_BLOCK_START`. If so, it drains the entire output buffer, sets `TTY_BLOCK`, and starts a 100ms timer.

```c
tty->flags |= TTY_BLOCK;
evbuffer_drain(tty->out, size);   // discard everything pending
c->discarded += size;
evtimer_add(&tty->timer, &tv);    // 100ms timer
```

**Source**: `tty.c:212-239`

**Step 2 -- Discard all output while blocked**: While `TTY_BLOCK` is set, `tty_add()` silently discards all output:

```c
if (tty->flags & TTY_BLOCK) {
    tty->discarded += len;
    return;
}
```

**Source**: `tty.c:620-628`

**Step 3 -- Timer fires, request full redraw**: When the 100ms timer fires (`tty_timer_callback`), it sets `CLIENT_ALLREDRAWFLAGS` on the client:

```c
c->flags |= CLIENT_ALLREDRAWFLAGS;
```

If the amount discarded during the timer interval has dropped below `TTY_BLOCK_STOP`, the block is cleared and `tty_invalidate()` resets all cached TTY state. Otherwise, the timer is re-armed for another 100ms.

**Source**: `tty.c:191-210`

**Step 4 -- Full redraw on next event loop**: In the next `server_client_loop()` iteration, `server_client_check_redraw()` sees `CLIENT_ALLREDRAWFLAGS` and calls `screen_redraw_screen()`, which redraws the entire display (borders, all panes, status line) from the authoritative screen state.

**Source**: `server-client.c:3308-3314`

### Terminal Clients: Redraw Buffer Protection

After a full redraw completes, tmux records how many bytes the redraw produced:

```c
c->redraw = EVBUFFER_LENGTH(tty->out);
```

While `c->redraw > 0`, the `tty_write_callback()` decrements it as bytes are written and **does not check `tty_block_maybe()`**. This prevents the redraw output itself from being immediately discarded.

**Source**: `server-client.c:3323-3331`, `tty.c:254-262`

### Control Clients: Pause or Disconnect

Control clients have a different model. Each `control_block` is timestamped (`cb->t`). The function `control_check_age()` computes the age of the oldest pending block:

- If the client supports `pause-after` (`CLIENT_CONTROL_PAUSEAFTER`), and the age exceeds `c->pause_age`, the pane is **paused**: all queued blocks for that pane are discarded, and `%pause %%%u` is sent to the client. The client must explicitly `send-keys -t %%%u` or similar to continue.

- If the client does NOT support `pause-after`, and the age exceeds `CONTROL_MAXIMUM_AGE` (300,000 microseconds = 300ms), the **entire client is disconnected** with the message "too far behind".

```c
if (c->flags & CLIENT_CONTROL_PAUSEAFTER) {
    cp->flags |= CONTROL_PANE_PAUSED;
    control_discard_pane(c, cp);
    control_write(c, "%%pause %%%u", wp->id);
} else {
    c->exit_message = xstrdup("too far behind");
    c->flags |= CLIENT_EXIT;
    control_discard(c);
}
```

**Source**: `control.c:431-464`

When a paused pane is continued (`control_continue_pane()`), its offsets are reset to the pane's current position, effectively jumping to the latest state and discarding all intermediate output:

```c
memcpy(&cp->offset, &wp->offset, sizeof cp->offset);
memcpy(&cp->queued, &wp->offset, sizeof cp->queued);
control_write(c, "%%continue %%%u", wp->id);
```

**Source**: `control.c:359-371`

## 4. Full Redraw Triggers

### Terminal Clients

Full redraw (`CLIENT_REDRAWWINDOW` and/or `CLIENT_ALLREDRAWFLAGS`) is triggered by:

1. **Client attach** -- `server_client_dispatch()` sets `CLIENT_ALLREDRAWFLAGS` on `MSG_IDENTIFY_DONE` -- `server-client.c:3460`
2. **Terminal resize** -- `MSG_RESIZE` handler calls `server_redraw_client(c)` which sets `CLIENT_ALLREDRAWFLAGS` -- `server-client.c:3431`, `server-fn.c:34-37`
3. **TTY_BLOCK recovery** -- Timer callback sets `CLIENT_ALLREDRAWFLAGS` -- `tty.c:200`
4. **TTY re-open** (e.g., `SIGCONT` after `SIGSTOP`) -- calls `server_redraw_client()` -- `tty.c:549`
5. **Session switch** -- `server_client_set_session()` calls `server_redraw_client()` -- `server-client.c:438`
6. **Explicit refresh** -- `refresh-client` command -- `cmd-refresh-client.c:252`
7. **Option changes** -- style/theme changes call `server_redraw_client()` -- `options.c:1265`
8. **>64 panes** -- When a window has more than 64 panes, the per-pane bitmask overflows and falls back to `CLIENT_REDRAWWINDOW` -- `server-client.c:3250-3258`

Incremental (per-pane) redraws occur when:
- `PANE_REDRAW` is set on a specific pane (from VT input, style change, etc.)
- The client's output buffer is empty (no deferral needed)

**There are no periodic full redraws.** tmux never sends a full redraw on a timer -- only in response to specific events. This is relevant to the I-frame/P-frame discussion: tmux has no concept of periodic keyframes.

### Redraw Deferral

If a client has pending output (`EVBUFFER_LENGTH(tty->out) != 0`) when a redraw is needed, the redraw is **deferred**: the panes needing redraw are recorded in `c->redraw_panes` bitmask and a 1ms timer is set to re-enter `server_client_check_redraw()`.

```c
if (needed && (left = EVBUFFER_LENGTH(tty->out)) != 0) {
    log_debug("%s: redraw deferred (%zu left)", c->name, left);
    // ... record which panes need redraw in bitmask ...
    return;
}
```

**Source**: `server-client.c:3230-3267`

### Control Clients (-CC Mode)

Control clients skip `server_client_check_redraw()` entirely:

```c
if (c->flags & (CLIENT_CONTROL|CLIENT_SUSPENDED))
    return;
```

**Source**: `server-client.c:3196-3197`

Control clients do not receive terminal escape sequences. Instead, they receive `%output` or `%extended-output` lines containing the raw PTY output for each pane. Resize triggers `%layout-change` notifications via `control-notify.c`, and the control client (e.g., iTerm2) is responsible for its own VT parsing and rendering.

## 5. Control Mode Output

### Buffering Architecture

Control mode output uses a two-tier queue system (documented in the comment at `control.c:29-43`):

1. **Per-pane queue** (`cp->blocks`): Holds `%output` blocks with their byte sizes.
2. **Client-wide queue** (`cs->all_blocks`): Interleaves `%output` blocks with notification lines (`%layout-change`, `%window-close`, etc.). Notifications are blocks with `size == 0` (no pane data).

The ordering rule: a `%output` block in the client-wide queue **holds up** all subsequent notification lines until it is fully written. This preserves the causal ordering between output and structural changes.

### Flow Control: Watermarks and Fair Scheduling

The write callback (`control_write_callback`, `control.c:727-761`) implements watermark-based flow control:

- Writing stops when the output buffer reaches `CONTROL_BUFFER_HIGH` (8192 bytes).
- Writing resumes when the buffer drains to `CONTROL_BUFFER_LOW` (512 bytes).
- Available space is divided fairly among pending panes: `limit = space / pending_count / 3` (the `/3` accounts for octal escaping overhead `\xxx`).
- Each pane gets at least `CONTROL_WRITE_MINIMUM` (32 bytes) per round.

**Source**: `control.c:130-136`, `control.c:727-761`

### PTY Data as Byte Stream (Not Coalesced)

In control mode, the server does NOT parse VT sequences or maintain screen state for the client. Instead, raw PTY bytes are forwarded via `control_write_output()`, which reads new data from the pane's shared `evbuffer` using per-client offsets:

```c
window_pane_get_new_data(wp, &cp->queued, &new_size);
```

The data is escaped (non-printable bytes become `\xxx` octal) and sent as `%output %%%u <data>` lines. The control client is responsible for its own VT state machine.

**Source**: `control.c:466-518`

### Slow Consumer Handling

Control clients have two slow-consumer strategies:

1. **Pause-after mode** (opt-in via `CLIENT_CONTROL_PAUSEAFTER`): When a pane's oldest pending block exceeds the configured age, that individual pane is paused. The client receives `%pause %%%u` and must explicitly continue. Other panes remain active.

2. **Legacy mode** (default): When the oldest pending block exceeds 300ms (`CONTROL_MAXIMUM_AGE`), the entire client is disconnected.

Additionally, `server_client_check_pane_buffer()` implements **backpressure on PTY reads**: if all attached clients are control clients and none can accept more data, the pane's PTY read event is disabled (`bufferevent_disable(wp->event, EV_READ)`), which causes the PTY buffer to fill and the child process to block on write.

**Source**: `server-client.c:2938-2949`

### Output Is Not Batched or Coalesced

Control mode output is not coalesced across time intervals. Each call to `control_write_output()` (triggered by PTY read events) creates a new block. The write callback drains blocks as fast as the client can accept them, subject to the watermark limits. There is no frame-based batching.

## Summary

### Key Patterns Relevant to I-frame/P-frame Discussion

1. **No shared buffer**: tmux generates output independently per client. Terminal clients get per-client escape sequences; control clients get per-client offset tracking into a shared pane `evbuffer`. There is no shared ring buffer that multiple clients read from.

2. **No delta encoding**: tmux does not compute diffs. When a redraw is needed, it re-renders the full pane (or full window) from authoritative `screen` state. Every "redraw" is effectively an I-frame. There are no P-frames in tmux.

3. **Discard-and-full-redraw as recovery**: When a terminal client falls behind, tmux discards all pending output (not just old frames) and schedules a complete redraw. This is equivalent to "drop all P-frames, send next I-frame." The 100ms timer provides hysteresis to avoid redraw storms.

4. **No periodic keyframes**: Full redraws are event-driven only (resize, attach, recovery from block). tmux never sends periodic full redraws. This is a significant difference from a periodic I-frame model.

5. **Control mode uses byte-stream offsets, not frames**: Control mode tracks consumption positions into raw PTY byte streams, not structured screen state. The pause/continue mechanism is the closest analog to I-frame recovery: when resumed, the client jumps to the latest byte position (skipping all intermediate data).

6. **Per-client dirty state is minimal**: The global `PANE_REDRAW` flag plus per-client 64-bit bitmask for deferred redraws is the extent of dirty tracking. tmux has no per-client "last-sent screen" for diffing.

7. **Backpressure reaches PTY**: When all clients are slow, tmux stops reading from the PTY entirely, letting kernel PTY buffers fill and the child process block. This is an alternative to discarding -- it slows the producer rather than dropping output.

### File Reference Summary

| File | Lines | Relevance |
|------|-------|-----------|
| `tty.c` | 80-82, 191-239, 620-628, 1549-1568, 2216-2231 | TTY_BLOCK mechanism, per-client output, discard pattern, tty_invalidate |
| `server-client.c` | 2704-2759, 2865-2950, 3182-3332 | Event loop, pane buffer management, redraw check/deferral |
| `screen-redraw.c` | 574-606, 644-707, 939-1008 | Full/partial redraw logic, pane drawing |
| `control.c` | 29-128, 265-276, 359-464, 466-518, 727-761 | Control mode architecture, pause/age, output writing, flow control |
| `control-notify.c` | 26-100 | Control mode notification fan-out |
| `tmux.h` | 1156-1158, 1183-1215, 1610-1640, 1947-2074, 2000-2047 | Data structures, flags, client redraw constants |
| `server-fn.c` | 34-37 | `server_redraw_client()` definition |

All paths are relative to `~/dev/git/references/tmux/`.
