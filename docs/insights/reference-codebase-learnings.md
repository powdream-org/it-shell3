# Reference Codebase Learnings

Quick-reference of architectural facts from tmux, zellij, and ghostty relevant to libitshell3 design.

---

## 1. Multi-Client Output Delivery Models

**Per-client rendered output (tmux TTY, zellij)**

- tmux TTY clients: server walks the authoritative grid and emits VT escape sequences per-client into each client's `tty.out` evbuffer. Output differs per client (different terminal capabilities, cursor positions). Inherently O(N) per output event. (tmux `tty_write()`, `tty.c:1549-1568`)
- zellij terminal panes: one authoritative `Grid` per pane, rendered once per cycle, then **cloned** N times at the `Output` layer. Each client gets an independently serialized VTE string. A `TODO` comment acknowledges the clone overhead. (`output/mod.rs:370`)

**Shared buffer with per-client cursors (tmux control mode)**

- tmux `-CC` (control mode): raw PTY bytes accumulate in a shared pane evbuffer. Each control client maintains a per-pane read offset (`control_pane.offset`). The shared buffer is drained only when ALL clients have consumed past a point. This is the closest existing analogue to a shared ring buffer. (`control.c:54-75`, `server-client.c:2879-2906`)

**Single-consumer (ghostty)**

- ghostty has exactly one renderer per terminal. No multi-client delivery. The `RenderState.update()` method consumes dirty flags destructively -- single-consumer by design.

---

## 2. Dirty Tracking Strategies

**Per-pane boolean flag (tmux)**

- A single `PANE_REDRAW` bit on each `window_pane` struct. Not per-row, not per-client. Either the whole pane needs redraw or it doesn't. Per-client scope is controlled by coarse `CLIENT_REDRAW*` bit flags (window, status, panes) and a 64-bit `redraw_panes` bitmask (max 64 panes). (`tmux.h:1200`, `tmux.h:2003-2046`)

**Shared row-level dirty set (zellij terminal panes)**

- `OutputBuffer` contains `changed_lines: HashSet<usize>` plus `should_update_all_lines: bool`. One OutputBuffer per terminal pane, shared across all clients. Dirty state is consumed once per render cycle, not per-client. (`output/mod.rs:1071-1075`)

**Per-client row-level dirty (zellij plugin panes)**

- Plugin panes maintain one `Grid` (with its own `OutputBuffer`) per client. Each client's dirty set is independent. This exists because plugins can produce client-specific content.

**Three-level hierarchy, single-consumer (ghostty)**

- Terminal-level `Dirty` packed struct (palette, reverse_colors, clear, preedit) -- triggers full redraw.
- Page-level `dirty: bool` -- optimization hint for bulk operations.
- Row-level `dirty: bool` -- single bit in a packed 64-bit `Row` struct.
- `RenderState.Dirty` enum: `false` / `partial` / `full`. The `update()` method clears all source dirty flags after reading them. No cell-level tracking. (`render.zig:225-238`)

---

## 3. Frame Recovery Patterns

**Discard-and-full-redraw (tmux TTY)**

- When a client's output buffer overflows `TTY_BLOCK_START` (e.g., 38KB for 120x40): all buffered output discarded, `TTY_BLOCK` flag set, 100ms timer starts. On timer: if drain rate is acceptable, unblock and set `CLIENT_ALLREDRAWFLAGS` for a full redraw from the authoritative grid. No gradual catch-up, no delta accumulation. (`tty.c:212-238`, `tty.c:191-210`)

**Offset reset + client-side capture (tmux control mode)**

- When a control client's oldest undelivered block exceeds `pause_age`: pane is paused, pending blocks discarded, `%pause` notification sent. On `%continue`, client's offset is reset to the pane's current write position. The client (e.g., iTerm2) must request a `capture-pane` to recover full screen state. (`control.c:432-464`, `control.c:360-370`)

**Force render (zellij)**

- `set_force_render()` sets `should_update_all_lines = true` on every pane's OutputBuffer. Triggered by tab switch, tab create/close, new client attach, watcher attach. No periodic keyframe mechanism. (`tab/mod.rs:3013-3016`)

**Periodic state reset (ghostty)**

- Every 100,000 frames (~12 min at 120Hz), the entire `RenderState` is destroyed and rebuilt from scratch. Primarily for memory management (arena peak retention), but effectively a periodic full rebuild. (`generic.zig:1138-1148`)

**No system uses proactive periodic keyframes for multi-client sync.**

---

## 4. Concurrency Models

**Single-threaded event loop (tmux)**

- Everything runs in one thread with libevent. The main loop (`server_client_loop`) checks all windows, then all clients. No locking needed. Output buffering and timer callbacks are all within the same event loop.

**Multi-threaded with bounded channels (zellij)**

- Server thread renders and sends `ServerToClientMsg::Render` to per-client bounded crossbeam channels (depth 5000). Render requests are debounced at 10ms via a background job scheduler. No lock contention on the render path -- communication is via message passing.

**IO thread + renderer thread with shared mutex (ghostty)**

- IO thread processes PTY output, modifies terminal state under `state.mutex`, then notifies renderer via async wakeup. Renderer locks the same mutex during `RenderState.update()` to snapshot state. Critical section is minimized -- only the snapshot phase holds the lock. (`Termio.zig:687-689`, `render.zig:258-648`)
- Implicit coalescing: multiple `notify()` calls between event loop ticks collapse to one renderer wakeup.

---

## 5. Backpressure Handling

**Discard + timer recovery (tmux TTY)**

- Output buffer exceeds threshold -> discard all, block for 100ms, retry. If still overloaded, reschedule timer. On recovery, full redraw. A redraw's output bytes are exempt from the block check to prevent immediate re-block. (`tty.c:254-262`)

**Age-based pause or disconnect (tmux control mode)**

- If oldest undelivered block exceeds `pause_age` (configurable): pause pane, discard pending. If no pause mode and age exceeds 300s: disconnect client ("too far behind"). When ALL control clients are paused/off, PTY reads are disabled entirely (backpressure to child process). (`control.c:432-464`, `server-client.c:2938-2949`)

**Bounded channel with disconnect (zellij)**

- Per-client channel depth 5000. When `try_send` fails with `Full`, the client is disconnected. No render coalescing in the queue, no frame dropping, no resync. Maintainers acknowledge this is suboptimal and note a "redraw-on-backpressure mechanism" would be better. (`os_input_output.rs:176-210`)

**ghostty: not applicable (single-consumer)**

- No backpressure concern. Synchronized output mode (DEC 2026) allows applications to defer rendering voluntarily, but this is cooperative, not backpressure.

---

## 6. Additional Notable Facts

- **tmux control mode notification ordering**: dual-queue design (per-pane + per-client global) ensures `%layout-change` and other notification lines are never reordered past pending `%output` blocks. (`control.c:468-518`)
- **zellij plugin vs terminal pane divergence**: plugin panes need per-client state (different mode indicators, active tab highlights). Terminal panes share one grid. This maps to: shared terminal content + client-specific UI overlays.
- **ghostty Cell is 64 bits packed**: codepoint (21 bits), style_id (indirect), wide marker (2 bits), flags. Styles are reference-counted in a per-page style set. Wide chars use two cells (wide + spacer_tail). (`page.zig:1958-2002`)
- **ghostty RenderState is a recent optimization**: replaced full screen `clone()` which was "repeatedly a bottleneck blocking IO." The snapshot approach with per-row arenas was introduced specifically to reduce critical section time.
- **None of these systems use structured binary cell data on the wire.** tmux sends VT sequences (TTY) or raw PTY bytes (control). zellij sends VTE strings. ghostty has no wire protocol. libitshell3's binary CellData protocol is novel in this space.
