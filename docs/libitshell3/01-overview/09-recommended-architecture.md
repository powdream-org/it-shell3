# Recommended Architecture

## Overview

This document proposes the architecture for it-shell3 based on the feasibility analysis and reference code research.

---

## Architecture Decision: Portable Zig Library (libitshell3)

it-shell3 is a **portable Zig library** (`libitshell3`) that:
- Exports C headers and shared libraries (`.dylib` / `.so`)
- Wraps libghostty's terminal engine
- Provides terminal multiplexer session management (daemon/client)
- Handles CJK preedit synchronization
- Can be consumed by native apps (Swift macOS, future Linux clients)

### Why Zig?

1. **Natural FFI with libghostty**: ghostty is written in Zig — importing and wrapping it is seamless
2. **C ABI export**: Zig can `@export` functions with C calling convention and generate `.h` headers
3. **Cross-platform**: Same codebase targets macOS (now) and Linux (future)
4. **No runtime**: No GC, no runtime overhead — suitable for embedding
5. **Build system**: Zig's build system can compose with ghostty's build system

### Library Architecture

```
libitshell3 (Zig library)
├── C API (exported via ghostty-style .h header)
│   ├── itshell3_daemon_*()      // Daemon lifecycle
│   ├── itshell3_session_*()     // Session management
│   ├── itshell3_client_*()      // Client connection
│   ├── itshell3_pane_*()        // Pane operations
│   ├── itshell3_preedit_*()     // CJK preedit
│   └── itshell3_protocol_*()   // Wire protocol
│
├── Daemon Module (Zig)
│   ├── PTY management (wrap POSIX openpty/forkpty)
│   ├── Session/Tab/Pane state
│   ├── Unix socket listener
│   ├── Client connection manager
│   ├── I/O multiplexer (kqueue/epoll)
│   └── CJK preedit state tracker
│
├── Client Module (Zig)
│   ├── Unix socket connector
│   ├── Protocol message encoder/decoder
│   ├── Surface data feeder (→ libghostty)
│   └── Preedit event forwarder
│
├── Protocol Module (Zig)
│   ├── Message types and serialization
│   ├── Handshake / capability negotiation
│   ├── CJK extension messages
│   └── Control mode text protocol
│
└── Depends on: libghostty (git submodule)
    ├── Terminal engine (VT parser, screen, grid)
    ├── Font/Unicode subsystem
    ├── Renderer (Metal, OpenGL)
    └── PTY primitives
```

### Build System

```zig
// build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Import ghostty as dependency
    const ghostty_dep = b.dependency("ghostty", .{
        .target = target,
        .optimize = optimize,
    });

    // Static library
    const lib = b.addStaticLibrary(.{
        .name = "itshell3",
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.addModule("ghostty", ghostty_dep.module("ghostty"));

    // Shared library (.dylib / .so)
    const shared = b.addSharedLibrary(.{
        .name = "itshell3",
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Install C header
    b.installFile("include/itshell3.h", "include/itshell3.h");

    // Install libraries
    b.installArtifact(lib);
    b.installArtifact(shared);
}
```

### C API Design (itshell3.h)

```c
#ifndef ITSHELL3_H
#define ITSHELL3_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================
// Opaque handle types
// ============================================================

typedef void* itshell3_daemon_t;
typedef void* itshell3_client_t;
typedef void* itshell3_session_t;
typedef void* itshell3_tab_t;
typedef void* itshell3_pane_t;

// ============================================================
// Configuration
// ============================================================

typedef struct {
    const char* socket_path;     // Unix socket path (NULL = default)
    const char* session_dir;     // Session persistence directory
    uint32_t    max_scrollback;  // Max scrollback lines per pane
    bool        cjk_enabled;     // Enable CJK extensions
    uint8_t     ambiguous_width; // 1 or 2 for ambiguous-width chars
} itshell3_config_s;

// ============================================================
// Daemon API (server-side)
// ============================================================

itshell3_daemon_t itshell3_daemon_new(itshell3_config_s config);
void              itshell3_daemon_free(itshell3_daemon_t);
int               itshell3_daemon_start(itshell3_daemon_t);  // Fork & listen
int               itshell3_daemon_run(itshell3_daemon_t);    // Run in foreground
void              itshell3_daemon_stop(itshell3_daemon_t);

// ============================================================
// Client API (connect to daemon)
// ============================================================

itshell3_client_t itshell3_client_new(const char* socket_path);
void              itshell3_client_free(itshell3_client_t);
int               itshell3_client_connect(itshell3_client_t);
void              itshell3_client_disconnect(itshell3_client_t);
int               itshell3_client_attach(itshell3_client_t, const char* session_name);
void              itshell3_client_detach(itshell3_client_t);

// ============================================================
// Session management
// ============================================================

itshell3_session_t itshell3_session_new(itshell3_daemon_t, const char* name);
void               itshell3_session_free(itshell3_session_t);
const char*        itshell3_session_name(itshell3_session_t);

// ============================================================
// Tab management
// ============================================================

itshell3_tab_t itshell3_tab_new(itshell3_session_t, const char* name);
void           itshell3_tab_free(itshell3_tab_t);
void           itshell3_tab_set_name(itshell3_tab_t, const char* name);

// ============================================================
// Pane management
// ============================================================

typedef enum {
    ITSHELL3_SPLIT_RIGHT,
    ITSHELL3_SPLIT_DOWN,
    ITSHELL3_SPLIT_LEFT,
    ITSHELL3_SPLIT_UP,
} itshell3_split_direction_e;

typedef enum {
    ITSHELL3_NAVIGATE_PREVIOUS,
    ITSHELL3_NAVIGATE_NEXT,
    ITSHELL3_NAVIGATE_UP,
    ITSHELL3_NAVIGATE_DOWN,
    ITSHELL3_NAVIGATE_LEFT,
    ITSHELL3_NAVIGATE_RIGHT,
} itshell3_navigate_direction_e;

itshell3_pane_t itshell3_pane_new(itshell3_tab_t, const char* command);
void            itshell3_pane_free(itshell3_pane_t);
itshell3_pane_t itshell3_pane_split(itshell3_pane_t, itshell3_split_direction_e);
void            itshell3_pane_close(itshell3_pane_t);
void            itshell3_pane_focus(itshell3_pane_t);
void            itshell3_pane_navigate(itshell3_pane_t, itshell3_navigate_direction_e);
void            itshell3_pane_resize(itshell3_pane_t, uint32_t cols, uint32_t rows);
void            itshell3_pane_write(itshell3_pane_t, const char* data, size_t len);

// ============================================================
// CJK Preedit API
// ============================================================

typedef struct {
    uint32_t pane_id;
    const char* text;        // UTF-8 preedit text
    size_t text_len;
    uint32_t cursor_x;
    uint32_t cursor_y;
} itshell3_preedit_s;

void itshell3_preedit_start(itshell3_pane_t, uint32_t cursor_x, uint32_t cursor_y);
void itshell3_preedit_update(itshell3_pane_t, const char* text, size_t len);
void itshell3_preedit_end(itshell3_pane_t, const char* committed, size_t len);

// ============================================================
// Callbacks (host provides these)
// ============================================================

typedef void (*itshell3_output_cb)(void* userdata, itshell3_pane_t pane,
                                    const char* data, size_t len);
typedef void (*itshell3_preedit_cb)(void* userdata, itshell3_preedit_s preedit);
typedef void (*itshell3_pane_event_cb)(void* userdata, itshell3_pane_t pane, int event);

typedef struct {
    void* userdata;
    itshell3_output_cb on_output;         // Terminal output from pane
    itshell3_preedit_cb on_preedit;       // CJK preedit update from another client
    itshell3_pane_event_cb on_pane_event; // Pane lifecycle events
} itshell3_callbacks_s;

void itshell3_client_set_callbacks(itshell3_client_t, itshell3_callbacks_s);

// ============================================================
// Protocol info
// ============================================================

typedef struct {
    uint8_t  protocol_version;
    uint32_t cjk_capabilities;   // Bitflags
    const char* version_string;
} itshell3_info_s;

itshell3_info_s itshell3_info(void);

#ifdef __cplusplus
}
#endif

#endif // ITSHELL3_H
```

### Module Layout (Zig Source)

```
src/
├── lib.zig              # Library entry point, C exports
├── daemon/
│   ├── Daemon.zig       # Daemon lifecycle, socket listener
│   ├── Session.zig      # Session state management
│   ├── Tab.zig          # Tab state
│   ├── Pane.zig         # Pane state, PTY ownership
│   ├── Layout.zig       # Binary split tree
│   └── ClientManager.zig # Connected client tracking
├── client/
│   ├── Client.zig       # Client connection, attach/detach
│   ├── SurfaceFeeder.zig # Feed data to libghostty surface
│   └── PreeditManager.zig # Local IME → protocol bridge
├── protocol/
│   ├── Message.zig      # Message types and encoding
│   ├── Handshake.zig    # Capability negotiation
│   ├── Transport.zig    # Unix socket read/write
│   └── CjkExtensions.zig # CJK-specific messages
├── pty/
│   ├── Pty.zig          # Platform-abstracted PTY
│   └── Subprocess.zig   # Child process management
└── unicode/
    └── CjkState.zig     # Preedit state, Jamo decomposition
```

---

## Integration with Terminal App (it-shell3)

The future it-shell3 is a **complete terminal emulator** for macOS and iOS (starting with macOS). It replaces apps like Terminal.app, iTerm2, or Ghostty.app — not a wrapper around them. It will consume libitshell3:

```
┌─────────────────────────────────────────────────┐
│          it-shell3 App (Swift/AppKit)            │
│                                                  │
│  ┌────────────────┐  ┌─────────────────────┐    │
│  │ UI Layer       │  │ libghostty           │    │
│  │ (Swift)        │  │ (terminal rendering) │    │
│  │ - Tab bar      │  │ - Metal GPU          │    │
│  │ - Split views  │  │ - Font shaping       │    │
│  │ - Status bar   │  │ - VT parsing         │    │
│  └───────┬────────┘  └──────────┬──────────┘    │
│          │                      │                │
│  ┌───────┴──────────────────────┴──────────┐    │
│  │         libitshell3 (C API)              │    │
│  │  - Daemon management                    │    │
│  │  - Client connection                    │    │
│  │  - Session/tab/pane state               │    │
│  │  - CJK preedit sync                    │    │
│  │  - Protocol encoding                   │    │
│  └─────────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘
```

---

## Technology Stack Summary

| Component | Technology | Rationale |
|-----------|-----------|-----------|
| Library language | Zig | Natural FFI with ghostty, C export, cross-platform |
| Terminal engine | libghostty (Zig) | CJK-ready, GPU-rendered, battle-tested |
| Build system | Zig build | Composes with ghostty's build system |
| IPC transport | Unix domain sockets | Proven (tmux), fast, FD passing |
| Serialization | Custom binary (like tmux) | Low overhead, control over format |
| Persistence | JSON snapshots | Human-readable, debuggable |
| macOS app | Swift/AppKit + libitshell3 + libghostty | Complete terminal emulator (first target) |
| iOS app | Swift/UIKit + libitshell3 + libghostty | Complete terminal emulator (client-only, connects to macOS/Linux daemon) |
| Future Linux app | GTK/other + libitshell3 + libghostty | Same library, different UI |
