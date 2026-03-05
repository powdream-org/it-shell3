# Research Report: zellij Multi-Client Frame Delivery

> **Date**: 2026-03-05
> **Researcher**: zellij-expert
> **Scope**: Multi-client render state management, bounded channel interaction with render updates, proactive full screen redraws, plugin vs terminal pane rendering pipelines
> **zellij source**: `~/dev/git/references/zellij/`

---

## 1. Per-Client Render State vs Shared Authoritative State

### 1.1 Terminal Panes: One Grid, One OutputBuffer (Shared)

Terminal panes use a **single authoritative `Grid`** that is shared across all clients.

```
// zellij-server/src/panes/terminal_pane.rs:320-341
fn render(
    &mut self,
    _client_id: Option<ClientId>,   // <-- client_id is IGNORED for terminal panes
) -> Result<Option<(Vec<CharacterChunk>, Option<String>, Vec<SixelImageChunk>)>> {
    if self.should_render() {
        match self.grid.render(content_x, content_y, &self.style) {
            Ok(rendered_assets) => {
                self.set_should_render(false);
                return Ok(rendered_assets);
            },
            ...
        }
    }
}
```

The `Grid` struct (`zellij-server/src/panes/grid.rs:353`) contains a single `output_buffer: OutputBuffer` field (line 367). This `OutputBuffer` tracks dirty lines via a `changed_lines: HashSet<usize>` set and a `should_update_all_lines: bool` flag (lines 1071-1075).

**Key fact**: Terminal pane rendering produces one set of `CharacterChunk`s per render cycle, regardless of how many clients are connected. The `_client_id` parameter is explicitly ignored.

### 1.2 Plugin Panes: Per-Client Grids (Separate State)

Plugin panes maintain **one `Grid` per client** via `grids: HashMap<ClientId, Grid>` (`zellij-server/src/panes/plugin_pane.rs:94`).

```
// zellij-server/src/panes/plugin_pane.rs:393-420
fn render(
    &mut self,
    client_id: Option<ClientId>,   // <-- client_id IS used
) -> Result<Option<(Vec<CharacterChunk>, Option<String>, Vec<SixelImageChunk>)>> {
    if let Some(client_id) = client_id {
        if self.should_render.get(&client_id).copied().unwrap_or(false) {
            if let Some(grid) = self.grids.get_mut(&client_id) {
                match grid.render(content_x, content_y, &self.style) { ... }
            }
        }
    }
}
```

Each client's grid has its own `OutputBuffer`, meaning dirty tracking for plugins is per-client. This is because plugins can produce different output for different clients (e.g., showing different mode indicators, focus states, etc.).

### 1.3 How Render Output Reaches Clients

The `Output` struct (`zellij-server/src/output/mod.rs:299`) holds `client_character_chunks: HashMap<ClientId, Vec<CharacterChunk>>` — this is the per-client divergence point.

For **terminal panes**, the tiled_panes render method (`zellij-server/src/panes/tiled_panes/mod.rs:1043-1061`) handles the split:

```rust
// Terminal panes: same content to ALL clients
PaneId::Terminal(_) => {
    output.add_pane_contents(
        &connected_clients,      // all clients
        pane.pid(),
        pane.pane_contents(None, false),
    );
},
// Plugin panes: per-client content
PaneId::Plugin(_) => {
    for client_id in &connected_clients {
        output.add_pane_contents(
            &[*client_id],       // one client at a time
            pane.pid(),
            pane.pane_contents(Some(*client_id), false),
        );
    }
},
```

The `add_character_chunks_to_multiple_clients` method (`output/mod.rs:361-373`) **clones** the character chunks for each client:

```rust
pub fn add_character_chunks_to_multiple_clients(
    &mut self,
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

Note the `TODO` comment acknowledging the clone overhead. The final `serialize()` method (`output/mod.rs:464-505`) produces a `HashMap<ClientId, String>` — **one VTE string per client** — by serializing each client's chunks independently.

### 1.4 Summary

| Pane type | Grid count | OutputBuffer count | Dirty tracking | Render output |
|-----------|-----------|-------------------|----------------|---------------|
| Terminal  | 1 per pane | 1 per pane | Shared (single `changed_lines` set) | Cloned to N clients at `Output` level |
| Plugin    | N per pane (one per client) | N per pane | Per-client | Already separated per client |

**There is no shared ring buffer or deduplication.** Each render cycle clones terminal pane data N times and serializes VTE strings N times.

---

## 2. Bounded Channel (5000 Messages) Interaction with Render Updates

### 2.1 ClientSender Architecture

Each client has a dedicated `ClientSender` with a bounded crossbeam channel of depth 5000 (`zellij-server/src/os_input_output.rs:176-210`):

```rust
struct ClientSender {
    client_id: ClientId,
    client_buffer_sender: channels::Sender<ServerToClientMsg>,
}

impl ClientSender {
    pub fn new(client_id: ClientId, mut sender: IpcSenderWithContext<ServerToClientMsg>) -> Self {
        // FIXME(hartan): This queue is responsible for buffering messages between server and
        // client. If it fills up, the client is disconnected with a "Buffer full" sort of error
        // message. It was previously found to be too small (with depth 50), so it was increased to
        // 5000 instead. This decision was made because it was found that a queue of depth 5000
        // doesn't cause noticable increase in RAM usage, but there's no reason beyond that. If in
        // the future this is found to fill up too quickly again, it may be worthwhile to increase
        // the size even further (or better yet, implement a redraw-on-backpressure mechanism).
        // We, the zellij maintainers, have decided against an unbounded
        // queue for the time being because we want to prevent e.g. the whole session being killed
        // (by OOM-killers or some other mechanism) just because a single client doesn't respond.
        let (client_buffer_sender, client_buffer_receiver) = channels::bounded(5000);
        // ...
    }
}
```

The comment is significant: the maintainers explicitly note that a "redraw-on-backpressure mechanism" would be better but has not been implemented. The current behavior on channel full is:

```rust
pub fn send_or_buffer(&self, msg: ServerToClientMsg) -> Result<()> {
    self.client_buffer_sender
        .try_send(msg)
        .or_else(|err| {
            if let TrySendError::Full(_) = err {
                log::warn!("client {} is processing server messages too slow", self.client_id);
            }
            Err(err)
        })
}
```

When `try_send` fails with `Full`, the error propagates up to the `send_to_client!` macro in `lib.rs`, which removes the client entirely (disconnects with an error).

### 2.2 No Render Coalescing in the Channel

The channel carries `ServerToClientMsg::Render { content: String }` messages. Each render cycle produces at most one message per client. There is no mechanism to:
- Coalesce multiple Render messages in the queue
- Drop stale Render messages when newer ones arrive
- Replace the head of the queue with a fresher frame

The 5000-depth buffer is a brute-force approach: buffer enough messages that a slow client rarely fills up, and disconnect when it does. The maintainers' own comment acknowledges this is suboptimal.

### 2.3 Render Debounce

Before reaching the channel, renders are debounced at 10ms via a background job (`zellij-server/src/background_jobs.rs:116, 449-495`):

```rust
static REPAINT_DELAY_MS: u64 = 10;

BackgroundJob::RenderToClients => {
    // ... spawns async task:
    tokio::time::sleep(std::time::Duration::from_millis(REPAINT_DELAY_MS)).await;
    let _ = senders.send_to_screen(ScreenInstruction::RenderToClients);
    // If another request arrived during sleep, re-schedule
    if last_render_request > task_start_time {
        let _ = senders.send_to_background_jobs(BackgroundJob::RenderToClients);
    }
}
```

This means at most ~100 render cycles per second reach the output pipeline. But within each cycle, N copies are still made (one per client), and N messages are sent to N bounded channels.

---

## 3. Proactive Full Screen Redraws (Beyond Resize)

### 3.1 The `should_update_all_lines` Mechanism

The `OutputBuffer` has a `should_update_all_lines: bool` flag (`output/mod.rs:1073`). When true, `changed_chunks_in_viewport()` returns **all lines** instead of only the changed lines (lines 1142-1152).

This flag is set to `true` in these cases:

| Trigger | Location | File |
|---------|----------|------|
| **Initial creation** | `Default::default()` | `output/mod.rs:1081` |
| `render_full_viewport()` | `grid.rs:599-600` | `grid.rs` |
| `update_all_lines()` | `output/mod.rs:1102-1105` | `output/mod.rs` |

### 3.2 `render_full_viewport()` Triggers (Grid Level)

The `Grid::render_full_viewport()` method (which sets `should_update_all_lines = true`) is called from `grid.rs` in these situations:

1. **Resize** — `grid.rs:777, 829, 865` (when grid dimensions change)
2. **Scroll operations** — `grid.rs:1286, 1292, 1297, 1303` (scroll up/down, scroll region changes)
3. **Cursor movement with scroll** — `grid.rs:1321, 1336, 1350, 1392, 1403` (index/reverse index, line feed in scroll region)
4. **Clear screen** — `grid.rs:1079` (CSI 2J and similar)

### 3.3 `set_force_render()` Triggers (Tab Level)

The `Tab::set_force_render()` method (`tab/mod.rs:3013-3016`) calls `set_force_render()` on both tiled and floating panes, which in turn calls `pane.set_should_render(true)` and `pane.render_full_viewport()` on every pane.

This is triggered by `Screen` in these situations:

| Trigger | Location | Proactive? |
|---------|----------|-----------|
| **Tab switch** (move pane to different tab) | `screen.rs:1355` | Yes |
| **Tab close** (remaining tabs re-render) | `screen.rs:1612` | Yes |
| **Window resize** | `screen.rs:1656` | Expected |
| **Watcher render cycle** (conditional) | `screen.rs:1873` | Yes |
| **New tab creation** | `screen.rs:2264` | Yes |
| **Watcher size change** | `screen.rs:2387` (via `WatcherState::set_force_render`) | Expected |

### 3.4 Watcher Forced Renders

Watchers (read-only observer clients for web sharing) have their own `should_force_render` flag in `WatcherState` (`screen.rs:1016-1018`). On each render cycle, the system checks if any watcher needs a forced render:

```rust
// screen.rs:1864-1870
let any_watcher_needs_force_render = self
    .watcher_clients
    .values()
    .any(|state| state.should_force_render());
let should_force_render = non_watcher_output_was_dirty
    || any_watcher_needs_force_render
    || !has_regular_clients;

if should_force_render {
    tab.set_force_render();   // <-- full redraw of entire tab
}
```

This means **every time regular client output changes, watchers also get a full-tab force render** (because `non_watcher_output_was_dirty` is true). The flag `should_force_render` on `WatcherState` is primarily for the case where only the watcher's own state changed (resize, initial attach) but no regular client output changed.

After rendering, the force render flag is cleared for all watchers (`screen.rs:1909-1910`).

### 3.5 Summary of Proactive Full Redraws

zellij performs proactive full screen redraws (not just on resize) in these situations:
1. **Tab switches**: Both source and destination tabs get full redraws
2. **Tab creation/closure**: Force render on affected tabs
3. **New client attach**: First render is always full (`OutputBuffer::default()` sets `should_update_all_lines: true`)
4. **New watcher attach**: Triggers a render, and `WatcherState::new()` sets `should_force_render: true`
5. **Watcher rendering generally**: If regular client output was dirty, watchers get a force render

There is **no periodic keyframe mechanism**. zellij does not send full redraws at intervals — it relies on incremental dirty line tracking with full redraws only on structural events.

---

## 4. Plugin Rendering Pipeline vs Terminal Pane Rendering

### 4.1 Fundamental Difference: State Ownership

| Aspect | Terminal Pane | Plugin Pane |
|--------|--------------|-------------|
| Grid struct | `grid: Grid` (one) | `grids: HashMap<ClientId, Grid>` (N) |
| VTE parser | `grid.vte_parser` (one) | `vte_parsers: HashMap<ClientId, vte::Parser>` (N) |
| Dirty tracking | One `OutputBuffer` shared | N `OutputBuffer`s (one per client's grid) |
| `should_render` | `grid.should_render: bool` (one) | `should_render: HashMap<ClientId, bool>` (N) |
| Frame cache | `frame: HashMap<ClientId, PaneFrame>` | `frame: HashMap<ClientId, PaneFrame>` |
| Render input | `_client_id: Option<ClientId>` (ignored) | `client_id: Option<ClientId>` (used to select grid) |

### 4.2 Why Plugins Need Per-Client State

Plugins send VTE bytes to the server via `PluginInstruction::Update`. The plugin system delivers these bytes per-client through `handle_plugin_bytes(client_id, bytes)` (`plugin_pane.rs:227`). This is because plugins can render client-specific content:
- The status bar plugin shows the current mode (each client can be in a different mode)
- Tab bar highlights differ per client's active tab
- Plugins can query which client triggered an event

Each client's bytes are parsed by a separate VTE parser and written to a separate Grid, producing independent dirty tracking.

### 4.3 Tiled Panes Render Method: The Divergence Point

In `tiled_panes/mod.rs:1043-1061`, the render method explicitly branches:

```rust
for (kind, pane) in self.panes.iter_mut() {
    match kind {
        PaneId::Terminal(_) => {
            // ONE call, ALL clients
            output.add_pane_contents(&connected_clients, pane.pid(), pane.pane_contents(None, false));
        },
        PaneId::Plugin(_) => {
            // N calls, one per client
            for client_id in &connected_clients {
                output.add_pane_contents(
                    &[*client_id], pane.pid(), pane.pane_contents(Some(*client_id), false)
                );
            }
        },
    }
}
```

### 4.4 Serialization Pipeline

After the pane render phase, `Output::serialize()` (`output/mod.rs:464-505`) iterates over `client_character_chunks` and produces one VTE string per client. Each string includes:
1. Pre-VTE instructions (e.g., hide cursor, clear display)
2. Serialized character chunks (the actual cell content as ANSI escape sequences)
3. Post-VTE instructions (e.g., cursor position, BEL)

For watcher clients, the method `serialize_with_size()` (`output/mod.rs:507-586`) adds size constraints — padding and cropping if the watcher's terminal is a different size than the session.

### 4.5 The `content: String` Wire Format

The final message sent to clients is `ServerToClientMsg::Render { content: String }` (`zellij-utils/src/ipc.rs:156-158`). The `content` is a raw VTE/ANSI escape sequence string. The client writes this directly to its terminal — there is no structured data, no framing, no delta encoding. Each message is a complete rendering instruction sequence for the current state of all visible panes.

---

## 5. Files Examined

| File | Lines | Purpose |
|------|-------|---------|
| `zellij-server/src/output/mod.rs` | 1-1230 | Output struct, CharacterChunk, OutputBuffer, serialize, dirty tracking |
| `zellij-server/src/screen.rs` | 1014-1048, 1050-1210, 1706-1920, 2280-2390 | WatcherState, Screen struct, render/render_to_clients, client management |
| `zellij-server/src/os_input_output.rs` | 170-410 | ClientSender, bounded channel (5000), send_to_client |
| `zellij-server/src/background_jobs.rs` | 116-495 | REPAINT_DELAY_MS (10ms), RenderToClients debounce |
| `zellij-server/src/panes/terminal_pane.rs` | 300-342 | Terminal pane render (client_id ignored) |
| `zellij-server/src/panes/plugin_pane.rs` | 76-170, 361-420 | Plugin pane struct (per-client grids), render (client_id used) |
| `zellij-server/src/panes/grid.rs` | 353-600, 1105-1170 | Grid struct, OutputBuffer usage, read_changes, render_full_viewport |
| `zellij-server/src/panes/tiled_panes/mod.rs` | 987-1080 | set_force_render, render method (terminal vs plugin branching) |
| `zellij-server/src/tab/mod.rs` | 650-730, 3013-3016, 3049-3127 | Tab render, set_force_render |
| `zellij-server/src/lib.rs` | 1319-1365 | ServerInstruction::Render dispatch to clients |
| `zellij-utils/src/ipc.rs` | 155-186 | ServerToClientMsg::Render { content: String } |
| `zellij-server/src/panes/active_panes.rs` | 1-50 | Per-client active pane tracking |

---

## 6. Relevance to libitshell3

### 6.1 What zellij Does That Is Relevant

1. **One authoritative grid, N copies at output**: Terminal panes have one Grid (≈ our authoritative terminal state on the server). The data is cloned per-client at the Output serialization layer. The zellij maintainers have a TODO comment acknowledging this clone overhead (`output/mod.rs:370`).

2. **Brute-force buffering with disconnection**: The 5000-message bounded channel is a "good enough" backpressure mechanism. When it fills, the slow client is disconnected entirely. There is no render coalescing, no frame dropping, no resync. The maintainers' comment explicitly suggests "a redraw-on-backpressure mechanism" would be better.

3. **Per-client dirty tracking for plugins only**: Terminal panes share dirty state; plugin panes have per-client dirty state. This maps to our scenario where terminal content is shared across clients (one PTY), but UI overlays might differ.

4. **No periodic keyframes**: zellij relies entirely on event-driven full redraws (tab switch, resize, client attach) and incremental dirty line tracking. There is no periodic self-healing mechanism.

5. **Force render as the recovery mechanism**: When state might be inconsistent (tab switch, new client, watcher needing fresh state), zellij calls `set_force_render()` which sets `should_update_all_lines = true` on every pane's OutputBuffer. This is the equivalent of our proposed I-frame — a full snapshot of all visible content.

6. **10ms render debounce**: All render requests are coalesced within 10ms windows by the background job scheduler. This is simpler than our 4-tier adaptive coalescing model.

### 6.2 Patterns We Diverge From

1. **Wire format**: zellij sends raw VTE strings (`String`). We send structured binary CellData. This means zellij's "full redraw" is re-sending all ANSI escape sequences, not a structured keyframe. Our I-frame would be a structured full CellData snapshot — fundamentally different and more amenable to ring buffer sharing.

2. **No multi-client size awareness**: In normal (non-watcher) mode, all clients share the same terminal size (the session's `self.size`). Watchers get size-constrained rendering via `serialize_with_size()` which crops/pads, but the underlying grid content is the same. Our `latest` resize policy with per-client clipping is more complex.

3. **Client as terminal emulator**: zellij clients are terminals — they receive VTE and render it locally. Our clients use libghostty's RenderState, which is a structured cell grid. This means our server needs to transmit structured state, not escape sequences.

### 6.3 Caveats

- zellij is a Rust application where server and client run as separate processes connected via Unix socket (IPC) or TCP. The `ServerToClientMsg` is serialized via protobuf.
- The watcher/web-sharing feature is relatively new and its rendering pipeline (separate force-render phase) shows signs of being added incrementally rather than designed from the start.
- zellij's `session_is_mirrored` flag determines whether all clients see the same tab or can independently navigate tabs. When mirrored, behavior is closer to our shared-focus model. When not mirrored, clients can be on different tabs with different active panes — a complexity we do not have in v1.
- The Rust-specific pattern of `Rc<RefCell<>>` for shared mutable state does not directly translate to Zig, where explicit pointer ownership would be used instead.
