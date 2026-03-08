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

### Layout System

tmux uses a tree of `layout_cell` nodes with three types: `LAYOUT_LEFTRIGHT` (horizontal split), `LAYOUT_TOPBOTTOM` (vertical split), `LAYOUT_WINDOWPANE` (leaf pane). Layouts serialize as compact strings (e.g., `80x24,0,0{40x24,0,0,0,40x24,40,0,1}`).

---

## 2. Zellij: Screen > Tab > Panes

### Hierarchy

```
Server
├── Tab 0: "editor"
│   ├── TiledPanes (grid-arranged, fill available space)
│   └── FloatingPanes (overlay with explicit coordinates)
├── Tab 1: "build"
│   └── TiledPanes
```

Key distinction: Zellij separates tiled panes (constraint-based layout) from floating panes (positioned overlays). Also supports swap layouts and WASM plugin panes.

---

## 3. cmux: Window > Workspace > Layout > Panel

### Hierarchy

```
Application
├── Window 1
│   ├── Workspace "project-a" (sidebar tab)
│   │   └── Binary split tree of Panels
│   └── Workspace "project-b"
├── Window 2
│   └── Workspace "monitoring"
```

Uses the **Bonsplit** library for binary split tree layout. Persistence via JSON snapshots (see `docs/daemon/01-session-persistence.md`).

---

## 4. Comparison

| Feature | tmux | zellij | cmux |
|---------|------|--------|------|
| Top-level | Session | (single) | Window |
| Mid-level | Window | Tab | Workspace |
| Leaf-level | Pane | Pane | Panel |
| Floating panes | No | Yes | No |
| Layout model | Tree | Constraint + Float | Binary tree |
| Layout serialization | String | KDL | JSON |
| Multiple sessions | Yes | Yes (separate servers) | No |

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

1. **Binary Split Tree** (like cmux/ghostty) — matches ghostty's split API, simple to serialize/deserialize, proven by cmux.

2. **Stable IDs + Display Positions** (like zellij) — panes get stable UUIDs, tabs have both stable IDs and display positions. Stable IDs used in protocol messages.

3. **No Floating Panes** (initially) — keep it simple for v1.

4. **Session > Tab > Pane** — matches user mental model. Multiple sessions for different projects. Session-level configuration and IME engine (one ImeEngine per session).

### Key Data Structures

Each **Pane** holds: stable ID, title, CWD, PTY master fd, child PID, terminal dimensions, scrollback buffer.

Each **Tab** holds: stable ID, display position, name, layout tree root, active pane reference.

Each **Session** holds: stable ID, name, ordered tabs, active tab, creation timestamp, options, and an ImeEngine instance.

> For the detailed protocol messages for layout operations (split, close, focus, navigate, resize, equalize, zoom, swap), see `docs/modules/libitshell3-protocol/02-design-docs/server-client-protocols/`.

### Layout Serialization (JSON)

```json
{
  "type": "split",
  "orientation": "horizontal",
  "ratio": 0.6,
  "first": { "type": "pane", "id": "a1b2c3d4", "title": "vim" },
  "second": {
    "type": "split",
    "orientation": "vertical",
    "ratio": 0.5,
    "first": { "type": "pane", "id": "e5f6g7h8", "title": "shell" },
    "second": { "type": "pane", "id": "i9j0k1l2", "title": "claude" }
  }
}
```
