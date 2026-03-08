# Mouse Events

Mouse event handling depends on whether the terminal application has enabled mouse reporting. This document covers the ghostty mouse API and it-shell3's handling strategy.

---

## Ghostty Mouse API

```c
bool ghostty_surface_mouse_captured(ghostty_surface_t);   // Is mouse reporting active?
void ghostty_surface_mouse_button(ghostty_surface_t, ghostty_input_mouse_button_s);
void ghostty_surface_mouse_pos(ghostty_surface_t, double x, double y);
void ghostty_surface_mouse_scroll(ghostty_surface_t, double dx, double dy, ghostty_input_scroll_mods_s);
void ghostty_surface_mouse_pressure(ghostty_surface_t, uint32_t stage, float pressure);
```

## it-shell3 Mouse Handling

1. **Mouse reporting mode active** (`mouse_captured` = true):
   - Forward all mouse events through daemon to PTY
   - Application (vim, htop, etc.) handles them

2. **Mouse reporting inactive**:
   - Click: Focus pane
   - Drag: Select text
   - Right-click: Context menu
   - Scroll: Scrollback navigation
