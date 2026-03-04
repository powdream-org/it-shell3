# Review Notes: 01-protocol-overview.md

**Reviewer**: heejoon.kang
**Date**: 2026-03-04

---

## Mapping Clarification

The protocol designer should use the following mapping consistently throughout
all protocol documents:

| libitshell3 concept | Maps to | Reference analogy |
|---------------------|---------|-------------------|
| **Session** | ghostty tab | tmux session, zellij tab |
| **Pane** (vertical/horizontal split) | ghostty split pane | tmux pane, zellij pane |

---

## Issue 1: CJK & IME Message Directions Are Wrong (Section 4.2)

**Severity**: Design-level error

The current spec has `PreeditStart`, `PreeditUpdate`, `PreeditEnd` going **C→S**
(client-to-server). This implies the client drives IME composition and reports
state to the server.

This contradicts the core architecture: **the server owns the native IME
(libitshell3-ime)**. The actual data flow is:

```
Client                          Server (Daemon)
  │                                │
  │─── KeyInput (raw key) ────────►│  Client ALWAYS sends raw keys,
  │                                │  even during CJK composition
  │                                │
  │                                │  Server runs libitshell3-ime,
  │                                │  processes the key
  │                                │
  │◄── PreeditState ──────────────│  Server pushes composition state
  │    (preedit string, cursor,   │  to client(s) for rendering
  │     composing Jamo)           │
  │                                │
  │◄── PreeditCommit ─────────────│  Composition committed
  │    or PreeditCancel           │  (character written to PTY)
  │                                │
```

### What needs to change

1. **Flip direction** of preedit messages from C→S to **S→C**:
   - `PreeditStart` → S→C (server notifies client that composition began)
   - `PreeditUpdate` → S→C (server pushes current composition state)
   - `PreeditEnd` → S→C (server notifies commit or cancel)

2. **Remove the assumption that clients manage preedit state.** Clients are
   thin renderers — they receive preedit state and overlay it at the cursor
   position. They never compute composition themselves.

3. **Consider adding `IMEModeSwitch` (C→S)** — client requests toggling
   between input modes (e.g., direct ASCII ↔ Korean 2-set). Alternatively,
   the server can detect the mode-switch hotkey from `KeyInput` and handle it
   internally.

4. **`PreeditSync` (S→C)** still makes sense for multi-client broadcast, but
   its role overlaps with the corrected `PreeditUpdate`. Clarify whether
   `PreeditSync` is a separate "broadcast to OTHER clients" message or if
   `PreeditUpdate` should simply be sent to all attached clients.

---

## Issue 2: Pane Management Missing Operations (Section 4.2)

**Severity**: Incomplete specification

### 2a. `PaneCreate` lacks split parameters

The document says `PaneCreate` supports "optionally via split", but does not
specify the payload fields needed to express a split operation:

- **Split direction**: horizontal vs. vertical
- **Reference pane**: which existing pane to split from
- **Split ratio**: initial ratio (e.g., 50/50, 60/40) or absolute size
- **Position**: whether the new pane goes before or after the reference pane

Without these, the server cannot know how to arrange the new pane in the
binary split tree.

### 2b. No divider adjustment message

`PaneResize` is defined as "cols × rows", which describes absolute terminal
dimensions. But in a split-pane layout, users resize panes by **dragging
the divider** between siblings. This changes the split ratio, and the server
recalculates cols/rows for both affected panes.

Need a message like:
- **`SplitResize` (C→S)** — adjust the divider position between two sibling
  panes (by ratio delta or pixel offset)

### 2c. No pane repositioning/swapping

Missing operations:
- **`PaneSwap` (C→S)** — swap two panes' positions in the layout tree
- **`PaneMove` (C→S)** — move a pane to a different position or tab
- **`PaneRotate` (C→S)** — rotate pane arrangement (common in tmux/zellij)

### 2d. No client-initiated layout query

`LayoutChanged` (S→C) exists as a server notification, but there is no
**`LayoutGet` (C→S)** for the client to request the current layout tree
on demand (e.g., after reconnection or when a new client attaches mid-session).

---

## Issue 3: Tab Management Missing Operations (Section 4.2)

**Severity**: Minor gap

Present: `TabCreate`, `TabClose`, `TabFocus`

Missing:
- **`TabReorder` (C→S)** — move a tab to a different position in the tab bar
- **`TabRename` (C→S)** — rename a tab (user-facing label)

---

## Issue 4: Minor Observations

### 4a. Sequence number scope (Section 3.4)

Sequence 0 is reserved for "unsolicited notifications", but Section 3.4 also
says "Notifications use the sender's next sequence number (not a response to
anything)." These seem contradictory. Clarify: when exactly is sequence 0 used
vs. a normal sequence number for notifications?

### 4b. `PreeditSync` vs. multi-client `FrameUpdate`

If preedit state is part of the render state (which it should be — the client
needs to render the preedit overlay), should preedit be embedded in
`FrameUpdate` rather than as a separate message? Or is a separate message
justified for latency reasons (preedit changes are more frequent and
time-critical than full frame updates)?

This is a design question, not necessarily a bug — but it should be explicitly
decided and documented.

---

## Issue 5: Cursor Style Change During CJK Composition — Not Addressed

**Severity**: Missing specification (cross-cutting, affects 04 and 05)

The protocol defines three cursor styles in `FrameUpdate`'s cursor section
(`04-input-and-renderstate.md`):

```
cursor_style: 0=block, 1=bar, 2=underline
```

And the preedit overlay rendering (`05-cjk-preedit-protocol.md`) describes
underline text decoration and a slightly different background for composing
text.

**However, no document specifies that the cursor style should change when
IME composition is active.** The standard UX convention is:

| Mode | Expected cursor style | Rationale |
|------|-----------------------|-----------|
| Normal typing (English) | Bar (blinking) | Standard text insertion caret |
| CJK composing (preedit active) | Block | Visually signals "building a character in-place" |
| CJK committed (preedit ended) | Back to bar | Composition finished, normal insertion resumes |

### What needs to be decided

1. **Who controls the cursor style during composition?** Since the server owns
   the IME and the cursor state, the server should automatically set
   `cursor_style = block` in `FrameUpdate` when `preedit_active = true`, and
   restore the previous style when composition ends. This keeps the
   server-authoritative principle intact.

2. **Or is this purely a client rendering decision?** The client could
   independently override cursor rendering based on the `preedit_active` flag.
   But this violates the server-authoritative model and risks inconsistency
   across clients.

3. **Document the expected behavior** in both `04-input-and-renderstate.md`
   (cursor section) and `05-cjk-preedit-protocol.md` (rendering section).

---

## Issue 6: Multi-Client Window Size Negotiation — Contradictory Across Docs

**Severity**: Design contradiction (cross-cutting, affects 02 and 03)

Two protocol documents specify **different strategies** for handling multiple
clients with different terminal dimensions:

| Document | Line | Strategy |
|----------|------|----------|
| `02-handshake-capability-negotiation.md` | ~489 | **Minimum (cols, rows)** across all attached clients (like tmux `aggressive-resize`) |
| `03-session-pane-management.md` | ~765 | **Most recently attached** client's dimensions; other clients see padding/clipping |

The session-pane doc flags this as an "Open question, deferred to v2."

### Why this must be resolved before implementation

The PTY has exactly **one** terminal size (`TIOCSWINSZ`). When two clients
attach with different dimensions (e.g., 120×40 vs. 80×24), the server must
pick one. This choice cascades through the entire layout tree and affects
every pane's cell dimensions, line wrapping, and reflow. It cannot be deferred.

### Strategies to evaluate

| Strategy | Pros | Cons |
|----------|------|------|
| **Minimum (cols, rows)** (tmux default) | All clients see the full content; no clipping | The larger client wastes screen space (padding) |
| **Most recently attached** | Simple, last-writer-wins | Other clients get clipped or must scroll horizontally |
| **Per-client viewport** (tmux `aggressive-resize`) | Each client uses its own dimensions; server tracks multiple viewports | Complex: requires per-client dirty tracking, multiple TIOCSWINSZ calls (not possible — PTY has one size), or virtual viewport mapping |
| **Largest client** | Maximizes content visible to at least one client | Smaller clients are clipped |

### Recommendation

Decide on **one strategy for v1** and document it consistently across all
protocol specs. The "minimum (cols, rows)" approach is the simplest and most
proven (tmux has used it for 15+ years). Per-client viewports can be a v2
feature if needed.

### Related: `WindowResize` message (`0x0190` in 03-session-pane-management.md)

The `WindowResize` message is sent per-client and includes cols, rows, and
pixel dimensions. The server cascades resizes via `TIOCSWINSZ`. But the
protocol does not specify:

- What happens when a **second** client sends `WindowResize` with different
  dimensions than the first client
- Whether the server sends `LayoutChanged` / `FrameUpdate` to **all** attached
  clients after a resize triggered by one client
- Whether the server notifies other clients that the effective terminal size
  has changed (and why)
