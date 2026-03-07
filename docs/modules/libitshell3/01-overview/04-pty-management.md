# PTY Management

## Overview

PTY (pseudo-terminal) management is the foundation of terminal multiplexing. The daemon owns PTY master file descriptors, manages child processes, and forwards I/O between clients and shell processes.

---

## 1. Ghostty PTY Implementation

**Source**: `vendors/ghostty/src/pty.zig`

### Platform Abstraction

```zig
pub const Pty = switch (builtin.os.tag) {
    .windows => WindowsPty,
    .ios => NullPty,     // iOS cannot fork — uses NullPty
    else => PosixPty,    // macOS, Linux, FreeBSD
};
```

### PosixPty (macOS/Linux)

```zig
pub const PosixPty = struct {
    master: posix.fd_t,
    slave: posix.fd_t,

    pub fn open(size: posix.winsize) !PosixPty {
        // 1. Call openpty() to create master/slave fd pair
        // 2. Set CLOEXEC on master fd
        // 3. Enable IUTF8 mode (CRITICAL for CJK input)
        var attrs: posix.termios = undefined;
        tcgetattr(slave, &attrs);
        attrs.c_iflag |= IUTF8;  // UTF-8 input processing
        tcsetattr(slave, .NOW, &attrs);
        return .{ .master = master, .slave = slave };
    }

    pub fn getMode() Mode {
        // Read termios to detect canonical/echo mode
        // Used to detect password input prompts
    }

    pub fn setSize(ws: posix.winsize) void {
        ioctl(master, TIOCSWINSZ, &ws);
    }

    pub fn getSize() posix.winsize {
        ioctl(master, TIOCGWINSZ, &ws);
    }

    pub fn childPreExec() void {
        // Called after fork(), in the child process:
        // 1. Reset all signal handlers to default
        // 2. setsid() — create new session
        // 3. ioctl(slave, TIOCSCTTY, 0) — set controlling terminal
        // 4. Close master and slave fds
    }
};
```

### NullPty (iOS)

iOS cannot fork processes, so it uses a NullPty that provides no-op implementations. This means on iOS, it-shell3 must act as a **client only**, connecting to a remote daemon.

### IUTF8 Flag — Critical for CJK

The `IUTF8` flag on the PTY slave is essential:
- Tells the kernel line discipline to treat input as UTF-8
- Ensures backspace deletes a full multi-byte character, not just one byte
- Without it, Korean Jamo decomposition and Chinese Pinyin editing break

---

## 2. Ghostty Terminal I/O Architecture

**Source**: `vendors/ghostty/src/termio/`

### Termio Layer

```zig
// Termio.zig
pub const Termio = struct {
    terminal: Terminal,              // VT state machine
    backend: termio.Backend,         // I/O backend (Exec)
    terminal_stream: StreamHandler.Stream,  // Escape sequence parser
    renderer_state: *RenderState,    // Shared state with renderer
    size: CachedSize,               // Terminal dimensions
};
```

### Exec Backend (Subprocess Management)

```zig
// Exec.zig
pub const Exec = struct {
    subprocess: Subprocess,          // PTY + child process

    pub fn threadEnter() void {
        // 1. Start subprocess (fork + exec shell)
        // 2. Create xev.Process watcher for child exit
        // 3. Start read thread for PTY output
        // 4. Start termios polling timer (200ms)
    }
};
```

### I/O Threading Model

```
┌───────────────────┐     ┌──────────────────────┐
│    Read Thread     │     │    Main I/O Thread    │
│  (dedicated)       │     │  (xev event loop)     │
│                    │     │                        │
│  read(master_fd)   │────>│  Parse escape seqs     │
│  → buffer data     │     │  Update terminal state │
│  → notify main     │     │  Wake renderer         │
│                    │     │                        │
│                    │     │  Write to PTY:          │
│                    │     │  xev.Stream(master_fd)  │
└───────────────────┘     └──────────────────────┘
```

- **Read Thread**: Dedicated thread doing blocking `read()` on PTY master fd for low-jitter data processing
- **Main Thread**: xev event loop handles writing to PTY, parsing terminal escape sequences, updating terminal state
- **Termios Polling**: 200ms timer to detect mode changes (e.g., password input detection)

---

## 3. tmux PTY Management

**Source**: `~/dev/git/references/tmux/spawn.c`, `tty.c`

### PTY Creation

```c
// spawn.c
struct window_pane* spawn_pane(struct spawn_context *sc, char **cause) {
    // 1. Create PTY pair via forkpty()
    wp->fd = forkpty(&wp->fd, NULL, NULL, &ws);

    if (wp->fd == 0) {
        // Child process:
        // - Close server socket
        // - Reset signal handlers
        // - Set environment (TERM, SHELL, etc.)
        // - exec() the shell/command
    }

    // Parent (server):
    // 2. Set master fd non-blocking
    setblocking(wp->fd, 0);

    // 3. Create bufferevent for async I/O
    wp->event = bufferevent_new(wp->fd, ...);

    // 4. Enable reading
    bufferevent_enable(wp->event, EV_READ|EV_WRITE);
}
```

### FD Passing (Client → Server)

tmux passes the client's stdin/stdout FDs to the server via `sendmsg(2)`:

```c
// client.c
void client_send_identify(void) {
    // Pass stdin FD via cmsg ancillary data
    proc_send(peer, MSG_IDENTIFY_STDIN, -1, NULL, 0);
    // The FD is attached as ancillary data in the sendmsg() call

    // Pass stdout FD similarly
    proc_send(peer, MSG_IDENTIFY_STDOUT, -1, NULL, 0);
}
```

This allows the server to:
- Read terminal capabilities from the client's actual terminal
- Set raw mode on the client's terminal
- Write rendered output directly to the client's terminal

### Per-Pane Output Tracking

```c
// Each pane tracks how much output each client has consumed
struct window_pane {
    struct evbuffer *buffer;     // Output buffer from PTY
    TAILQ_HEAD(, window_pane_offset) offset_list;  // Per-client offsets
};

struct window_pane_offset {
    struct client *client;
    size_t offset;               // How far this client has read
    TAILQ_ENTRY(window_pane_offset) entry;
};
```

---

## 4. Zellij PTY Management

**Source**: `~/dev/git/references/zellij/zellij-server/src/`

### PTY Creation (Unix)

```rust
// os_input_output_unix.rs
pub fn openpty() -> (RawFd, RawFd) {
    let pty = nix::pty::openpty(None, None).unwrap();
    (pty.master, pty.slave)
}

pub fn spawn_terminal(command: TerminalAction, ...) -> Result<ChildProcess> {
    let (master, slave) = openpty();

    let child = unsafe {
        Command::new(&shell)
            .pre_exec(move || {
                // In child process:
                setsid()?;                           // New session
                ioctl(slave, TIOCSCTTY, 0)?;         // Set controlling terminal
                dup2(slave, STDIN_FILENO)?;
                dup2(slave, STDOUT_FILENO)?;
                dup2(slave, STDERR_FILENO)?;
                close(master)?;
                close(slave)?;
                Ok(())
            })
            .spawn()?
    };

    close(slave);  // Parent doesn't need slave
    Ok(ChildProcess { master, child })
}
```

### Async PTY Reading

```rust
// os_input_output_unix.rs
pub struct RawFdAsyncReader {
    fd: RawFd,
    async_fd: Option<AsyncFd<RawFd>>,  // Lazily registered with tokio
}

impl RawFdAsyncReader {
    pub async fn read(&mut self, buf: &mut [u8]) -> Result<usize> {
        // Lazily register FD with tokio's async reactor
        if self.async_fd.is_none() {
            self.async_fd = Some(AsyncFd::new(self.fd)?);
        }

        // Wait for read readiness
        let mut guard = self.async_fd.as_ref().unwrap().readable().await?;
        // Perform non-blocking read
        match nix::unistd::read(self.fd, buf) {
            Ok(n) => Ok(n),
            Err(Errno::EAGAIN) => {
                guard.clear_ready();
                Err(...)
            }
        }
    }
}
```

### PTY Writer Thread

```rust
// pty_writer.rs
enum PtyWriteInstruction {
    Write(Vec<u8>, RawFd),       // Write bytes to PTY
    ResizePty(PaneGeom, RawFd),  // Resize PTY via ioctl
    StartCachingResizes,          // Buffer resizes
    ApplyCachedResizes,           // Flush buffered resizes
}
```

---

## 5. PTY Architecture for it-shell3

### Design Decisions

#### Where PTY Lives: In the Daemon

The daemon must own all PTY master FDs because:
- PTY FDs don't survive process restarts
- The daemon is the long-lived process
- Child processes (shells) are parented to the daemon

#### Relationship with libghostty

**Key question**: Should it-shell3 use libghostty's built-in PTY management (via `Exec` backend) or manage PTYs directly?

**Option A: Use libghostty's PTY management**
- Pros: Less code, proven, includes termios polling
- Cons: Less control over PTY lifecycle, harder to serialize state

**Option B: Manage PTYs directly, use libghostty for rendering only**
- Pros: Full control over PTY lifecycle, can implement session persistence
- Cons: Must reimplement some of ghostty's I/O layer

**Recommendation: Option B** — The daemon manages PTYs directly, and the client uses libghostty surfaces for rendering. The daemon reads from PTY master FDs and forwards terminal output to connected clients. The client feeds output into libghostty's terminal state machine for rendering.

This is analogous to how iTerm2's tmux integration works: iTerm2 handles rendering while tmux manages PTYs.

#### iOS Considerations

iOS cannot fork processes (`NullPty`), so:
- iOS app is always a **client** connecting to a macOS/Linux daemon
- Network transport needed (not just Unix sockets) for cross-device
- Could use SSH tunneling or a custom protocol over TCP/TLS

### Proposed PTY Flow

```
┌────────────────────────────────────────────────────────┐
│                    it-shell3 Daemon                     │
│                                                        │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐         │
│  │ Pane 1   │    │ Pane 2   │    │ Pane 3   │         │
│  │ PTY(m/s) │    │ PTY(m/s) │    │ PTY(m/s) │         │
│  │ bash     │    │ vim      │    │ python   │         │
│  └────┬─────┘    └────┬─────┘    └────┬─────┘         │
│       │               │               │                │
│       └───────────────┼───────────────┘                │
│                       │                                │
│              ┌────────┴────────┐                       │
│              │  I/O Multiplexer │                       │
│              │  (epoll/kqueue)  │                       │
│              └────────┬────────┘                       │
│                       │                                │
│              ┌────────┴────────┐                       │
│              │ Client Manager  │                       │
│              │ (Unix socket)   │                       │
│              └────────┬────────┘                       │
└───────────────────────┼────────────────────────────────┘
                        │ Unix Domain Socket
┌───────────────────────┼────────────────────────────────┐
│                       │                                │
│              ┌────────┴────────┐                       │
│              │ Protocol Client │                       │
│              └────────┬────────┘                       │
│                       │                                │
│              ┌────────┴────────┐                       │
│              │ libghostty      │                       │
│              │ Surface(s)      │                       │
│              │ (Metal Render)  │                       │
│              └─────────────────┘                       │
│                                                        │
│                    it-shell3 Client                     │
└────────────────────────────────────────────────────────┘
```

### IUTF8 and CJK Requirements

**Always set IUTF8 on PTY creation**:
```c
struct termios attrs;
tcgetattr(slave_fd, &attrs);
attrs.c_iflag |= IUTF8;
tcsetattr(slave_fd, TCSANOW, &attrs);
```

This ensures:
- Kernel line discipline treats input as UTF-8
- Backspace correctly deletes multi-byte characters
- Essential for Korean Jamo decomposition to work at the kernel level
