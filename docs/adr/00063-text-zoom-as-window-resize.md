# 00063. Text Zoom Handled as WindowResize

- Date: 2026-03-30
- Status: Accepted

## Context

Terminal emulators support text zoom (Cmd+/− on macOS) which changes the cell
pixel size. When cells get larger (zoom in), fewer cells fit in the window; when
cells get smaller (zoom out), more cells fit. The daemon needs to know the
current cell grid dimensions to correctly size panes and PTYs (TIOCSWINSZ).

A dedicated "zoom" protocol message would require the daemon to understand pixel
dimensions and cell-to-pixel conversion — concerns that belong entirely to the
client's rendering layer.

The daemon operates entirely in cell units. Border rendering (1px divider lines
between panes) is a client-side overlay and occupies 0 cells in the daemon's
grid. The full cell grid is partitioned among panes with no gaps.

## Decision

Text zoom is not a separate protocol event. When the user zooms text, the client
recalculates its cell grid dimensions (cols × rows) based on the new cell pixel
size and sends a `WindowResize` message with the updated cols/rows. The daemon
treats this identically to a physical window resize.

The daemon's cell grid model: the daemon never deals with pixels. It receives
cell dimensions from the client and partitions them among panes via the split
tree. All ratio arithmetic, layout computation, and PTY sizing operate in cell
units.

## Consequences

- **No protocol addition needed.** Text zoom reuses `WindowResize` — no new
  message type, no new handler, no new state.
- **Daemon stays pixel-agnostic.** The daemon never needs to know cell pixel
  size, font metrics, or display DPI. These are client concerns.
- **Client takes conversion responsibility.** The client must recalculate
  cols/rows when cell size changes and send WindowResize. This is the same
  calculation the client already does for physical window resize.
- **Zoom and resize are indistinguishable to the daemon.** Both result in a new
  cols/rows grid. The daemon applies the same resize logic (pane dimension
  recalculation, TIOCSWINSZ, LayoutChanged notification).
- **Cell grid model is formalized.** Border/divider rendering is explicitly a
  client overlay. The daemon's grid has no gaps — every cell belongs to a pane.
