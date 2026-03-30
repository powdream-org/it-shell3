# 00064. Category-Based Message Dispatcher

- Date: 2026-03-31
- Status: Accepted

## Context

After Plan 7, `message_dispatcher.zig` contains a single monolithic `switch` on
`MessageType` with 20+ arms — lifecycle messages (handshake, heartbeat,
disconnect), session messages (7 types), pane messages (10 types), and a
catch-all `else` for future plans. Each arm includes inline JSON payload parsing
via `std.json.parseFromSlice`. The file is ~420 lines and growing.

The protocol spec organizes message types by range:

| Range  | Category                 |
| ------ | ------------------------ |
| 0x00xx | Lifecycle                |
| 0x01xx | Session + Pane           |
| 0x02xx | Input                    |
| 0x03xx | Render                   |
| 0x04xx | IME                      |
| 0x05xx | Flow control + auxiliary |

Plans 8 (Input), 9 (Render/Flow), and future plans will each add more message
types. With the current monolithic structure, every plan modifies the same file
and the same switch statement, creating merge conflicts and bloating a single
compilation unit.

## Decision

Refactor `message_dispatcher.zig` into a two-level dispatch:

All category dispatchers receive a single `CategoryDispatchParams` struct:

```zig
pub const CategoryDispatchParams = struct {
    context: *DispatcherContext,
    client: *ClientState,
    client_slot: u16,
    msg_type: MessageType,
    header: Header,
    payload: []const u8,
};

pub fn dispatch(...) void {
    const client = ctx.client_manager.getClient(client_slot) orelse return;
    const params = CategoryDispatchParams{
        .context = ctx,
        .client = client,
        .client_slot = client_slot,
        .msg_type = msg_type,
        .header = header,
        .payload = payload,
    };
    switch (@intFromEnum(msg_type) >> 8) {
        0x00 => lifecycle.dispatch(params),
        0x01 => session_pane.dispatch(params),
        0x02 => input.dispatch(params),
        0x03 => render.dispatch(params),
        0x04 => ime.dispatch(params),
        0x05 => flow_control.dispatch(params),
        else => {},
    }
}
```

Every category dispatcher has the same signature:
`fn dispatch(params:
CategoryDispatchParams) void`. This uniform struct
parameter ensures that adding a new field (e.g., a timestamp or priority hint)
requires changing only the struct definition and the construction site — not
every category dispatcher's function signature.

Within the 0x01xx category, a second-level split using `raw & 0xC0` further
separates sub-categories:

```zig
// session_pane dispatcher internal
const sub = (@intFromEnum(msg_type) & 0xC0) >> 6;
switch (sub) {
    0 => session.dispatch(params),      // 0x0100-0x013F
    1 => pane.dispatch(params),         // 0x0140-0x017F
    2 => notification.dispatch(params), // 0x0180-0x019F
    else => {},
}
```

This two-level dispatch (page → sub-category) keeps each file focused: session
handlers, pane handlers, and notification handlers are each self-contained.

Each category sub-dispatcher is a separate file under `server/handlers/`:

- `lifecycle_dispatcher.zig` — handshake, heartbeat, disconnect, error
- `session_pane_dispatcher.zig` — session CRUD + pane CRUD with JSON parsing
- `input_dispatcher.zig` — stub for Plan 8
- `render_dispatcher.zig` — stub for Plan 9
- `ime_dispatcher.zig` — stub for Plan 8
- `flow_control_dispatcher.zig` — stub for Plan 9

The top-level `message_dispatcher.zig` becomes a thin router (~30 lines). JSON
parsing and handler invocation move into each category dispatcher.

## Consequences

- **Separation of concerns.** Each protocol category is self-contained. Adding
  input handlers (Plan 8) means editing `input_dispatcher.zig`, not the
  monolithic dispatcher.
- **Parallel development.** Plans 8 and 9 can work on different dispatchers
  without file conflicts.
- **Top-level dispatcher is stable.** New message types within existing
  categories do not modify the top-level file. Only a new 0x06xx range would.
- **Category selector is O(1).** `msg_type >> 8` is a single shift — no
  sequential switch comparison.
- **Stub dispatchers are ready.** Future plans get a pre-wired entry point.
- **Pure structural refactor.** No behavioral change — all existing tests
  continue to pass without modification.
