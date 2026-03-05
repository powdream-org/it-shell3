# Zellij Research: Multi-Client Resize and Client Health Detection

**Researcher**: zellij-expert  
**Date**: 2026-03-05  
**Source**: `~/dev/git/references/zellij/`  
**Purpose**: Evidence for libitshell3 protocol v0.6 design decisions on Issue 2a (multi-client resize) and Issue 2b (client health model)

---

## Issue 2a: Multi-Client Resize

### 1. Multi-Client Sizing Strategy

**Finding: Zellij uses "smallest client wins" for regular clients, with independent viewport rendering for watcher clients.**

Zellij has two distinct client types with different resize semantics:

#### Regular Clients — Smallest Wins

When a regular client sends a `TerminalResize` message, the server stores the client's size in `SessionState`, then computes the **minimum across all regular client sizes** and applies that as the single global screen size.

**File**: `zellij-server/src/lib.rs:558-585`
```rust
pub fn min_client_terminal_size(&self) -> Option<Size> {
    let mut rows: Vec<usize> = self
        .clients
        .values()
        .filter_map(|size_and_is_web_client| {
            size_and_is_web_client.map(|(size, _is_web_client)| size.rows)
        })
        .collect();
    rows.sort_unstable();
    let mut cols: Vec<usize> = self
        .clients
        .values()
        .filter_map(|size_and_is_web_client| {
            size_and_is_web_client.map(|(size, _is_web_client)| size.cols)
        })
        .collect();
    cols.sort_unstable();
    let min_rows = rows.first();
    let min_cols = cols.first();
    match (min_rows, min_cols) {
        (Some(min_rows), Some(min_cols)) => Some(Size {
            rows: *min_rows,
            cols: *min_cols,
        }),
        _ => None,
    }
}
```

This minimum is then sent as `ScreenInstruction::TerminalResize(min_size)` to resize all tabs to this unified size.

**File**: `zellij-server/src/route.rs:2096-2117`
```rust
session_state.write().to_anyhow().with_context(err_context)?
    .set_client_size(client_id, new_size);
session_state.read().to_anyhow()
    .and_then(|state| {
        state.min_client_terminal_size().ok_or(anyhow!(
            "failed to determine minimal client terminal size"
        ))
    })
    .and_then(|min_size| {
        let _ = senders.as_ref().map(|s| {
            s.send_to_screen(ScreenInstruction::TerminalResize(min_size))
        });
        Ok(())
    })
    .with_context(err_context)?;
```

**Key observation**: The minimum is computed as `min(rows) x min(cols)` independently — not from the same client. If client A has 80x24 and client B has 100x20, the result is 80x20.

#### Watcher Clients — Independent Viewport (No PTY Impact)

Watcher clients are read-only observers that do NOT participate in the "smallest wins" calculation. They have their own `WatcherState` with an independent `size` field.

**File**: `zellij-server/src/screen.rs:1014-1048`
```rust
pub(crate) struct WatcherState {
    size: Size,
    should_force_render: bool,
}
```

When a watcher resizes, it sends `WatcherTerminalResize` (NOT `TerminalResize`), which updates only the watcher's local size without touching the global screen size:

**File**: `zellij-server/src/route.rs:1883-1892`
```rust
ClientToServerMsg::TerminalResize { new_size } => {
    // For watchers: send size to Screen for rendering adjustments, but
    // this does not affect the screen size
    send_to_screen_or_retry_queue!(
        senders,
        ScreenInstruction::WatcherTerminalResize(client_id, *new_size),
        ...
    )
}
```

**File**: `zellij-server/src/screen.rs:7607-7609`
```rust
ScreenInstruction::WatcherTerminalResize(client_id, size) => {
    screen.set_watcher_size(client_id, size);
    screen.render(None)?;
},
```

The watcher sees content rendered at the "followed client's" viewport, then **cropped/padded** to the watcher's own terminal size via `serialize_with_size()`. This means watchers with smaller terminals see a cropped view, and those with larger terminals see blank padding.

**File**: `zellij-server/src/screen.rs:1884-1896`
```rust
for (watcher_id, watcher_state) in &self.watcher_clients {
    let mut watcher_specific_output = watcher_output.clone();
    let mut serialized_output = watcher_specific_output
        .serialize_with_size(Some(watcher_state.size()), Some(self.size))
        .context(err_context)?;
    if let Some(followed_output) = serialized_output.remove(&followed_client_id) {
        watcher_render_output.insert(*watcher_id, followed_output);
    }
}
```

### 2. Unresponsive Client Handling in Resize

**Finding: Zellij does NOT exclude unresponsive or stale clients from the `min_client_terminal_size()` calculation.**

The `SessionState.clients` HashMap stores `Option<(Size, bool)>` per client. Once a client's size is set (via `set_client_size`), it remains in the map until the client is explicitly removed. There is:

- No timestamp tracking on client sizes
- No staleness check
- No health-based exclusion from the minimum calculation

If a client becomes unresponsive but its IPC connection hasn't broken, its stale size continues to participate in the minimum calculation. The only way a client stops affecting the resize is if:

1. Its IPC send buffer fills up (5000-message bounded channel), causing `ClientTooSlow` error
2. The `send_to_client!` macro removes the client from `SessionState` on send failure
3. After removal, `min_client_terminal_size()` is recalculated

**File**: `zellij-server/src/lib.rs:480-501`
```rust
macro_rules! send_to_client {
    ($client_id:expr, $os_input:expr, $msg:expr, $session_state:expr) => {
        let send_to_client_res = $os_input.send_to_client($client_id, $msg);
        if let Err(e) = send_to_client_res {
            ...
            // failed to send to client, remove it
            remove_client!($client_id, $os_input, $session_state);
        }
    };
}
```

**Implication for libitshell3**: Zellij has the exact same problem our Issue 2a describes. An unresponsive client with a small terminal will shrink the PTY for all healthy clients until either (a) 5000 render messages accumulate and overflow the buffer, or (b) the Unix socket breaks.

### 3. Resize Propagation Path with Debounce/Coalescing

Zellij has a multi-layer resize coalescing mechanism:

#### Layer 1: Client-to-Server (No Debounce)

Client sends `ClientToServerMsg::TerminalResize { new_size }` directly on SIGWINCH. No client-side debounce is visible in the code.

#### Layer 2: Screen-Level Resize

`resize_to_screen()` checks for size equality before applying:

**File**: `zellij-server/src/screen.rs:1648-1664`
```rust
pub fn resize_to_screen(&mut self, new_screen_size: Size) -> Result<()> {
    if self.size != new_screen_size {
        self.size = new_screen_size;
        for tab in self.tabs.values_mut() {
            tab.resize_whole_tab(new_screen_size)?;
            tab.set_force_render();
        }
        self.log_and_report_session_state()?;
        self.render(None)
    } else {
        Ok(())
    }
}
```

#### Layer 3: PTY Resize Caching (Batch Application)

During screen event processing, zellij caches PTY resize syscalls and applies them in bulk at the end of each event loop iteration. This prevents multiple `TIOCSWINSZ` syscalls during a single event batch.

**File**: `zellij-server/src/os_input_output.rs:612-635`
```rust
pub struct ResizeCache {
    senders: ThreadSenders,
}

impl ResizeCache {
    pub fn new(senders: ThreadSenders) -> Self {
        senders.send_to_pty_writer(PtyWriteInstruction::StartCachingResizes).unwrap_or_else(|e| {
            log::error!("Failed to cache resizes: {}", e);
        });
        ResizeCache { senders }
    }
}

impl Drop for ResizeCache {
    fn drop(&mut self) {
        self.senders.send_to_pty_writer(PtyWriteInstruction::ApplyCachedResizes).unwrap_or_else(|e| {
            log::error!("Failed to apply cached resizes: {}", e);
        });
    }
}
```

The `ResizeCache` is created at the start of the screen event loop iteration, and when it's dropped at the end, all cached resize operations are applied to the PTYs. Only the **last resize per pane** is kept:

**File**: `zellij-server/src/os_input_output.rs:336-338`
```rust
if let Some(cached_resizes) = self.cached_resizes.lock().unwrap().as_mut() {
    cached_resizes.insert(id, (cols, rows, width_in_pixels, height_in_pixels));
    return Ok(());
}
```

#### Layer 4: Render Debounce (10ms)

The actual rendering is debounced at 10ms via the `BackgroundJob::RenderToClients` mechanism. Each `render()` call sends a `RenderToClients` job, which waits 10ms before sending `ScreenInstruction::RenderToClients`. If another render request arrives during the delay, the timer effectively resets.

**File**: `zellij-server/src/background_jobs.rs:116,449-495`
```rust
static REPAINT_DELAY_MS: u64 = 10;

BackgroundJob::RenderToClients => {
    let (should_run_task, current_time) = {
        let mut last_render_request = last_render_request.lock().unwrap();
        let should_run_task = last_render_request.is_none();
        let current_time = Instant::now();
        *last_render_request = Some(current_time);
        (should_run_task, current_time)
    };
    if should_run_task {
        runtime.spawn({
            async move {
                tokio::time::sleep(Duration::from_millis(REPAINT_DELAY_MS)).await;
                let _ = senders.send_to_screen(ScreenInstruction::RenderToClients);
                // If another render request arrived while sleeping, re-schedule
                ...
            }
        });
    }
},
```

### 4. Per-Client Viewport Sizing

**Finding: Zellij supports per-client pane focus but NOT per-client viewport sizing for regular clients.**

In mirrored mode (`session_is_mirrored = true`, the default for `mirror_session` option), all regular clients see the same tab and share cursor/focus state. Tab switching by any client switches for all.

In non-mirrored mode (`session_is_mirrored = false`), each client can focus different tabs and different panes within a tab independently. The tab tracks per-client focus via `connected_clients`:

**File**: `zellij-server/src/screen.rs:1081,1125,1400`
```rust
session_is_mirrored: bool,
```

However, **both modes use the same global screen size** (the minimum across all clients). There is no per-client viewport with independent PTY sizes — only watcher clients get independent viewport rendering (via cropping/padding of the single global render).

**File**: `zellij-server/src/screen.rs:1060`
```rust
/// The full size of this [`Screen`].
size: Size,
```

This is a single `Size` value shared by the entire `Screen` struct, not per-client.

---

## Issue 2b: Client Health Detection

### 1. Client Health Detection Mechanisms

**Finding: Zellij has NO heartbeat, NO ping/pong, and NO explicit health checks. It relies entirely on IPC failure detection.**

A thorough search of the codebase for `heartbeat`, `ping`, `pong`, `keepalive`, `health`, and `watchdog` returns zero results related to client health monitoring. Zellij detects client problems through two mechanisms:

#### Mechanism 1: Bounded Send Buffer Overflow

Each client connection gets a dedicated sender thread with a **bounded channel of depth 5000**:

**File**: `zellij-server/src/os_input_output.rs:182-210`
```rust
impl ClientSender {
    pub fn new(client_id: ClientId, mut sender: IpcSenderWithContext<ServerToClientMsg>) -> Self {
        // ... previously found to be too small at 50, increased to 5000 ...
        let (client_buffer_sender, client_buffer_receiver) = channels::bounded(5000);
        std::thread::spawn(move || {
            for msg in client_buffer_receiver.iter() {
                sender.send_server_msg(msg).with_context(err_context).non_fatal();
            }
            let _ = sender.send_server_msg(ServerToClientMsg::Exit {
                exit_reason: ExitReason::Disconnect,
            });
        });
        ...
    }
    pub fn send_or_buffer(&self, msg: ServerToClientMsg) -> Result<()> {
        self.client_buffer_sender
            .try_send(msg)
            .or_else(|err| {
                if let TrySendError::Full(_) = err {
                    log::warn!("client {} is processing server messages too slow", self.client_id);
                }
                Err(err)
            })
            .with_context(err_context)
    }
}
```

When `try_send` returns `TrySendError::Full`, the `send_to_client!` macro removes the client entirely:

**File**: `zellij-server/src/lib.rs:482-499`
```rust
let send_to_client_res = $os_input.send_to_client($client_id, $msg);
if let Err(e) = send_to_client_res {
    ...
    // failed to send to client, remove it
    remove_client!($client_id, $os_input, $session_state);
}
```

#### Mechanism 2: Unix Socket Read Error / EOF

The route thread for each client runs a blocking loop reading `ClientToServerMsg` from the IPC socket. If the client process dies, the socket read returns `None`, and after 1000 consecutive `None` values, the client is forcibly removed:

**File**: `zellij-server/src/route.rs:2299-2313`
```rust
None => {
    consecutive_unknown_messages_received += 1;
    if consecutive_unknown_messages_received == 1 {
        log::error!("Received unknown message from client.");
    }
    if consecutive_unknown_messages_received >= 1000 {
        log::error!("Client sent over 1000 consecutive unknown messages...");
        let _ = os_input.send_to_client(client_id, ServerToClientMsg::Exit { ... });
        let _ = to_server.send(ServerInstruction::RemoveClient(client_id));
        break 'route_loop;
    }
}
```

#### Mechanism 3: Explicit Client Exit Message

Well-behaved clients send `ClientToServerMsg::ClientExited` when disconnecting:

**File**: `zellij-server/src/route.rs:2254-2256`
```rust
ClientToServerMsg::ClientExited => {
    let _ = to_server.send(ServerInstruction::RemoveClient(client_id));
    return Ok(true);
},
```

### 2. Unresponsive Client Actions

**Finding: Zellij has exactly ONE response to an unresponsive client — disconnection. There is no intermediate "pause" or "degrade" state.**

The progression is:
1. Client is **connected** (messages flow normally)
2. Server buffer fills up (5000 messages) or socket read fails
3. Client is **removed** immediately — no warning, no grace period, no degradation

When the sender thread's channel is dropped (because `ClientSender` is removed from the map), the sender thread sends one final `ExitReason::Disconnect` message:

**File**: `zellij-server/src/ipc.rs:218-239` (`ExitReason::Disconnect` display)
```
Your zellij client lost connection to the zellij server.
...
This usually means that your terminal didn't process server messages quick
enough. Maybe your system is currently under high load, or your terminal
isn't performant enough.
```

There is no concept of:
- Pausing output to a slow client while keeping it connected
- Reducing rendering quality/frequency for slow clients
- Marking a client as "degraded" while maintaining its session state

### 3. Per-Client Output Flow Control and Backpressure

**Finding: Zellij uses a bounded per-client channel (5000 messages) as its sole backpressure mechanism.**

Each client gets its own sender thread with a `channels::bounded(5000)` channel. The server uses `try_send` (non-blocking) to avoid the screen thread being blocked by a slow client:

- If the channel has space: message is buffered
- If the channel is full: `TrySendError::Full` is returned, client is removed

The comments in the code explicitly discuss the trade-off:

**File**: `zellij-server/src/os_input_output.rs:183-192`
```rust
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
```

This is notable: the zellij maintainers explicitly acknowledge that a "redraw-on-backpressure" mechanism would be better but haven't implemented it.

### 4. Thread Architecture and Per-Client Isolation

**Finding: Each client gets its own dedicated route thread. Server-side processing is centralized in single threads per concern.**

Thread architecture:

| Thread | Scope | Purpose |
|--------|-------|---------|
| `server_router` (per client) | One per connected client | Reads `ClientToServerMsg` from IPC socket, routes to appropriate thread |
| `screen` (singleton) | One per session | Owns all `Tab`/`Pane` state, handles resize, rendering |
| `pty` (singleton) | One per session | PTY spawning, terminal ID management |
| `pty_writer` (singleton) | One per session | Writes to PTY stdin, handles resize syscalls |
| `plugin` (singleton) | One per session | WASM plugin execution |
| `background_jobs` (singleton) | One per session | Render debounce, session serialization, animations |
| Client sender (per client) | One per connected client | Writes `ServerToClientMsg` to IPC socket |

**File**: `zellij-server/src/thread_bus.rs:13-19`
```rust
pub struct ThreadSenders {
    pub to_screen: Option<SenderWithContext<ScreenInstruction>>,
    pub to_pty: Option<SenderWithContext<PtyInstruction>>,
    pub to_plugin: Option<SenderWithContext<PluginInstruction>>,
    pub to_server: Option<SenderWithContext<ServerInstruction>>,
    pub to_pty_writer: Option<SenderWithContext<PtyWriteInstruction>>,
    pub to_background_jobs: Option<SenderWithContext<BackgroundJob>>,
}
```

Per-client isolation is achieved at the IPC layer:
- Each client has its own route thread for reading input
- Each client has its own sender thread with its own bounded channel
- A slow client's sender thread blocks only its own channel, not the screen thread
- The screen thread uses `try_send` (non-blocking) to avoid being stalled

**File**: `zellij-server/src/lib.rs:710-732`
```rust
for stream in listener.incoming() {
    match stream {
        Ok(stream) => {
            let client_id = session_state.write().unwrap().new_client();
            let receiver = os_input.new_client(client_id, stream).unwrap();
            thread::Builder::new()
                .name("server_router".to_string())
                .spawn(move || {
                    route_thread_main(session_data, session_state, os_input, to_server, receiver, client_id)
                        .fatal()
                })
                .unwrap();
        },
        ...
    }
}
```

### 5. Plugin Client vs Terminal Client Policies

**Finding: Zellij distinguishes three client types: regular clients, watcher clients, and web clients. Plugins are not clients — they run in-process as WASM.**

- **Regular clients**: Full bidirectional interaction, affect PTY sizing
- **Watcher clients**: Read-only observers with independent viewport, do NOT affect PTY sizing. Can only press Ctrl-Q/Esc/Ctrl-C to disconnect. All other input is silently dropped.
- **Web clients**: Regular or watcher clients connecting via WebSocket instead of Unix socket. Subject to the `web_clients_allowed` configuration flag.
- **Plugins**: Run as WASM modules inside the `plugin` thread. Not IPC clients — they communicate via the plugin API's protobuf-defined messages within the same process.

Watcher clients are identified via `ClientToServerMsg::AttachWatcherClient`:

**File**: `zellij-utils/src/ipc.rs:127-130`
```rust
AttachWatcherClient {
    terminal_size: Size,
    is_web_client: bool,
},
```

And converted from regular client state:

**File**: `zellij-server/src/lib.rs:629-631`
```rust
pub fn convert_client_to_watcher(&mut self, client_id: ClientId, is_web_client: bool) {
    self.clients.remove(&client_id);
    self.watchers.insert(client_id, is_web_client);
}
```

---

## Relevance to libitshell3

### Key Findings Summary

| Aspect | Zellij Behavior | Relevance to Issue |
|--------|----------------|-------------------|
| Multi-client resize | "Smallest wins" across all regular clients | **Issue 2a**: Same algorithm as our current design. Same vulnerability to stale dimensions. |
| Unresponsive client exclusion | No exclusion — stale sizes persist until buffer overflow or socket death | **Issue 2a**: Confirms this is a real gap. libitshell3 should improve on this. |
| Watcher model | Separate client type that doesn't affect PTY sizing, gets cropped/padded independent viewport | **Issue 2a**: Potential inspiration for our "observer" or "paused" client concept |
| Health detection | No heartbeat. Buffer overflow (5000 msgs) or socket EOF only | **Issue 2b**: Confirms the gap. libitshell3's heartbeat design is more proactive than zellij. |
| Health states | Binary: connected or removed. No intermediate states | **Issue 2b**: libitshell3 should add intermediate states (degraded/paused) |
| Backpressure | Bounded 5000-message per-client channel, `try_send` | **Issue 2b**: Good isolation pattern but crude policy (disconnect on overflow) |
| Thread isolation | Per-client route + sender threads, singleton screen/pty threads | **Both**: Validates per-client isolation approach |
| Render debounce | 10ms debounce via background job | **Issue 2a**: Relevant to resize coalescing design |
| PTY resize coalescing | `ResizeCache` batches all pane resizes per event loop iteration | **Issue 2a**: Good pattern — only last resize per pane is applied |

### Design Implications

1. **For Issue 2a**: Zellij's watcher client pattern demonstrates that it IS feasible to have clients with independent viewports that don't affect PTY sizing. libitshell3 could adopt a similar pattern where paused/unresponsive clients are "promoted" to watcher-like status (excluded from min-size calculation) rather than leaving their stale dimensions in the pool.

2. **For Issue 2b**: Zellij's lack of heartbeats means detection of unresponsive clients depends entirely on output pressure. A client that sends no input but is otherwise alive is indistinguishable from a healthy idle client. libitshell3's explicit heartbeat mechanism (already designed in the protocol) is strictly better — it provides positive proof of client liveness independent of output flow.

3. **Backpressure inspiration**: Zellij's bounded channel with `try_send` provides good server-side isolation but has a crude disconnect-on-overflow policy. The maintainers' own FIXME comment suggests "redraw-on-backpressure" as the ideal. libitshell3 could implement what zellij has identified but not built: upon backpressure detection, switch the client to a reduced-rendering mode (e.g., lower frame rate, skip non-essential updates) rather than disconnecting.

### Caveats

- Zellij is single-process (server and all threads share memory). libitshell3 is IPC-based (daemon/client), so the channel-based backpressure model maps to socket buffer pressure instead.
- Zellij's `Output` struct serializes VT escape codes per client. libitshell3 uses binary RenderState protocol, so the "per-client cropping" approach for watchers would need to be reimagined in terms of RenderState message filtering rather than VT output truncation.
- Zellij WASM plugins are in-process, not IPC clients. libitshell3 doesn't have a direct equivalent of the plugin vs. client distinction.
- The 5000-message buffer depth was empirically chosen and acknowledged as potentially insufficient. It's not a principled bound — just "didn't noticeably increase RAM."
