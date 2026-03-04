# libghostty API Reference

## Overview

Ghostty exposes **two distinct C APIs**:

1. **Full Embedding API** (`ghostty.h`) — for embedding the complete terminal engine in native apps
2. **libghostty-vt** (`ghostty/vt.h`) — lightweight VT parsing library for escape sequence handling

The full embedding API is what cmux uses and what it-shell3 will use.

## Source Locations

```
~/dev/git/references/ghostty/
├── include/
│   ├── ghostty.h              # Full embedding API (1170 lines)
│   ├── module.modulemap       # Swift/Clang module map
│   └── ghostty/
│       └── vt.h               # libghostty-vt entry point
│           ├── allocator.h    # Custom allocator interface
│           ├── key/
│           │   ├── encoder.h  # Key event encoding
│           │   └── event.h    # Key event types
│           ├── osc.h          # OSC sequence parser
│           ├── paste.h        # Paste safety checker
│           └── sgr.h          # SGR attribute parser
├── src/
│   ├── main_c.zig             # C export definitions
│   ├── lib_vt.zig             # libghostty-vt Zig exports
│   ├── Surface.zig            # Core terminal surface
│   ├── apprt/
│   │   ├── embedded.zig       # macOS/iOS embedding runtime
│   │   └── action.zig         # Action dispatch system
│   └── ...
└── example/                   # Working C/Zig/Wasm examples
```

## Full Embedding API (`ghostty.h`)

### Opaque Handle Types

```c
typedef void* ghostty_app_t;       // Application instance
typedef void* ghostty_config_t;    // Configuration object
typedef void* ghostty_surface_t;   // Terminal surface (one per pane)
typedef void* ghostty_inspector_t; // Debug inspector
```

### Lifecycle Management

#### Initialization
```c
// Initialize global state (call once at startup)
void ghostty_init(int argc, char** argv);

// Try to run a CLI action if specified in args
bool ghostty_cli_try_action();

// Get build info (version, build mode)
ghostty_info_s ghostty_info();

// i18n string translation
const char* ghostty_translate(const char* msgid);

// Free a ghostty-allocated string
void ghostty_string_free(const char* str);
```

#### Configuration
```c
ghostty_config_t ghostty_config_new();
void ghostty_config_free(ghostty_config_t);
ghostty_config_t ghostty_config_clone(ghostty_config_t);

// Loading configuration from various sources
void ghostty_config_load_cli_args(ghostty_config_t);
void ghostty_config_load_file(ghostty_config_t, const char* path);
void ghostty_config_load_default_files(ghostty_config_t);
void ghostty_config_load_recursive_files(ghostty_config_t);

// Finalize config (must call after all load operations)
void ghostty_config_finalize(ghostty_config_t);

// Query config values
bool ghostty_config_get(ghostty_config_t, const char* key, void* out);
void ghostty_config_trigger(ghostty_config_t, const char* key);

// Diagnostics
uint32_t ghostty_config_diagnostics_count(ghostty_config_t);
ghostty_diagnostic_s ghostty_config_get_diagnostic(ghostty_config_t, uint32_t idx);
const char* ghostty_config_open_path(ghostty_config_t);
```

#### Application
```c
ghostty_app_t ghostty_app_new(ghostty_runtime_config_s, ghostty_config_t);
void ghostty_app_free(ghostty_app_t);

// Main loop tick — must be called regularly to drain mailbox and process events
void ghostty_app_tick(ghostty_app_t);

void ghostty_app_set_focus(ghostty_app_t, bool focused);
void ghostty_app_key(ghostty_app_t, ghostty_input_key_s);
bool ghostty_app_key_is_binding(ghostty_app_t, ghostty_input_key_s);
void ghostty_app_keyboard_changed(ghostty_app_t);
void ghostty_app_open_config(ghostty_app_t);
void ghostty_app_update_config(ghostty_app_t, ghostty_config_t);
bool ghostty_app_needs_confirm_quit(ghostty_app_t);
bool ghostty_app_has_global_keybinds(ghostty_app_t);
void ghostty_app_set_color_scheme(ghostty_app_t, ghostty_color_scheme_e);
```

#### Surface (Terminal Instance)
```c
// Creation and destruction
ghostty_surface_t ghostty_surface_new(ghostty_app_t, ghostty_surface_config_s);
void ghostty_surface_free(ghostty_surface_t);

// Properties
void* ghostty_surface_userdata(ghostty_surface_t);
ghostty_app_t ghostty_surface_app(ghostty_surface_t);
ghostty_config_t ghostty_surface_inherited_config(ghostty_surface_t);
void ghostty_surface_update_config(ghostty_surface_t, ghostty_config_t);
bool ghostty_surface_needs_confirm_quit(ghostty_surface_t);
bool ghostty_surface_process_exited(ghostty_surface_t);

// Rendering
void ghostty_surface_refresh(ghostty_surface_t);
void ghostty_surface_draw(ghostty_surface_t);

// Display properties
void ghostty_surface_set_content_scale(ghostty_surface_t, double, double);
void ghostty_surface_set_focus(ghostty_surface_t, bool);
void ghostty_surface_set_occlusion(ghostty_surface_t, bool);
void ghostty_surface_set_size(ghostty_surface_t, uint32_t width, uint32_t height);
ghostty_surface_size_s ghostty_surface_size(ghostty_surface_t);
void ghostty_surface_set_color_scheme(ghostty_surface_t, ghostty_color_scheme_e);
```

### Input Handling

```c
// Keyboard input
void ghostty_surface_key(ghostty_surface_t, ghostty_input_key_s);
bool ghostty_surface_key_is_binding(ghostty_surface_t, ghostty_input_key_s);

// Committed text (after IME confirmation)
void ghostty_surface_text(ghostty_surface_t, const char* utf8, uintptr_t len);

// IME preedit text (during composition — CRITICAL FOR CJK)
void ghostty_surface_preedit(ghostty_surface_t, const char* utf8, uintptr_t len);

// Get IME candidate window position
void ghostty_surface_ime_point(ghostty_surface_t,
    double* x, double* y, double* width, double* height);

// Mouse input
bool ghostty_surface_mouse_captured(ghostty_surface_t);
void ghostty_surface_mouse_button(ghostty_surface_t, ghostty_input_mouse_button_s);
void ghostty_surface_mouse_pos(ghostty_surface_t, double x, double y);
void ghostty_surface_mouse_scroll(ghostty_surface_t, double dx, double dy, ghostty_input_scroll_mods_s);
void ghostty_surface_mouse_pressure(ghostty_surface_t, uint32_t stage, float pressure);
```

### Split Management

```c
// Split direction enum
typedef enum {
    GHOSTTY_SPLIT_DIRECTION_RIGHT,
    GHOSTTY_SPLIT_DIRECTION_DOWN,
    GHOSTTY_SPLIT_DIRECTION_LEFT,
    GHOSTTY_SPLIT_DIRECTION_UP,
} ghostty_action_split_direction_e;

// Navigation between splits
typedef enum {
    GHOSTTY_GOTO_SPLIT_PREVIOUS,
    GHOSTTY_GOTO_SPLIT_NEXT,
    GHOSTTY_GOTO_SPLIT_UP,
    GHOSTTY_GOTO_SPLIT_LEFT,
    GHOSTTY_GOTO_SPLIT_DOWN,
    GHOSTTY_GOTO_SPLIT_RIGHT,
} ghostty_action_goto_split_e;

// Resize direction
typedef enum {
    GHOSTTY_RESIZE_SPLIT_UP,
    GHOSTTY_RESIZE_SPLIT_DOWN,
    GHOSTTY_RESIZE_SPLIT_LEFT,
    GHOSTTY_RESIZE_SPLIT_RIGHT,
} ghostty_action_resize_split_direction_e;

// Split operations
void ghostty_surface_split(ghostty_surface_t, ghostty_action_split_direction_e);
void ghostty_surface_split_focus(ghostty_surface_t, ghostty_action_goto_split_e);
void ghostty_surface_split_resize(ghostty_surface_t, ghostty_action_resize_split_direction_e, uint16_t amount);
void ghostty_surface_split_equalize(ghostty_surface_t);
```

### Selection and Clipboard

```c
bool ghostty_surface_has_selection(ghostty_surface_t);
char* ghostty_surface_read_selection(ghostty_surface_t);
char* ghostty_surface_read_text(ghostty_surface_t);
void ghostty_surface_free_text(ghostty_surface_t, char*);
void ghostty_surface_request_close(ghostty_surface_t);
void ghostty_surface_binding_action(ghostty_surface_t, ghostty_input_binding_s);
void ghostty_surface_complete_clipboard_request(ghostty_surface_t, const char*, uintptr_t, bool);
```

### Apple-Specific APIs

```c
void ghostty_surface_set_display_id(ghostty_surface_t, uint32_t);
void ghostty_surface_quicklook_font(ghostty_surface_t);
void ghostty_surface_quicklook_word(ghostty_surface_t);

// Metal inspector
void ghostty_inspector_metal_init(ghostty_inspector_t, void* layer);
void ghostty_inspector_metal_render(ghostty_inspector_t, void* layer);
void ghostty_inspector_metal_shutdown(ghostty_inspector_t);
```

### Runtime Configuration (Host Callbacks)

The host application must provide callback functions for ghostty to communicate back:

```c
typedef struct {
    void* userdata;
    bool supports_selection_clipboard;

    // Wake up the main event loop (thread-safe)
    ghostty_runtime_wakeup_cb wakeup_cb;

    // Handle actions from ghostty (60+ action types)
    ghostty_runtime_action_cb action_cb;

    // Clipboard operations
    ghostty_runtime_read_clipboard_cb read_clipboard_cb;
    ghostty_runtime_confirm_read_clipboard_cb confirm_read_clipboard_cb;
    ghostty_runtime_write_clipboard_cb write_clipboard_cb;

    // Surface lifecycle
    ghostty_runtime_close_surface_cb close_surface_cb;
} ghostty_runtime_config_s;
```

### Action System (60+ action types)

The `action_cb` receives a `ghostty_action_tag_e` with action-specific payloads:

Key actions relevant to it-shell3:
- `GHOSTTY_ACTION_NEW_SPLIT` — Create new split pane
- `GHOSTTY_ACTION_GOTO_SPLIT` — Navigate between splits
- `GHOSTTY_ACTION_RESIZE_SPLIT` — Resize split
- `GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM` — Zoom a split
- `GHOSTTY_ACTION_EQUALIZE_SPLITS` — Equalize split sizes
- `GHOSTTY_ACTION_CLOSE_SURFACE` — Close a surface
- `GHOSTTY_ACTION_NEW_TAB` — Create new tab
- `GHOSTTY_ACTION_NEW_WINDOW` — Create new window
- `GHOSTTY_ACTION_SET_TITLE` — Set surface title
- `GHOSTTY_ACTION_MOUSE_SHAPE` — Cursor shape change
- `GHOSTTY_ACTION_SIZE_LIMIT` — Report size limits
- `GHOSTTY_ACTION_RENDERER_HEALTH` — Renderer health status

### Surface Context

```c
typedef enum {
    GHOSTTY_SURFACE_CONTEXT_WINDOW,  // Top-level window
    GHOSTTY_SURFACE_CONTEXT_TAB,     // Tab within a window
    GHOSTTY_SURFACE_CONTEXT_SPLIT,   // Split pane within a surface
} ghostty_surface_context_e;
```

## libghostty-vt (Lightweight VT Library)

A smaller, more stable API for just VT parsing. Useful for parsing terminal escape sequences without the full terminal engine.

### OSC Parser
```c
void ghostty_osc_new(GhosttyAllocator*, GhosttyOscParser*);
void ghostty_osc_free(GhosttyOscParser);
void ghostty_osc_reset(GhosttyOscParser);
GhosttyOscResult ghostty_osc_next(GhosttyOscParser, uint8_t byte);
GhosttyOscCommand ghostty_osc_end(GhosttyOscParser, uint8_t terminator);
GhosttyOscCommandType ghostty_osc_command_type(GhosttyOscCommand);
void* ghostty_osc_command_data(GhosttyOscCommand);
```

### SGR Parser
```c
void ghostty_sgr_new(GhosttyAllocator*, GhosttySgrParser*);
void ghostty_sgr_free(GhosttySgrParser);
void ghostty_sgr_reset(GhosttySgrParser);
void ghostty_sgr_set_params(GhosttySgrParser, uint16_t* params, uint8_t* seps, uint8_t len);
bool ghostty_sgr_next(GhosttySgrParser, GhosttySgrAttr*);
```

### Key Encoder
```c
void ghostty_key_event_new(GhosttyAllocator*, GhosttyKeyEvent*);
void ghostty_key_event_free(GhosttyKeyEvent);
void ghostty_key_event_set_action(GhosttyKeyEvent, GhosttyKeyAction);
void ghostty_key_event_set_key(GhosttyKeyEvent, GhosttyKey);
void ghostty_key_event_set_mods(GhosttyKeyEvent, GhosttyMods);
void ghostty_key_event_set_consumed_mods(GhosttyKeyEvent, GhosttyMods);
void ghostty_key_event_set_composing(GhosttyKeyEvent, bool);
void ghostty_key_event_set_utf8(GhosttyKeyEvent, const char*);
void ghostty_key_event_set_unshifted_codepoint(GhosttyKeyEvent, uint32_t);

void ghostty_key_encoder_new(GhosttyAllocator*, GhosttyKeyEncoder*);
void ghostty_key_encoder_free(GhosttyKeyEncoder);
void ghostty_key_encoder_setopt(GhosttyKeyEncoder, GhosttyKeyEncoderOpt, uint32_t);
int ghostty_key_encoder_encode(GhosttyKeyEncoder, GhosttyKeyEvent, char* buf, size_t, size_t*);
```

### Paste Safety
```c
bool ghostty_paste_is_safe(const char* data, size_t len);
```

## Building libghostty

### Build System (Zig)

```bash
# Build the full library
zig build

# Build libghostty-vt only
zig build lib-vt

# Build xcframework for macOS/iOS
zig build xcframework

# Build via Xcode (macOS app)
zig build xcodebuild
```

### Build Artifacts

| Artifact | Description |
|----------|-------------|
| `GhosttyLib` | Static/shared library for embedding |
| `GhosttyLibVt` | Lightweight VT parsing library |
| `GhosttyXCFramework` | macOS/iOS xcframework for Xcode |
| `GhosttyResources` | Terminfo, shell integration, themes |

### App Runtime Backends

```zig
// Selected at build time:
pub const runtime = switch (build_config.artifact) {
    .exe => switch (build_config.app_runtime) {
        .none => none,     // Headless / libghostty mode
        .gtk => gtk,       // GTK (Linux)
    },
    .lib => embedded,      // macOS/iOS embedding (what we use)
    .wasm_module => browser,
};
```

### Renderer Backends

```zig
pub const Renderer = switch (build_config.renderer) {
    .metal => GenericRenderer(Metal),    // macOS/iOS
    .opengl => GenericRenderer(OpenGL),  // Linux
    .webgl => WebGL,                     // Browser
};
```

## Key Zig Source Files

| File | Purpose |
|------|---------|
| `src/Surface.zig` | Core terminal surface (input, preedit, selection) |
| `src/terminal/Terminal.zig` | VT state machine, character printing, wide char handling |
| `src/terminal/page.zig` | Cell grid with wide character support |
| `src/termio/Termio.zig` | Terminal I/O management |
| `src/termio/Exec.zig` | PTY subprocess management |
| `src/pty.zig` | Platform-abstracted PTY (Posix, Windows, NullPty for iOS) |
| `src/font/shaper/harfbuzz.zig` | HarfBuzz text shaping for CJK |
| `src/unicode/props.zig` | Unicode width properties |
| `src/input/key.zig` | KeyEvent struct with composition tracking |
| `src/apprt/embedded.zig` | macOS/iOS embedding runtime |
| `src/apprt/action.zig` | Action dispatch system |
| `src/renderer/Metal.zig` | Metal GPU renderer |
| `src/terminal/tmux/` | tmux control mode integration |

## How cmux Uses libghostty (Reference Pattern)

cmux (at `~/dev/git/references/cmux/`) is the primary reference for embedding libghostty in a Swift/AppKit app:

1. **Build**: Compiles ghostty submodule into `GhosttyKit.xcframework`
2. **Import**: Uses `module.modulemap` to import C API into Swift
3. **App Init**: Creates `ghostty_config_t` → `ghostty_app_t` with runtime callbacks
4. **Surfaces**: Each terminal pane = one `ghostty_surface_t` rendered via Metal layer
5. **Input**: Overrides `keyDown(with:)` and `performKeyEquivalent(with:)` in NSView
6. **Splits**: Handles `GHOSTTY_ACTION_NEW_SPLIT` in action callback, creates layout
7. **Config**: Reads existing Ghostty config for themes/fonts/colors

Key cmux source files:
- `Sources/GhosttyTerminalView.swift` — NSView wrapping ghostty surface
- `Sources/Workspace.swift` — Workspace model and surface config inheritance
- `Sources/TerminalController.swift` — Unix socket control interface
