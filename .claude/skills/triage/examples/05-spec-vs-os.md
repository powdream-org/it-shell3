## Example 5: Spec <-> OS Behavior Conflict

### What

The daemon behavior spec requires foreground process tracking via `EVFILT_PROC`
with `NOTE_FORK` on kqueue, stating that the daemon monitors process group
leadership changes to determine which process currently owns the terminal
foreground. However, macOS kqueue's `EVFILT_PROC` with `NOTE_FORK` only fires
for direct child process fork events, not for process group leadership changes
(i.e., `tcsetpgrp` calls). Linux does not support kqueue at all and requires a
completely different mechanism.

### Why

Foreground process tracking is essential for two features: (1) displaying the
current foreground command name in the pane title bar, and (2) sending `SIGTERM`
to the correct process group when the user closes a pane that has a running
foreground job. If the daemon cannot reliably determine which process is in the
foreground, pane titles show stale information and pane close may kill the wrong
process group or leave orphaned processes.

### Who

The daemon behavior spec (`docs/modules/libitshell3/daemon-behavior.md`, Section
7.4) vs. macOS kqueue behavior (`man 2 kqueue`, EVFILT_PROC section) and Linux's
lack of kqueue entirely.

### When

Introduced in daemon behavior spec v1.0-r5 during Plan 2. The spec author likely
tested `EVFILT_PROC` with `NOTE_FORK` and confirmed it fires on `fork()`, but
did not verify whether it fires on foreground process group changes, which are a
different kernel event (`tcsetpgrp` modifying the terminal's controlling process
group).

### Where

**Spec quote** (`docs/modules/libitshell3/daemon-behavior.md`, lines 423-441):

```
## 7.4 Foreground Process Tracking

The daemon MUST track which process currently owns the foreground of
each PTY. This is used for pane title updates and safe pane teardown.

The daemon registers a kqueue EVFILT_PROC filter with NOTE_FORK on the
PTY's initial child process (the shell). When the shell forks a child
that calls tcsetpgrp() to become the foreground process group leader,
the daemon receives a kevent notification and updates the pane's
foreground_pid field.

When a pane is closed by the user, the daemon sends SIGTERM to the
process group identified by foreground_pid, waits up to 5 seconds,
then sends SIGKILL if the group has not exited.

The daemon MUST NOT poll /proc or use ptrace for foreground detection.
These mechanisms are either unavailable (macOS has no /proc/pid/stat)
or require elevated privileges.
```

**Actual macOS kqueue behavior** (`man 2 kqueue` on macOS 14, EVFILT_PROC
section, abridged):

```
EVFILT_PROC
     Takes the process ID to monitor as the identifier. The events to
     watch for are:

     NOTE_EXIT      The process has exited.

     NOTE_FORK      The process has called fork(2).

     NOTE_EXEC      The process has executed a new process via
                    execve(2) or similar call.

     NOTE_SIGNAL    The process was sent a signal. Status can be
                    checked via waitpid(2) or similar call.
```

There is no `NOTE_TCSETPGRP`, `NOTE_PGRP`, or any flag related to foreground
process group changes. `NOTE_FORK` fires when `fork(2)` is called, period. A
child process calling `tcsetpgrp()` to seize the foreground generates no kqueue
event whatsoever. The spec conflates "fork" with "foreground process group
change" -- they are distinct kernel operations.

**Empirical verification** (test program on macOS 14.4):

```zig
// Register EVFILT_PROC with NOTE_FORK on shell PID
// Then run: sleep 10 &; fg   (background then foreground)
//
// Result: NOTE_FORK fires when `sleep` is forked.
//         NO event fires when `fg` calls tcsetpgrp().
//         NO event fires when `sleep` becomes foreground PG leader.
//
// Conclusion: kqueue cannot observe tcsetpgrp() calls.
```

**Platform divergence for actual foreground PID detection:**

| Platform | Mechanism                      | Availability           |
| -------- | ------------------------------ | ---------------------- |
| macOS    | `tcgetpgrp(pty_fd)`            | Always (POSIX)         |
| macOS    | `EVFILT_PROC NOTE_FORK`        | Fork only, not pgrp    |
| macOS    | `/proc/<pid>/stat` field 8     | Not available          |
| Linux    | `tcgetpgrp(pty_fd)`            | Always (POSIX)         |
| Linux    | `/proc/<pid>/stat` field 8     | Available, no root     |
| Linux    | Netlink proc connector         | Requires CAP_NET_ADMIN |
| Both     | Poll `tcgetpgrp()` on interval | Works but spec forbids |

The only cross-platform mechanism that actually detects foreground process group
changes is `tcgetpgrp(pty_fd)`, which returns the current foreground process
group ID. But it is a synchronous query, not an event-driven notification. Using
it requires periodic polling, which the spec explicitly prohibits in the final
paragraph of Section 7.4.

**Concrete impact:** Foreground process tracking is impossible with the
mechanism specified in the daemon behavior spec. On macOS, `EVFILT_PROC` with
`NOTE_FORK` does not fire on foreground process group changes. On Linux, kqueue
does not exist at all. The only portable mechanism (`tcgetpgrp` polling) is
explicitly prohibited by the spec. The spec must be revised to either allow
polling-based detection (with a defined interval and jitter budget) or adopt a
hybrid approach such as using `NOTE_FORK`/`NOTE_EXEC` to detect new processes
and `tcgetpgrp` to confirm which one is foreground.

### How

The owner needs to decide how foreground process tracking should work
cross-platform. Options include but are not limited to: revising the spec to
allow `tcgetpgrp()` polling at a defined interval (e.g., 250 ms), using
`EVFILT_PROC` events as triggers to call `tcgetpgrp()` (event-driven where
possible, poll as fallback), or introducing a platform abstraction layer where
macOS uses `EVFILT_PROC` + `tcgetpgrp` and Linux uses the proc connector or
`/proc` polling. The "no polling" constraint in the spec should also be
revisited, as no event-driven mechanism exists for `tcsetpgrp` on any supported
platform.
