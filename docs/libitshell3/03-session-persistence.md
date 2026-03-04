# Session Persistence Mechanisms

## Overview

Session persistence is the core feature that differentiates a terminal multiplexer from a plain terminal emulator. This document analyzes how tmux, zellij, and cmux keep sessions alive and how it-shell3 should approach persistence.

---

## 1. tmux: Daemon Process as Persistence

### Mechanism

tmux sessions persist because the **server process is the persistence**. The server:
1. Forks into a daemon via `proc_fork_and_daemon()`
2. Holds all session/window/pane state in memory
3. Owns all PTY master file descriptors
4. Continues running after all clients disconnect

### Server Lifecycle

```c
// server.c: server_start()
int server_start(struct tmuxproc *client, ...) {
    // Fork to background
    if (proc_fork_and_daemon(&fd) != 0) {
        // Parent: wait for server ready message, then return
        close(fd);
        return 0;
    }

    // Child (server daemon):
    // 1. Create Unix domain socket
    // 2. Set up libevent base
    // 3. Enter event loop (server_loop)
    event_init();
    server_loop();  // Blocks until server decides to exit
}
```

### Exit Conditions

The server only exits when ALL of these are true:
- `exit-empty` option is set AND no sessions remain
- OR `exit-unattached` option is set AND no clients attached
- AND no background jobs are running
- AND all child processes have been reaped

### Limitations

- **No disk persistence**: If the server process is killed (SIGKILL, OOM, reboot), all sessions are lost
- **No scrollback save**: Terminal scrollback is only in memory
- **Single machine**: Sessions cannot be transferred between machines

### What it-shell3 Can Learn

- The daemon-as-persistence model is simple and proven
- Consider adding optional disk-based session state snapshots (like zellij)
- Consider scrollback persistence (like cmux)

---

## 2. Zellij: Daemon + Disk Serialization

### Daemon Process

```rust
// zellij-server/src/lib.rs
pub fn start_server(session_name: String, ...) {
    // Daemonize using the `daemonize` crate
    let daemonize = Daemonize::new()
        .pid_file(pid_file_path)
        .working_directory(std::env::current_dir().unwrap())
        .umask(0o077);

    daemonize.start().expect("Failed to daemonize");

    // Set up local socket listener
    // Enter tokio async runtime
    // Start server threads (screen, pty, plugin, pty_writer, background_jobs)
}
```

### Session State Serialization

Zellij periodically writes session layout state to disk via background jobs:

```rust
// zellij-server/src/background_jobs.rs
enum BackgroundJob {
    WriteSessionStateToDisk,  // Periodic layout snapshot
    // ...
}
```

This enables:
- Session resurrection after server crash
- Layout recovery after unexpected termination
- Session listing without connecting to server

### Session Discovery

Zellij stores session metadata at predictable filesystem locations, allowing `zellij list-sessions` to enumerate active sessions without IPC.

---

## 3. cmux: JSON Snapshot Persistence

### Mechanism

cmux has the most comprehensive persistence system among the references.

### Snapshot Structure

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

// Recursive layout tree
indirect enum SessionWorkspaceLayoutSnapshot: Codable {
    case pane(SessionPaneLayoutSnapshot)
    case split(SessionSplitLayoutSnapshot)
}

struct SessionSplitLayoutSnapshot: Codable {
    var orientation: SplitOrientation  // .horizontal | .vertical
    var dividerPosition: CGFloat
    var first: SessionWorkspaceLayoutSnapshot
    var second: SessionWorkspaceLayoutSnapshot
}

struct SessionPaneLayoutSnapshot: Codable {
    var title: String?
    var directory: String?
    var scrollback: String?          // Preserved terminal output
    var ttyName: String?
    var type: PanelType              // .terminal | .browser
}
```

### Storage Location

```
~/Library/Application Support/cmux/session-<bundleId>.json
```

### Auto-Save Policy

```swift
struct SessionPersistencePolicy {
    static let autosaveInterval: TimeInterval = 8.0  // Every 8 seconds
}
```

### Scrollback Preservation

- **Maximum**: 4000 lines or 400K characters per terminal pane
- **ANSI Safety**: Truncation avoids splitting mid-escape-sequence
- **Restore**: Scrollback written to temp file, replayed via `CMUX_RESTORE_SCROLLBACK_FILE` env var

### Restore Logic

```swift
func shouldRestore() -> Bool {
    // Skip if automated test environment
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return false }
    // Skip if explicitly disabled
    if ProcessInfo.processInfo.environment["CMUX_DISABLE_SESSION_RESTORE"] == "1" { return false }
    // Check for valid snapshot file
    return snapshotFileExists()
}
```

---

## Comparison Matrix

| Feature | tmux | zellij | cmux |
|---------|------|--------|------|
| Persistence Method | Process memory | Process + disk | JSON snapshots |
| Survives server crash | No | Partial (layout) | Yes (full state) |
| Scrollback preserved | No | No | Yes (4000 lines) |
| Layout preserved | In memory only | Written to disk | Full JSON tree |
| Auto-save interval | N/A | Periodic | 8 seconds |
| Session discovery | Socket file | Filesystem | File existence |
| Cross-device | No | No | No (but possible) |

---

## Recommended Approach for it-shell3

### Hybrid Persistence Strategy

1. **Primary**: Daemon process holds live state (like tmux)
   - PTY file descriptors
   - Active terminal state
   - Input/output buffers

2. **Secondary**: Periodic disk snapshots (like cmux)
   - Session layout tree
   - Scrollback buffer (configurable limit)
   - Per-pane metadata (title, CWD, env)
   - CJK preedit state

3. **Snapshot Format**: JSON or MessagePack
   - Human-readable for debugging (JSON)
   - Or fast serialization for large scrollback (MessagePack)

4. **Snapshot Location**:
   ```
   # macOS
   ~/Library/Application Support/it-shell3/sessions/<session-id>.json

   # Linux
   ~/.local/share/it-shell3/sessions/<session-id>.json
   ```

5. **Recovery Flow**:
   ```
   Client connects → Check for running daemon
     → If daemon alive: Attach to existing session
     → If daemon dead but snapshot exists: Start new daemon, restore from snapshot
     → If nothing: Start fresh session
   ```

### Scrollback Persistence Considerations

- **ANSI-safe truncation**: Never split mid-escape-sequence
- **CJK-safe truncation**: Never split mid-grapheme-cluster
- **Compression**: Scrollback can be gzip'd for storage efficiency
- **Incremental**: Only persist new scrollback since last snapshot
