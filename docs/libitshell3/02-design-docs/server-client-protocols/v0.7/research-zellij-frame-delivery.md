# Research: zellij Multi-Client Frame Delivery

**Date**: 2026-03-05
**Researcher**: zellij-expert
**Purpose**: Prior-art evidence for I-frame/P-frame design discussion (Issues 22-24)

## 1. Per-Client Render State

### Terminal Panes: Single Authoritative Grid, Shared Output

Terminal panes (`TerminalPane`) contain a **single** `Grid` instance that holds the authoritative terminal state. There is no per-client Grid for terminal panes.

The `Grid` contains a single `OutputBuffer` that tracks which lines have changed since the last render:

```rust
// zellij-server/src/panes/grid.rs (fields on Grid struct)
pub should_render: bool,
// ...
// zellij-server/src/output/mod.rs:1071-1075
pub struct OutputBuffer {
    pub changed_lines: HashSet<usize>, // line index
    pub should_update_all_lines: bool,
    styled_underlines: bool,
}
```

When the Grid renders, it reads changed chunks from the `OutputBuffer` and then **clears** the buffer:

```rust
// zellij-server/src/panes/grid.rs:1105-1132
pub fn read_changes(&mut self, x_offset: usize, y_offset: usize)
    -> (Vec<CharacterChunk>, Vec<SixelImageChunk>) {
    let changed_character_chunks = self.output_buffer.changed_chunks_in_viewport(/*...*/);
    // ...
    self.output_buffer.clear();
    (changed_character_chunks, changed_sixel_image_chunks)
}
```

This means dirty state is consumed on render. After `read_changes()` returns, the `OutputBuffer` is empty until new terminal output arrives. This is relevant to multi-client: all regular clients share the same dirty-tracking state.

**Source files**:
- `zellij-server/src/panes/terminal_pane.rs:127-156` (TerminalPane struct: single `grid: Grid`)
- `zellij-server/src/panes/grid.rs:1105-1132` (read_changes consumes output_buffer)
- `zellij-server/src/output/mod.rs:1071-1108` (OutputBuffer struct and clear/update methods)

### Plugin Panes: Per-Client Grids

In contrast, `PluginPane` maintains a **per-client** Grid and per-client `should_render` flag:

```rust
// zellij-server/src/panes/plugin_pane.rs:76-95
pub(crate) struct PluginPane {
    pub should_render: HashMap<ClientId, bool>,
    // ...
    grids: HashMap<ClientId, Grid>,
    // ...
}
```

Each client gets its own VTE parser and Grid for plugins because plugins produce per-client output (different UI views per user). The `get_or_create_grid!` macro lazily creates a new Grid when a new client_id is first seen.

**Source files**:
- `zellij-server/src/panes/plugin_pane.rs:47-74` (get_or_create_grid! macro)
- `zellij-server/src/panes/plugin_pane.rs:76-95` (PluginPane struct with per-client maps)
- `zellij-server/src/panes/plugin_pane.rs:393-421` (render() method: per-client rendering)

### The Output Struct: Per-Client Serialization

The server-side `Output` struct aggregates render output into per-client `HashMap`s:

```rust
// zellij-server/src/output/mod.rs:299-312
pub struct Output {
    pre_vte_instructions: HashMap<ClientId, Vec<String>>,
    post_vte_instructions: HashMap<ClientId, Vec<String>>,
    client_character_chunks: HashMap<ClientId, Vec<CharacterChunk>>,
    sixel_chunks: HashMap<ClientId, Vec<SixelImageChunk>>,
    // ...
}
```

For terminal panes, the same `CharacterChunk` data is **cloned** to each client:

```rust
// zellij-server/src/output/mod.rs:361-373
pub fn add_character_chunks_to_multiple_clients(&mut self,
    character_chunks: Vec<CharacterChunk>,
    client_ids: impl Iterator<Item = ClientId>,
    z_index: Option<usize>,
) -> Result<()> {
    for client_id in client_ids {
        self.add_character_chunks_to_client(client_id, character_chunks.clone(), z_index)
            // TODO: forgo clone by adding an all_clients thing?
    }
    Ok(())
}
```

The TODO comment is significant: the zellij developers are aware this cloning is suboptimal.

The final serialization (`Output::serialize()`) produces a `HashMap<ClientId, String>` where each value is VTE escape sequence data. For terminal panes the content is typically identical across clients (same pane content), but can differ due to different cursor positions, selections, or frame rendering (e.g., which pane border is highlighted).

**Source files**:
- `zellij-server/src/output/mod.rs:299-312` (Output struct)
- `zellij-server/src/output/mod.rs:361-373` (clone-per-client TODO)
- `zellij-server/src/output/mod.rs:464-510` (serialize into HashMap<ClientId, String>)

## 2. Bounded Channel Behavior

### Inter-Thread Channels: Mostly Unbounded

The channels between server threads (screen, pty, plugin, background_jobs) are **unbounded**, with two exceptions:

```rust
// zellij-server/src/lib.rs:1718-1736
let (to_screen, screen_receiver) = channels::unbounded();    // screen: unbounded
let (to_screen_bounded, bounded_screen_receiver) = channels::bounded(50);  // bounded backup
let (to_plugin, plugin_receiver) = channels::unbounded();    // plugin: unbounded
let (to_pty, pty_receiver) = channels::unbounded();          // pty: unbounded
let (to_pty_writer, pty_writer_receiver) = channels::unbounded();  // pty_writer: unbounded
let (to_background_jobs, background_jobs_receiver) = channels::unbounded();  // bg: unbounded
```

The server-to-client channel is bounded at 50:
```rust
// zellij-server/src/lib.rs:670
let (to_server, server_receiver) = channels::bounded(50);
```

### Client Delivery: Bounded 5000 + try_send + Disconnect

Each client gets its own `ClientSender` with a **bounded(5000)** crossbeam channel:

```rust
// zellij-server/src/os_input_output.rs:176-232
struct ClientSender {
    client_id: ClientId,
    client_buffer_sender: channels::Sender<ServerToClientMsg>,
}
```

The behavior when the buffer is full:

1. The `send_or_buffer()` method uses `try_send()` (non-blocking).
2. If `TrySendError::Full`, it logs a warning and returns an error.
3. The caller (`send_to_client!` macro in `lib.rs:480-500`) catches this error, matches on `ZellijError::ClientTooSlow`, and **removes the client entirely**.

```rust
// zellij-server/src/lib.rs:480-500
macro_rules! send_to_client {
    ($client_id:expr, $os_input:expr, $msg:expr, $session_state:expr) => {
        let send_to_client_res = $os_input.send_to_client($client_id, $msg);
        if let Err(e) = send_to_client_res {
            let context = match e.downcast_ref::<ZellijError>() {
                Some(ZellijError::ClientTooSlow { .. }) => { /* log */ },
                _ => { /* log */ },
            };
            Err::<(), _>(e).context(context).non_fatal();
            remove_client!($client_id, $os_input, $session_state);
        }
    };
}
```

The developers left a detailed comment acknowledging this is a known limitation:

> "This queue is responsible for buffering messages between server and client. If it fills up, the client is disconnected with a 'Buffer full' sort of error message. It was previously found to be too small (with depth 50), so it was increased to 5000 instead. [...] If in the future this is found to fill up too quickly again, it may be worthwhile to increase the size even further (or better yet, implement a redraw-on-backpressure mechanism). We, the zellij maintainers, have decided against an unbounded queue for the time being because we want to prevent e.g. the whole session being killed (by OOM-killers or some other mechanism) just because a single client doesn't respond."

The key phrase is "implement a redraw-on-backpressure mechanism" -- they acknowledge the current approach of disconnect-on-overflow is suboptimal and that a mechanism closer to I-frame/keyframe recovery would be better.

A dedicated sender thread per client consumes from this bounded channel and writes to the Unix socket:

```rust
// zellij-server/src/os_input_output.rs:194-205
std::thread::spawn(move || {
    for msg in client_buffer_receiver.iter() {
        sender.send_server_msg(msg).non_fatal();
    }
    let _ = sender.send_server_msg(ServerToClientMsg::Exit {
        exit_reason: ExitReason::Disconnect,
    });
});
```

**Source files**:
- `zellij-server/src/os_input_output.rs:166-232` (ClientSender: bounded(5000), try_send, sender thread)
- `zellij-server/src/lib.rs:466-500` (remove_client! and send_to_client! macros)
- `zellij-server/src/lib.rs:670` (server channel: bounded(50))
- `zellij-server/src/lib.rs:1718-1736` (inter-thread channels: mostly unbounded)
- `zellij-utils/src/errors.rs:669` (ZellijError::ClientTooSlow definition)

## 3. Full Screen Redraws

### OutputBuffer Defaults to Full Render on First Draw

The `OutputBuffer` initializes with `should_update_all_lines: true`:

```rust
// zellij-server/src/output/mod.rs:1077-1084
impl Default for OutputBuffer {
    fn default() -> Self {
        OutputBuffer {
            changed_lines: HashSet::new(),
            should_update_all_lines: true, // first time we should do a full render
            styled_underlines: true,
        }
    }
}
```

This ensures the first render is always a complete screen draw.

### set_force_render Triggers Full Redraws

The `set_force_render` mechanism is used throughout the codebase to trigger full screen redraws. The `Grid::mark_for_rerender()` method calls `output_buffer.update_all_lines()`:

```rust
// zellij-server/src/panes/grid.rs:598-601
pub fn mark_for_rerender(&mut self) {
    self.should_render = true;
    self.output_buffer.update_all_lines();
}
```

`set_force_render` is called in numerous situations beyond resize:
- Tab switching (`set_force_render()` on all panes in newly visible tab)
- Pane addition/removal
- Tab closure (force render on remaining tabs)
- Layout changes
- Watcher client connection
- Pane focus changes in some cases

For example, when closing a tab:
```rust
// zellij-server/src/screen.rs:1610-1613
for t in self.tabs.values_mut() {
    if visible_tab_indices.contains(&t.id) {
        t.set_force_render();
```

### Watcher Clients Get Forced Full Renders

Watcher clients (read-only observers) have a `should_force_render` flag in `WatcherState`:

```rust
// zellij-server/src/screen.rs:1014-1026
pub(crate) struct WatcherState {
    size: Size,
    should_force_render: bool,
}
impl WatcherState {
    pub fn new(size: Size) -> Self {
        WatcherState { size, should_force_render: true }
    }
}
```

Watchers get forced full renders on:
- Initial connection (`should_force_render: true` by default)
- Resize (`set_force_render()`)
- When no regular clients exist

During `render_to_clients()`, the watcher rendering phase checks:
```rust
// zellij-server/src/screen.rs:1860-1874
let any_watcher_needs_force_render = self.watcher_clients.values()
    .any(|state| state.should_force_render());
let should_force_render = non_watcher_output_was_dirty
    || any_watcher_needs_force_render
    || !has_regular_clients;
if should_force_render {
    tab.set_force_render();
}
```

### No Periodic Proactive Redraws for Error Recovery

There is **no** periodic timer-based full redraw for error recovery. Full redraws are triggered only by specific events (listed above). If rendering state gets corrupted, there is no self-healing mechanism.

**Source files**:
- `zellij-server/src/output/mod.rs:1077-1084` (OutputBuffer default: full render on first draw)
- `zellij-server/src/panes/grid.rs:598-601` (mark_for_rerender)
- `zellij-server/src/screen.rs:1014-1026` (WatcherState with force_render)
- `zellij-server/src/screen.rs:1860-1912` (watcher force render logic)
- `zellij-server/src/screen.rs:1608-1613` (set_force_render on tab close)

## 4. Plugin vs Terminal Pane Rendering

### Terminal Panes: Single Grid, Client-Agnostic Content

Terminal panes have one `Grid` that processes VTE bytes from the PTY. Content is the same for all clients. The render path:

1. PTY bytes arrive via `ScreenInstruction::PtyBytes(terminal_id, vte_bytes)`
2. The Grid processes bytes through its VTE parser, updating `viewport` and `output_buffer`
3. On render, `TerminalPane::render()` calls `grid.render()` which calls `read_changes()`
4. Changed character chunks are added to all connected clients identically via `add_character_chunks_to_multiple_clients()`

The terminal pane's `render()` method ignores `client_id`:
```rust
// zellij-server/src/panes/terminal_pane.rs:320-342
fn render(&mut self, _client_id: Option<ClientId>)
    -> Result<Option<(Vec<CharacterChunk>, Option<String>, Vec<SixelImageChunk>)>> {
    if self.should_render() {
        // ...
        match self.grid.render(content_x, content_y, &self.style) { /* ... */ }
    }
}
```

### Plugin Panes: Per-Client Grid, Per-Client Content

Plugin panes run WASM plugins that generate per-client VTE output. The rendering path:

1. Plugin generates render output as VTE bytes per client via `PluginRenderAsset { client_id, plugin_id, bytes }`
2. `ScreenInstruction::PluginBytes` delivers these to the tab, which dispatches to the plugin pane
3. Each client's bytes are parsed through that client's dedicated VTE parser into that client's dedicated `Grid`
4. On render, the plugin pane renders each client separately:

```rust
// zellij-server/src/panes/plugin_pane.rs:393-421
fn render(&mut self, client_id: Option<ClientId>)
    -> Result<Option<(Vec<CharacterChunk>, Option<String>, Vec<SixelImageChunk>)>> {
    if client_id.is_none() { return Ok(None); }
    if let Some(client_id) = client_id {
        if self.should_render.get(&client_id).copied().unwrap_or(false) {
            if let Some(grid) = self.grids.get_mut(&client_id) {
                match grid.render(content_x, content_y, &self.style) { /* ... */ }
            }
        }
    }
}
```

### Tiled Panes Render: Different Paths for Terminal vs Plugin

In `TiledPanes::render()`, the dispatching differs:

```rust
// zellij-server/src/panes/tiled_panes/mod.rs:1043-1061
for (kind, pane) in self.panes.iter_mut() {
    match kind {
        PaneId::Terminal(_) => {
            output.add_pane_contents(
                &connected_clients,      // ALL clients at once
                pane.pid(),
                pane.pane_contents(None, false),
            );
        },
        PaneId::Plugin(_) => {
            for client_id in &connected_clients {
                output.add_pane_contents(
                    &[*client_id],       // ONE client at a time
                    pane.pid(),
                    pane.pane_contents(Some(*client_id), false),
                );
            }
        },
    }
}
```

Terminal pane contents go to all clients in one call; plugin pane contents are fetched per-client individually.

**Source files**:
- `zellij-server/src/panes/terminal_pane.rs:320-342` (terminal render ignores client_id)
- `zellij-server/src/panes/plugin_pane.rs:393-421` (plugin render per-client)
- `zellij-server/src/panes/tiled_panes/mod.rs:1043-1061` (dispatch difference)
- `zellij-server/src/plugins/wasm_bridge.rs:63-69` (PluginRenderAsset: per-client bytes)
- `zellij-server/src/screen.rs:4400-4417` (PluginBytes handling)

## 5. Multi-Client Output Routing

### Session Mirroring vs Independent Tabs

zellij supports two multi-client modes controlled by `session_is_mirrored`:

- **Mirrored** (`session_is_mirrored: true`): All clients see the same tab. Tab switching moves all clients together. This is the default.
- **Non-mirrored**: Each client can view a different tab independently. Each client has its own `active_tab_id`.

In both modes, each `Tab` tracks its own set of `connected_clients: Rc<RefCell<HashSet<ClientId>>>`, while the `Screen` maintains the global `connected_clients: Rc<RefCell<HashMap<ClientId, bool>>>`.

```rust
// zellij-server/src/screen.rs:1067
connected_clients: Rc<RefCell<HashMap<ClientId, bool>>>, // bool -> is_web_client
// zellij-server/src/tab/mod.rs:176
connected_clients: Rc<RefCell<HashSet<ClientId>>>,
```

### Render-to-Client Pipeline: Two Phases

The `render_to_clients()` method has two distinct phases:

**Phase 1: Regular clients** — Renders all tabs for regular clients. The `Output` struct collects per-client character chunks. After serialization, the result `HashMap<ClientId, String>` is sent to the server thread via `ServerInstruction::Render(Some(serialized_output))`.

**Phase 2: Watcher clients** — Creates a separate `Output` for watchers. Watchers always follow a single "followed" client (set by `followed_client_id`). The output is re-rendered from the followed client's active tab and then serialized per-watcher with size constraints (cropping/padding for different watcher terminal sizes).

The server thread then iterates the HashMap and delivers to each client individually:
```rust
// zellij-server/src/lib.rs:1319-1333
ServerInstruction::Render(serialized_output) => {
    let client_ids = session_state.read().unwrap().client_ids();
    if let Some(output) = &serialized_output {
        for (client_id, client_render_instruction) in output.iter() {
            send_to_client!(
                *client_id, os_input,
                ServerToClientMsg::Render { content: client_render_instruction.clone() },
                session_state
            );
        }
    }
}
```

### Render Debouncing: 10ms Coalescing

Render requests are debounced via a background job with a 10ms delay:

```rust
// zellij-server/src/background_jobs.rs:116
static REPAINT_DELAY_MS: u64 = 10;
```

The debounce mechanism:
1. `Screen::render()` sends `BackgroundJob::RenderToClients` to the background thread.
2. The background thread records the timestamp and spawns an async task that sleeps 10ms, then sends `ScreenInstruction::RenderToClients` back to the screen thread.
3. If additional render requests arrive during the 10ms sleep, the timestamp is updated. After the sleep, the background thread checks if the timestamp was updated and, if so, re-schedules itself.

This ensures at most ~100 renders/second, coalescing rapid terminal output.

### Slow Client Handling: Disconnect, No Degradation

There is **no** per-client buffering with graceful degradation. The handling is binary:

1. Server renders and serializes output for all clients (shared work).
2. Each client's serialized VTE string is sent via `send_to_client!`.
3. `ClientSender::send_or_buffer()` uses `try_send()` on the bounded(5000) channel.
4. If the channel is full, the error propagates up and `remove_client!` disconnects the client.
5. A disconnected client's sender thread sends a final `ServerToClientMsg::Exit` with `ExitReason::Disconnect`.

There is no mechanism to:
- Drop frames for slow clients while keeping them connected
- Send keyframes to help slow clients catch up
- Reduce render quality/frequency for individual clients
- Buffer and coalesce multiple frames into a single update for slow clients

The only mitigation is the 10ms debouncing, which limits render frequency globally (not per-client).

### ServerToClientMsg: VTE Strings, Not Structured Data

The render message sent to clients is a raw VTE string:
```rust
// zellij-utils/src/ipc.rs:155-158
pub enum ServerToClientMsg {
    Render { content: String },
    // ...
}
```

This is a pre-serialized terminal escape sequence, not structured cell data. There is no concept of I-frames vs P-frames at the protocol level.

**Source files**:
- `zellij-server/src/screen.rs:1727-1922` (render_to_clients: two-phase rendering)
- `zellij-server/src/screen.rs:1081` (session_is_mirrored field)
- `zellij-server/src/screen.rs:1110-1111` (watcher_clients, followed_client_id)
- `zellij-server/src/screen.rs:2280-2357` (add_client, remove_client, add_watcher_client)
- `zellij-server/src/lib.rs:1319-1333` (ServerInstruction::Render delivery loop)
- `zellij-server/src/background_jobs.rs:116,449-496` (10ms debounce)
- `zellij-utils/src/ipc.rs:155-158` (ServerToClientMsg::Render)

## 6. Additional Findings

### OutputBuffer Changed-Lines Tracking as Primitive Dirty Rects

The `OutputBuffer::changed_chunks_in_viewport()` method acts as a primitive dirty-rect system:

- When `should_update_all_lines` is true, all lines are emitted (equivalent to an I-frame).
- Otherwise, only lines in `changed_lines` are emitted (equivalent to a P-frame with per-line granularity).
- The `changed_rects_in_viewport()` method groups adjacent changed lines into contiguous rectangles.

This is the closest zellij comes to an I-frame/P-frame model, but it operates at the per-pane Grid level, not at the wire protocol level. By the time data reaches the client, it's all serialized VTE escape sequences with no frame type metadata.

### RenderBlocker: Plugin Render Synchronization

A `RenderBlocker` mechanism in the screen thread prevents rendering until all pending plugin layouts have been applied, with a 100ms timeout fallback:

```rust
// zellij-server/src/screen.rs:4421-4429
ScreenInstruction::RenderToClients => {
    if screen.render_blocker.can_render() {
        screen.render_to_clients()?;
    } else {
        screen.render(None)?;  // re-schedule
    }
}
```

This prevents partial-state rendering during layout transitions.

### Grid Output Buffer Is Consumed Destructively

A critical detail: `read_changes()` calls `self.output_buffer.clear()` after reading. This means if the render for watcher clients happens after the regular client render, the output buffer is already empty. The watcher rendering phase works around this by calling `tab.set_force_render()` before rendering, which sets `should_update_all_lines = true` on all panes.

This is a direct consequence of not having an explicit I-frame/P-frame model. The force_render acts as an ad-hoc "generate a keyframe now" mechanism.

## Summary

Key patterns relevant to the I-frame/P-frame design discussion:

1. **No I-frame/P-frame model**: zellij has no explicit frame typing. The `OutputBuffer` provides implicit dirty tracking (changed lines = delta, all lines = full), but this is internal to each Grid and not exposed at the protocol level.

2. **Destructive dirty-state consumption**: `read_changes()` clears the output buffer, making it impossible to serve the same delta to a second consumer (e.g., a late-joining watcher). The workaround is `set_force_render()`, which regenerates a full frame. This is the exact problem an I-frame/ring-buffer design would solve.

3. **Slow client handling is binary**: buffer 5000 messages or disconnect. No graceful degradation. The developers explicitly acknowledge wanting "a redraw-on-backpressure mechanism" (their words in the source comment) but have not implemented one.

4. **Per-client serialization, not per-client state**: For terminal panes, all clients get cloned copies of the same character chunks. The Output struct maintains per-client buckets, but the content is identical for terminal panes (differing only for plugin panes). This cloning is acknowledged as suboptimal with a TODO comment.

5. **Render debouncing at 10ms**: Global, not per-client. This limits the server to ~100 renders/second regardless of client count or capacity.

6. **Watcher rendering re-renders from scratch**: Because dirty state is consumed by the regular client render, watcher rendering must force a full re-render of the tab. This doubles the rendering cost when watchers are connected.

7. **VTE string protocol**: The wire format is raw VTE escape sequences (a `String`), not structured cell data. There is no mechanism for the client to request retransmission or for the server to send recovery frames.
