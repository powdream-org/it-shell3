---
name: impl-resolve-target
description: >
  Resolve implementation target argument to filesystem path and team directory.
  Internal skill invoked by the implementation team leader at cycle start.
user-invocable: false
---

# Resolve Implementation Target

Target: **$ARGUMENTS**

## Target Resolution

Targets are resolved by **filesystem discovery** across all source directories.

### Step 1: Discover all targets

Targets live across three top-level directories with different structures:

```bash
# Libraries — each subdirectory is a target
ls -d modules/*/ 2>/dev/null

# Daemon — the directory itself is a target (contains build.zig + main.zig)
ls daemon/build.zig 2>/dev/null && echo "daemon/"

# Client apps — each subdirectory is a target
ls -d app/*/ 2>/dev/null
```

This produces paths like `modules/libitshell3-ime/`, `daemon/`, `app/macos/`.
These paths are the **target directories**.

### Step 2: Match argument to target

Fuzzy-match the argument against discovered target directory names. Examples
(not exhaustive — always discover from filesystem):

- `ime` → `modules/libitshell3-ime`
- `protocol` → `modules/libitshell3-protocol`
- `client` or `client-sdk` → `modules/libitshell3-client`
- `core` or `libitshell3` → `modules/libitshell3`
- `daemon` → `daemon`
- `macos` or `app` → `app/macos`

If no match or ambiguous, show all discovered targets and ask the user to
clarify. If the target directory does not exist yet, confirm with the user that
this is a new target before proceeding (Step 1 will create it).

The resolved path (e.g., `modules/libitshell3-ime`) is referred to as `<target>`
throughout all step files.

### Step 3: Resolve team directory

Implementation teams use a shared agent directory: `.claude/agents/impl-team/`.

Use `ls -la` on the team directory to discover members (may include symlinks).
