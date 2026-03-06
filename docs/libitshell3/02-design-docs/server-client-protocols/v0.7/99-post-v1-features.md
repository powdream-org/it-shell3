# Post-v1 Features

This document collects features explicitly deferred beyond v1. These items are **not to be discussed or designed** during the v0.x through v1 cycle. They are recorded here solely to prevent information loss.

---

## 1. Image Protocol (Sixel / Kitty)

**Origin**: Doc 04 Open Question #2 (closed in v0.7, owner decision)

Sixel and Kitty image protocol support requires:
- Dedicated message type for image data (potentially megabytes per image)
- Out-of-band transfer mechanism (separate from FrameUpdate CellData stream)
- Image lifecycle management (placement, scrolling, resize interaction)

Image data is fundamentally different from text cell data and does not fit the current CellData structure. A dedicated spec is needed.

**References**: ghostty has Kitty image protocol support; iTerm2 supports both Sixel and its own inline image protocol.

## 2. Remain-on-Exit

**Origin**: Doc 03 Open Question #6 (closed in v0.7, owner decision)

v1 uses auto-close: when a pane's process exits, the server automatically closes the pane and triggers layout reflow. v1 ignores ghostty's `wait-after-command` option — the daemon always passes `wait_after_command = false` to libghostty.

Post-v1, add a `remain-on-exit` option (per-pane or per-session configuration) that keeps the pane visible with exit status displayed until the user explicitly closes it. tmux supports this via `set -g remain-on-exit on`.

**Implementation note**: When implementing remain-on-exit, ghostty's `wait-after-command` option MUST be considered. libghostty already has the plumbing — the embedder passes `wait_after_command = true` via `Surface.Options` and the Surface stays open after process exit. However, ghostty's behavior (show "Press any key to close" message, close on any keypress) may not match our desired UX (pane stays until explicit `ClosePane`). The daemon may need to handle the process exit callback independently rather than relying on ghostty's built-in wait behavior. See `v0.7/research/04-ghostty-wait-after-command.md` for the full ghostty implementation details.
