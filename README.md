# it-shell3

it-shell3 is a next-generation terminal ecosystem designed to overcome the limitations of traditional terminal multiplexers by providing a seamless development experience, particularly regarding CJK input processing, complex key combinations, and robust session management.

## Project Goals

- **Perfect CJK Support:** Built-in server-side IME ensures flawless Korean, Chinese, and Japanese input processing across all environments.
- **Rich Key Handling:** Preserves complex key combinations such as Shift+Enter or Ctrl+Semicolon that are often lost in standard terminal protocols.
- **Session Persistence:** A dedicated daemon manages multiplexing, ensuring sessions and pane layouts persist even if the client application is closed.
- **Thin Client Strategy:** All heavy processing—including VT emulation, SSH, and IME—is handled by the Zig daemon. The client application focuses exclusively on rendering and event capturing.

---

## Architecture

1. **Multiplexer Daemon (Server):**
   - High-performance VT emulation powered by `libghostty`.
   - Unicode/CJK composition via `libitshell3-ime`.
   - Session and window management via `libitshell3`.
2. **Client SDK (Zig):**
   - A standalone static library (.a) used by the app layer.
   - Abstracts the transport layer (Local Unix Socket vs. SSH Tunnel).
3. **App Layer (Client):**
   - Platform-specific UI layer (e.g., Swift for macOS).
   - Direct invocation of the Client SDK via C FFI (Foreign Function Interface).

---

## Client Connectivity Modes

The Client SDK automatically handles the complexity of connecting to a daemon based on the target environment. The UI layer (Swift) simply provides a configuration, and the SDK manages the transport.



### 1. Local Mode (Direct Unix Socket)
- **Scenario:** Developing or running on a local macOS host where the daemon is active.
- **Mechanism:** The SDK connects directly to the Unix Domain Socket (e.g., `/tmp/it-shell.sock`).
- **Benefit:** Lowest possible latency with zero encryption overhead.

### 2. Remote Mode (SSH + Unix Socket Bridge)
- **Scenario:** Connecting to a daemon running on a remote Linux server or a separate Mac.
- **Mechanism:** 1. The SDK establishes a secure connection using **`libssh2`**.
  2. It requests a **StreamLocal Forwarding** channel through the SSH session.
  3. The remote Unix socket is bridged to the client, allowing the application to use the standard it-shell protocol over an encrypted tunnel.
- **Benefit:** Secure, firewall-friendly access using existing SSH infrastructure.

---

## Directory Structure

In this architecture, the `daemon/` directory acts as the primary root for the Zig build system.

```text
it-shell3/
├── app/                    # Client UI applications
│   ├── macos/               # macOS App (Swift/Metal)
│   └── (ios)/               # Currently not present; will start after PoC validation
├── daemon/                 # Primary Zig Project Root
│   ├── build.zig           # Workspace Build Script (Defines Daemon & SDK targets)
│   ├── build.zig.zon       # Dependency management (libssh2, ghostty)
│   ├── main.zig            # Entry point for the it-shell-daemon binary
│   └── include/            # Internal headers for the daemon
├── modules/                # Core Logic Modules
│   ├── libitshell3/         # Server Core (Multiplexing and Session management)
│   ├── libitshell3-client/  # Client SDK (SSH and IPC bridging)
│   ├── libitshell3-ime/     # CJK IME Engine (Shared/Server)
│   └── libitshell3-protocol/# Shared binary protocol definitions
└── vendors/                # External Source Dependencies
    ├── ghostty/             # Ghostty repository (Git Submodule)
    └── libhangul/           # Korean Hangul composition library (Git Submodule)
```

---

## Automated Header Generation

To ensure the client layer always has an up-to-date interface, it-shell3 utilizes Zig's built-in C header generation for the Client SDK.

### 1. Zig Code Requirements
Functions and types intended for FFI must be marked with `export` and `extern` respectively in `modules/libitshell3-client/src/root.zig`.

### 2. Build Configuration
The `daemon/build.zig` is configured to emit the header automatically during the build process:

```zig
const lib = b.addStaticLibrary(.{
    .name = "itshell3-client",
    .root_source_file = b.path("../modules/libitshell3-client/src/root.zig"),
});

lib.emit_h = .emit; // Enables automatic header generation
```

---

## Build and Client SDK Integration

### 1. Build Orchestration (daemon/build.zig)

The `build.zig` defines separate targets for the server and the multi-architecture client SDK.

```zig
// (Standard multi-target logic for macOS and iOS targets)
const daemon_exe = b.addExecutable(.{ ... });
const client_lib = b.addStaticLibrary(.{ ... });
```

### 2. Execution and Packaging
Run the build commands from the `daemon/` folder:

```bash
cd daemon

# Build all client targets
zig build client-libs

# Create XCFramework for Apple platforms
xcodebuild -create-xcframework \
  -library ../artifacts/lib/macos-arm64/libitshell3-client.a -headers zig-out/include/ \
  -library ../artifacts/lib/macos-x86_64/libitshell3-client.a -headers zig-out/include/ \
  -library ../artifacts/lib/ios-arm64/libitshell3-client.a -headers zig-out/include/ \
  -output ../artifacts/it-shell-sdk.xcframework
```

---

## Integration (Swift)

The Swift application uses an `extern struct` to pass connectivity requirements to the Zig SDK.

```swift
// Swift Example
let config = itshell_config(
    type: .ssh, 
    host: "dev.server.com", 
    user: "heejoon.kang", 
    socket_path: "/tmp/it-shell.sock"
)
itshell_connect(config)
```

---

## Dependencies
- [Ghostty](https://github.com/ghostty-org/ghostty) (Git Submodule at vendors/ghostty)
- [libhangul](https://github.com/libhangul/libhangul) (Git Submodule at vendors/libhangul)
- [libssh2](https://github.com/allyourcodebase/libssh2) (Managed via daemon/build.zig.zon)
