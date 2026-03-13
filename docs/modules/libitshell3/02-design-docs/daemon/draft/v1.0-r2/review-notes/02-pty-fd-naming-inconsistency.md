# pty_master_fd vs pty_fd Naming Inconsistency

**Date**: 2026-03-10
**Raised by**: verification team
**Severity**: LOW
**Affected docs**: `v0.2/03-lifecycle-and-connections.md` — Section 1.1 Step 6 pseudocode
**Status**: open

---

## Problem

In doc 03 Section 1.1 Step 6 pseudocode, the `forkpty` result is bound to `pty_master_fd`, but the kqueue registration line immediately after says `EVFILT_READ on pty_fd`. Two names for the same fd within one code block.

All other documents use `pty_fd` exclusively. The `Pane` struct declares `pty_fd: posix.fd_t`.

## Analysis

Internal naming inconsistency within a single code block. `pty_master_fd` is technically more precise (it is the master side of the PTY pair), but the project convention is `pty_fd` everywhere else. Mismatch could confuse an implementor reading the pseudocode.

Low severity because the intent is unambiguous — there is only one fd in scope.

## Proposed Change

Replace `pty_master_fd` with `pty_fd` in the Step 6 pseudocode block.

## Owner Decision

Left to designers for resolution.

## Resolution

