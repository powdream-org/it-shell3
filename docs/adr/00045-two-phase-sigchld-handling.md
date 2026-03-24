# 00045. Two-Phase SIGCHLD Handling

- Date: 2026-03-24
- Status: Accepted

## Context

When a child process exits in a terminal multiplexer, the daemon receives
SIGCHLD. The naive approach — immediately destroying the pane in the SIGCHLD
handler — risks losing the child's final output. PTY data buffered in the kernel
may not have been read yet when the signal fires. If the daemon closes the PTY
fd and tears down the pane before draining that buffer, the user never sees the
last lines of output (e.g., a build's final error message or a command's exit
summary).

tmux handles this by reading remaining PTY data after child exit before removing
the pane. The challenge in a kqueue-based event loop is that SIGCHLD and PTY
read events may arrive in the same `kevent64()` batch, requiring explicit
processing order.

Alternatives considered:

- **Immediate destruction**: Simple but loses final output. Rejected.
- **Timer-based delay**: Wait N ms after SIGCHLD before destroying. Fragile —
  the right delay depends on output volume and system load.
- **Two-phase with dual flags**: Mark on SIGCHLD, drain via normal PTY read
  path, destroy when both flags are set. Chosen.

## Decision

Adopt a two-phase approach to child process exit handling:

**Phase 1 — SIGCHLD handler (reap + mark)**: When `EVFILT_SIGNAL` fires, call
`waitpid(-1, WNOHANG)` in a loop to reap all exited children. For each, set
`pane.pane_exited = true` and record exit status. Do NOT close the PTY fd or
destroy the pane.

**Phase 2 — PTY read handler (drain + destroy)**: The normal PTY read path
continues to drain remaining data. When `read()` returns 0 (EOF) or
`EVFILT_READ` delivers `EV_EOF`, set `pane.pty_eof = true`. When both
`pane_exited` and `pty_eof` are set (regardless of arrival order), trigger
`executePaneDestroyCascade()`.

**Event processing priority**: When a single `kevent64()` call returns both
`EVFILT_SIGNAL` and `EVFILT_READ` events, `EVFILT_SIGNAL` MUST be processed
first. This ensures `pane_exited` is set before the PTY read handler checks for
it.

## Consequences

- **Final output preserved**: The user always sees the child's last output
  before the pane disappears. Critical for build tools, test runners, and any
  command whose exit message matters.
- **Order-independent correctness**: The dual-flag model (`pane_exited` +
  `pty_eof`) handles both arrival orders — SIGCHLD before EOF and EOF before
  SIGCHLD — without special-casing.
- **Event loop constraint**: The daemon's event dispatch loop must enforce
  signal-before-read priority within each `kevent64()` batch. This is a one-time
  implementation detail, not an ongoing burden.
- **Slightly more complex pane lifecycle**: Panes now have a transient "exited
  but not yet destroyed" state where `pane_exited = true` but `pty_eof = false`.
  Code that iterates panes must account for this state (e.g., not sending new
  input to an exited pane).
