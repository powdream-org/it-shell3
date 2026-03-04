# Window and Pane Management

## Overview

Terminal multiplexers organize terminal sessions into a hierarchy. This document analyzes the hierarchy models from tmux, zellij, and cmux, and proposes the model for it-shell3.

---

## 1. tmux: Session > Window > Pane

### Hierarchy

```
Server
├── Session "dev"
│   ├── Window 0: "editor"
│   │   ├── Pane 0 (vim)        [60% width]
│   │   └── Pane 1 (terminal)   [40% width]
│   ├── Window 1: "build"
│   │   └── Pane 0 (make)       [100%]
│   └── Window 2: "logs"
│       ├── Pane 0 (tail -f)    [50% height]
│       └── Pane 1 (tail -f)    [50% height]
├── Session "ops"
│   └── Window 0: "monitoring"
│       └── Pane 0 (htop)       [100%]
```

### Key Data Structures

```c
// tmux.h
struct session {
    u_int                    id;          // Unique session ID
    char                    *name;        // Session name
    struct winlinks          windows;     // Linked list of windows
    struct winlink          *curw;        // Active window
    struct options          *options;
    TAILQ_ENTRY(session)     entry;
};

struct window {
    u_int                    id;          // Unique window ID
    char                    *name;        // Window name
    struct window_panes      panes;       // List of panes
    struct window_pane      *active;      // Active pane
    struct layout_cell      *layout_root; // Layout tree root
    u_int                    sx, sy;      // Window dimensions
};

struct window_pane {
    u_int                    id;          // Unique pane ID (%<id>)
    struct window           *window;      // Parent window
    int                      fd;          // PTY master fd
    pid_t                    pid;         // Child process PID
    struct bufferevent      *event;       // Async I/O handle
    struct screen           *screen;      // Terminal screen state
    u_int                    xoff, yoff;  // Position within window
    u_int                    sx, sy;      // Pane dimensions
    TAILQ_ENTRY(window_pane) entry;
};
```

### Layout System

tmux uses a tree of `layout_cell` nodes:

```c
struct layout_cell {
    enum layout_type {
        LAYOUT_LEFTRIGHT,   // Horizontal split
        LAYOUT_TOPBOTTOM,   // Vertical split
        LAYOUT_WINDOWPANE,  // Leaf (pane)
    } type;

    u_int sx, sy;           // Cell dimensions
    u_int xoff, yoff;       // Position offset
    struct window_pane *wp; // Pane (if leaf)

    TAILQ_HEAD(, layout_cell) cells;          // Children (if branch)
    TAILQ_ENTRY(layout_cell) entry;           // Sibling link
    struct layout_cell      *parent;          // Parent cell
};
```

### Layout Serialization

tmux serializes layouts as strings:
```
# Format: <width>x<height>,<xoff>,<yoff>[,<pane-id> | {<children>}]
# Example: 80x24,0,0{40x24,0,0,0,40x24,40,0,1}
# This means: 80x24 window split horizontally into two 40x24 panes
```

---

## 2. Zellij: Screen > Tab > Panes

### Hierarchy

```
Server
├── Tab 0: "editor"
│   ├── TiledPanes
│   │   ├── Terminal(0): vim     [main area]
│   │   └── Terminal(1): shell   [bottom strip]
│   └── FloatingPanes
│       └── Terminal(2): notes   [floating overlay]
├── Tab 1: "build"
│   └── TiledPanes
│       └── Terminal(3): cargo   [100%]
```

### Key Data Structures

```rust
// zellij-server/src/screen.rs
pub struct Screen {
    tabs: BTreeMap<usize, Tab>,     // Tabs keyed by stable ID
    active_tab_index: Option<usize>,
    // ...
}

// zellij-server/src/tab/mod.rs
pub struct Tab {
    index: usize,                    // Stable tab ID (never changes)
    position: usize,                 // Display position (0-based visual order)
    name: String,

    tiled_panes: TiledPanes,         // Grid-arranged panes
    floating_panes: FloatingPanes,   // Overlay panes with coordinates

    is_fullscreen_active: bool,
    panes_to_hide: HashSet<PaneId>,
}

// Pane identifier
pub enum PaneId {
    Terminal(u32),    // Terminal pane
    Plugin(u32),      // WASM plugin pane
}
```

### Tiled vs Floating Panes

**Tiled Panes**: Arranged in a constraint-based layout (similar to CSS flexbox):
- Fill available space
- Resize proportionally when window resizes
- Support stacking (multiple panes in same position, one visible)

**Floating Panes**: Positioned with explicit coordinates:
- Overlay on top of tiled panes
- Can be moved, resized independently
- Toggled on/off

### Swap Layouts

Zellij supports "swap layouts" — predefined layout configurations that can be cycled through:
```kdl
// layout.kdl
layout {
    swap_tiled_layout name="vertical" {
        tab {
            pane split_direction="vertical" {
                pane
                pane
            }
        }
    }
    swap_tiled_layout name="horizontal" {
        tab {
            pane split_direction="horizontal" {
                pane
                pane
            }
        }
    }
}
```

---

## 3. cmux: Window > Workspace > Layout > Panel

### Hierarchy

```
Application
├── Window 1
│   ├── Workspace "project-a" (sidebar tab)
│   │   └── Split(horizontal)
│   │       ├── Panel: Terminal (vim)     [70%]
│   │       └── Split(vertical)
│   │           ├── Panel: Terminal (sh)  [50%]
│   │           └── Panel: Browser (docs) [50%]
│   └── Workspace "project-b"
│       └── Panel: Terminal (cargo)      [100%]
├── Window 2
│   └── Workspace "monitoring"
│       └── Panel: Terminal (htop)       [100%]
```

### Key Data Structures

```swift
// SessionPersistence.swift
struct AppSessionSnapshot: Codable {
    var windows: [SessionWindowSnapshot]
}

struct SessionWindowSnapshot: Codable {
    var workspaces: [SessionWorkspaceSnapshot]
    var activeWorkspaceIndex: Int
    var frame: CGRect?
}

struct SessionWorkspaceSnapshot: Codable {
    var layout: SessionWorkspaceLayoutSnapshot
    var activeIndex: Int?
}

// Recursive binary tree layout
indirect enum SessionWorkspaceLayoutSnapshot: Codable {
    case pane(SessionPaneLayoutSnapshot)
    case split(SessionSplitLayoutSnapshot)
}

struct SessionSplitLayoutSnapshot: Codable {
    var orientation: SplitOrientation  // .horizontal | .vertical
    var dividerPosition: CGFloat       // 0.0 - 1.0 (proportion)
    var first: SessionWorkspaceLayoutSnapshot
    var second: SessionWorkspaceLayoutSnapshot
}

struct SessionPaneLayoutSnapshot: Codable {
    var title: String?
    var directory: String?
    var scrollback: String?
    var ttyName: String?
    var type: PanelType               // .terminal | .browser
}
```

### Bonsplit Library

cmux uses a custom split layout library called **Bonsplit** (vendored at `vendor/bonsplit/`):
- Binary split tree: Each node is either a leaf (pane) or a branch (split)
- Adjustable divider position
- Drag-to-resize dividers
- Recursive layout calculation

---

## 4. Comparison

| Feature | tmux | zellij | cmux |
|---------|------|--------|------|
| Top-level | Session | (single) | Window |
| Mid-level | Window | Tab | Workspace |
| Leaf-level | Pane | Pane | Panel |
| Floating panes | No | Yes | No |
| Plugin panes | No | Yes (WASM) | Yes (Browser) |
| Layout model | Tree | Constraint + Float | Binary tree |
| Layout serialization | String | KDL | JSON |
| Multiple sessions | Yes | Yes (separate servers) | No |
| ID system | Integer | Stable ID + Position | UUID |

---

## 5. Proposed Model for it-shell3

### Hierarchy

```
Daemon
├── Session "default"
│   ├── Tab 0: "editor"
│   │   └── Layout (binary split tree)
│   │       ├── Pane 0 (terminal, vim)
│   │       └── Split(horizontal)
│   │           ├── Pane 1 (terminal, shell)
│   │           └── Pane 2 (terminal, agent)
│   └── Tab 1: "build"
│       └── Pane 3 (terminal, cargo)
```

### Design Decisions

#### 1. Binary Split Tree (like cmux/ghostty)

Reasons:
- Matches ghostty's split API (`GHOSTTY_SPLIT_DIRECTION_{RIGHT,DOWN,LEFT,UP}`)
- Simple to serialize/deserialize
- Easy to implement resize by adjusting divider position
- Proven by cmux's production use

```
Node = Pane | Split(orientation, ratio, first: Node, second: Node)
```

#### 2. Stable IDs + Display Positions (like zellij)

- Each pane gets a stable UUID that never changes
- Tabs have both stable IDs and display positions
- Stable IDs used in protocol messages
- Display positions used in UI

#### 3. No Floating Panes (Initially)

- Keep it simple for v1
- Can be added later if needed
- Focus on solid split layout first

#### 4. Session > Tab > Pane Hierarchy

- Matches user mental model (tabs within a session)
- Multiple sessions for different projects
- Session-level configuration (CJK settings, key profiles)

### Pane Data Structure

```
Pane {
    id: UUID,               // Stable unique identifier
    title: String,          // Pane title (from OSC, or auto-generated)
    cwd: Path,              // Current working directory
    pty_fd: RawFd,          // PTY master file descriptor
    child_pid: pid_t,       // Child process PID
    size: (cols, rows),     // Terminal dimensions
    scrollback: Buffer,     // Scrollback buffer

    // CJK state
    cjk_state: PaneCjkState {
        preedit_active: bool,
        preedit_text: String,
        cursor_position: (x, y),
        ambiguous_width: u8,  // 1 or 2
    },

    // AI agent detection
    agent_mode: Option<AgentProfile>,  // Detected AI agent
}
```

### Tab Data Structure

```
Tab {
    id: UUID,               // Stable ID
    position: usize,        // Display order
    name: String,           // Tab name
    layout: LayoutNode,     // Root of binary split tree
    active_pane: UUID,      // Currently focused pane
}
```

### Session Data Structure

```
Session {
    id: UUID,               // Stable ID
    name: String,           // Session name (user-specified)
    tabs: Vec<Tab>,         // Ordered list of tabs
    active_tab: UUID,       // Currently active tab
    created_at: Timestamp,
    options: SessionOptions,
}
```

### Layout Serialization (JSON)

```json
{
  "type": "split",
  "orientation": "horizontal",
  "ratio": 0.6,
  "first": {
    "type": "pane",
    "id": "a1b2c3d4",
    "title": "vim",
    "cwd": "/home/user/project"
  },
  "second": {
    "type": "split",
    "orientation": "vertical",
    "ratio": 0.5,
    "first": {
      "type": "pane",
      "id": "e5f6g7h8",
      "title": "shell"
    },
    "second": {
      "type": "pane",
      "id": "i9j0k1l2",
      "title": "claude"
    }
  }
}
```

### Layout Operations

| Operation | Protocol Message | Description |
|-----------|-----------------|-------------|
| Split | `SplitPane(pane_id, direction)` | Split a pane horizontally or vertically |
| Close | `ClosePane(pane_id)` | Close pane, parent split becomes sibling |
| Focus | `FocusPane(pane_id)` | Set active pane |
| Navigate | `NavigatePane(direction)` | Move focus in direction |
| Resize | `ResizeSplit(pane_id, direction, delta)` | Adjust split divider |
| Equalize | `EqualizeSplits(tab_id)` | Make all splits equal |
| Zoom | `ZoomPane(pane_id)` | Toggle pane fullscreen |
| Swap | `SwapPanes(pane_a, pane_b)` | Swap two panes |
