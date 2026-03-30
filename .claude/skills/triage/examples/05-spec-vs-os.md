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

The spec assumes a causal chain that does not exist in any kernel:

```
What the spec assumes:
  shell forks child → child calls tcsetpgrp() → kqueue fires NOTE_FORK → daemon updates foreground_pid

What actually happens on macOS:
  shell forks child → child calls tcsetpgrp() → [NO EVENT] → daemon never knows

NOTE_FORK fires on fork(), not on tcsetpgrp(). These are different kernel operations.
```

The spec (Section 7.4) says: "When the shell forks a child that calls
`tcsetpgrp()` to become the foreground process group leader, the daemon receives
a kevent notification." This conflates two distinct events — `fork(2)` (which
kqueue can observe) and `tcsetpgrp()` (which no kqueue filter covers). There is
no `NOTE_TCSETPGRP` or `NOTE_PGRP` flag.

**Platform comparison for actual foreground PID detection:**

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
